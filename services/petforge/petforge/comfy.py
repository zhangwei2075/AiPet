"""极简 ComfyUI 客户端：提交 API 格式工作流、上传底图、取回输出图。

只依赖标准库。工作流里的占位符会被替换：

    {{image}}      上传后的文件名
    {{prompt}}     正向提示词
    {{negative}}   负向提示词
    {{seed}}       随机种子（int）
    {{denoise}}    img2img 重绘幅度（float）
    {{checkpoint}} checkpoint 名称
    {{steps}}      采样步数（int）
    {{cfg}}        CFG（float）

不要求安装 ComfyUI 的 Python 包，也不要求它和 PetForge 在同一台机器之外暴露。
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

BASE_PROMPT = (
    "the same pet character, identical fur color and markings, "
    "2d sticker illustration, clean white outline, transparent background, "
    "full body, centered"
)

DEFAULT_NEGATIVE = (
    "different character, extra limbs, extra ears, deformed paws, text, watermark, "
    "photo background, blurry, low quality, multiple pets"
)

DEFAULT_HOST = os.environ.get("PETFORGE_COMFY", "http://127.0.0.1:8188").rstrip("/")


class ComfyError(RuntimeError):
    """ComfyUI 调用失败（不可达、工作流被拒、超时等）。"""


@dataclass
class ComfyOptions:
    host: str = DEFAULT_HOST
    workflow: Path | None = None
    checkpoint: str | None = None
    timeout: float = 240.0
    poll_interval: float = 0.8
    denoise: float = 0.45
    steps: int = 20
    cfg: float = 6.5
    negative: str = DEFAULT_NEGATIVE


def default_workflow_path() -> Path:
    return Path(__file__).resolve().parent.parent / "workflows" / "img2img_frames.api.json"


def load_workflow(path: Path | None = None) -> dict[str, Any]:
    target = Path(path) if path else default_workflow_path()
    if not target.exists():
        raise ComfyError(f"找不到工作流文件：{target}")
    try:
        data = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ComfyError(f"工作流无法解析：{target}（{error}）") from error
    if not isinstance(data, dict) or not data:
        raise ComfyError(f"工作流为空或格式不对：{target}")
    # 允许文件里包一层 {"prompt": {...}}
    if set(data.keys()) == {"prompt"} and isinstance(data["prompt"], dict):
        data = data["prompt"]
    return data


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #


def _request(
    method: str,
    url: str,
    *,
    data: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 30.0,
) -> bytes:
    request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:800]
        raise ComfyError(f"ComfyUI HTTP {error.code}：{body}") from error
    except urllib.error.URLError as error:
        raise ComfyError(f"ComfyUI 连接失败：{error.reason}") from error
    except TimeoutError as error:
        raise ComfyError("ComfyUI 请求超时") from error


def is_available(host: str = DEFAULT_HOST, timeout: float = 0.8) -> bool:
    base = host.rstrip("/")
    for path in ("/system_stats", "/queue"):
        try:
            _request("GET", f"{base}{path}", timeout=timeout)
            return True
        except ComfyError:
            continue
    return False


def upload_image(host: str, png: bytes, filename: str = "petforge_base.png") -> str:
    """上传底图到 ComfyUI input 目录，返回 LoadImage 能用的名字。"""
    base = host.rstrip("/")
    boundary = f"----petforge{uuid.uuid4().hex}"
    parts = [
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="image"; filename="{filename}"\r\n'.encode(),
        b"Content-Type: image/png\r\n\r\n",
        png,
        b"\r\n",
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="overwrite"\r\n\r\n',
        b"true\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    body = b"".join(parts)
    raw = _request(
        "POST",
        f"{base}/upload/image",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        timeout=30,
    )
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise ComfyError("上传底图返回的不是 JSON") from error
    name = payload.get("name")
    subfolder = payload.get("subfolder") or ""
    if not name:
        raise ComfyError(f"上传底图失败：{payload}")
    return f"{subfolder}/{name}" if subfolder else name


def _first_checkpoint(host: str) -> str | None:
    try:
        raw = _request("GET", f"{host.rstrip('/')}/object_info/CheckpointLoaderSimple", timeout=10)
        payload = json.loads(raw.decode("utf-8"))
        names = payload["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"][0]
        return str(names[0]) if names else None
    except (ComfyError, KeyError, IndexError, TypeError, json.JSONDecodeError):
        return None


def inject(node: Any, values: dict[str, Any]) -> Any:
    """递归替换工作流里的占位符；整串占位符保留原始类型。"""
    if isinstance(node, dict):
        return {key: inject(value, values) for key, value in node.items()}
    if isinstance(node, list):
        return [inject(value, values) for value in node]
    if isinstance(node, str):
        if node.startswith("{{") and node.endswith("}}"):
            key = node[2:-2].strip()
            return values.get(key, node)
        for key, value in values.items():
            node = node.replace("{{" + key + "}}", str(value))
        return node
    return node


def queue_prompt(host: str, workflow: dict[str, Any]) -> str:
    body = json.dumps({"prompt": workflow, "client_id": uuid.uuid4().hex}).encode("utf-8")
    raw = _request(
        "POST",
        f"{host.rstrip('/')}/prompt",
        data=body,
        headers={"Content-Type": "application/json"},
        timeout=30,
    )
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise ComfyError("提交工作流返回的不是 JSON") from error
    if payload.get("node_errors"):
        raise ComfyError(f"工作流校验失败：{json.dumps(payload['node_errors'], ensure_ascii=False)[:600]}")
    prompt_id = payload.get("prompt_id")
    if not prompt_id:
        raise ComfyError(f"提交工作流失败：{payload}")
    return str(prompt_id)


def _history(host: str, prompt_id: str) -> dict[str, Any] | None:
    raw = _request("GET", f"{host.rstrip('/')}/history/{prompt_id}", timeout=30)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return None
    entry = payload.get(prompt_id)
    return entry if isinstance(entry, dict) else None


def wait_for_images(host: str, prompt_id: str, options: ComfyOptions) -> list[bytes]:
    deadline = time.monotonic() + options.timeout
    entry: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        entry = _history(host, prompt_id)
        if entry:
            status = entry.get("status") or {}
            if status.get("status_str") == "error":
                raise ComfyError(f"ComfyUI 执行失败：{json.dumps(status, ensure_ascii=False)[:600]}")
            if entry.get("outputs"):
                break
        time.sleep(options.poll_interval)
    else:
        raise ComfyError(f"ComfyUI 生成超时（{options.timeout:.0f}s）")

    images: list[bytes] = []
    for output in (entry or {}).get("outputs", {}).values():
        for image in output.get("images", []):
            if image.get("type", "output") != "output":
                continue
            query = urllib.parse.urlencode(
                {
                    "filename": image.get("filename", ""),
                    "subfolder": image.get("subfolder", ""),
                    "type": image.get("type", "output"),
                }
            )
            images.append(_request("GET", f"{host.rstrip('/')}/view?{query}", timeout=60))
    if not images:
        raise ComfyError("ComfyUI 没有返回图片")
    return images


def generate_frame(
    base_png: bytes,
    *,
    prompt: str,
    seed: int,
    options: ComfyOptions | None = None,
) -> bytes:
    """用底图 + 提示词生成一帧，返回 PNG 字节。"""
    options = options or ComfyOptions()
    host = options.host.rstrip("/")
    workflow = load_workflow(options.workflow)

    checkpoint = options.checkpoint or _first_checkpoint(host)
    if not checkpoint:
        raise ComfyError("没有可用的 checkpoint：请在 ComfyUI 里放一个模型，或用 --checkpoint 指定")

    image_name = upload_image(host, base_png, filename="petforge_base.png")
    workflow = inject(
        workflow,
        {
            "image": image_name,
            "prompt": prompt,
            "negative": options.negative,
            "seed": int(seed),
            "denoise": float(options.denoise),
            "checkpoint": checkpoint,
            "steps": int(options.steps),
            "cfg": float(options.cfg),
        },
    )
    prompt_id = queue_prompt(host, workflow)
    images = wait_for_images(host, prompt_id, options)
    return images[0]
