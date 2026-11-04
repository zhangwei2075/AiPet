"""PetForge HTTP API —— 本地/局域网运行，App 通过 127.0.0.1:8787 调用。

启动:
    python -m petforge            (默认 127.0.0.1:8787)
    uvicorn petforge.api:app --port 8787
"""

from __future__ import annotations

import time
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import UnidentifiedImageError
from starlette.concurrency import run_in_threadpool

from .animate import AnimateOptions, generate_animation, write_pack_animation
from .pipeline import Options, generate

MAX_UPLOAD = 15 * 1024 * 1024
ANIMATION_ENGINES = {"procedural", "comfyui"}

app = FastAPI(
    title="PetForge",
    version="0.1.0",
    description="把任意照片变成桌面宠物贴纸（抠图 / 调色板 / 性格 / 锚点）",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict:
    import cv2

    from . import comfy

    try:
        import rembg  # type: ignore  # noqa: F401

        rembg_ready = True
    except Exception:
        rembg_ready = False
    comfy_ready = comfy.is_available(timeout=0.6)
    return {
        "ok": True,
        "service": "petforge",
        "version": app.version,
        "capabilities": {
            "opencv": cv2.__version__,
            "rembg": rembg_ready,
            "cutoutChain": ["rembg", "flat", "grabcut", "oval"],
            "animate": {
                "procedural": True,
                "comfyui": comfy_ready,
                "comfyHost": comfy.DEFAULT_HOST,
            },
        },
    }


@app.post("/api/generate")
async def generate_pet(
    file: UploadFile = File(...),
    style: str = Form("sticker"),
    name: str | None = Form(None),
    removeBg: bool = Form(True),
    animate: bool = Form(False),
    engine: str = Form("procedural"),
    atlas: bool = Form(False),
    subject: str = Form(""),
    workflow: str = Form(""),
) -> dict:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_UPLOAD:
        raise HTTPException(status_code=413, detail="image too large (max 15MB)")
    if style not in {"sticker", "soft", "original"}:
        raise HTTPException(status_code=422, detail="style must be sticker|soft|original")
    if engine not in ANIMATION_ENGINES:
        raise HTTPException(status_code=422, detail="engine must be procedural|comfyui")

    started = time.perf_counter()
    try:
        pet = await run_in_threadpool(
            generate,
            data,
            Options(style=style, name=name.strip() if name else None, remove_bg=removeBg),
        )
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(status_code=400, detail=f"cannot read image: {exc}") from exc

    if animate:
        comfy_options = None
        if engine == "comfyui" and workflow.strip():
            from .comfy import ComfyOptions

            comfy_options = ComfyOptions(workflow=Path(workflow.strip()))
        result = await run_in_threadpool(
            generate_animation,
            pet.images["base"],
            AnimateOptions(
                engine=engine,
                style=style,
                atlas=atlas,
                subject=subject,
                comfy=comfy_options,
            ),
        )
        pet.images.update(result.images)
        write_pack_animation(pet.pack, result)

    payload = pet.pack_with_base64()
    payload["elapsedMs"] = round((time.perf_counter() - started) * 1000)
    return payload


@app.post("/api/preview")
async def preview(file: UploadFile = File(...), style: str = Form("sticker")) -> dict:
    """只返回图片，用于「生成过程」里的快速预览。"""
    data = await file.read()
    try:
        pet = generate(data, Options(style=style))
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"image": pet.pack_with_base64()["images"]["base"]}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("petforge.api:app", host="127.0.0.1", port=8787, reload=False)
