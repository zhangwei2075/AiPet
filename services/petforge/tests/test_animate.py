"""动画管线单元测试：不需要 ComfyUI，也不依赖 rembg。"""

from __future__ import annotations

import io
import json
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from petforge import comfy
from petforge.animate import (
    AnimateOptions,
    Pose,
    align_like_base,
    dedupe,
    generate_animation,
    render_pose,
    write_pack_animation,
)

ROOT = Path(__file__).resolve().parent.parent


def _pet_image(size: int = 256) -> Image.Image:
    """画一只简单的透明底小猫，代替真实照片。"""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    body = (size * 0.22, size * 0.38, size * 0.78, size * 0.94)
    draw.ellipse(body, fill=(245, 176, 96, 255))
    head = (size * 0.28, size * 0.14, size * 0.72, size * 0.58)
    draw.ellipse(head, fill=(245, 176, 96, 255))
    draw.polygon(
        [(size * 0.30, size * 0.22), (size * 0.38, size * 0.06), (size * 0.47, size * 0.22)],
        fill=(230, 143, 72, 255),
    )
    draw.polygon(
        [(size * 0.53, size * 0.22), (size * 0.62, size * 0.06), (size * 0.70, size * 0.22)],
        fill=(230, 143, 72, 255),
    )
    draw.ellipse((size * 0.39, size * 0.31, size * 0.44, size * 0.36), fill=(60, 44, 34, 255))
    draw.ellipse((size * 0.56, size * 0.31, size * 0.61, size * 0.36), fill=(60, 44, 34, 255))
    return image


class AnimateTest(unittest.TestCase):
    def test_render_pose_keeps_canvas(self) -> None:
        base = _pet_image()
        frame = render_pose(base, Pose(1.02, 0.98, 3.0, 0.01, -0.02))
        self.assertEqual(frame.size, base.size)
        self.assertEqual(frame.mode, "RGBA")

    def test_procedural_frames_and_atlas(self) -> None:
        result = generate_animation(
            _pet_image(),
            AnimateOptions(actions=("idle", "walk", "run", "lie"), atlas=True),
        )
        self.assertEqual(result.engine, "procedural")
        self.assertIsNone(result.fallback)
        self.assertEqual(set(result.animations), {"idle", "walk", "run", "lie"})

        for action, data in result.animations.items():
            self.assertGreaterEqual(len(data["frames"]), 2, action)
            self.assertGreater(data["fps"], 0)
            for filename in data["frames"]:
                self.assertIn(filename[:-4], result.images)

        # 同一动作里不能有完全重复的帧
        for data in result.animations.values():
            blobs = [result.images[name[:-4]] for name in data["frames"]]
            self.assertEqual(len(blobs), len(set(blobs)))

        self.assertIsNotNone(result.atlas)
        atlas = result.atlas or {}
        self.assertIn("atlas", result.images)
        self.assertEqual(atlas["cell"], 256)
        self.assertEqual(len(atlas["frames"]), sum(len(d["frames"]) for d in result.animations.values()))
        for rect in atlas["frames"].values():
            self.assertEqual(len(rect), 4)
            self.assertEqual(rect[2], 256)

    def test_frame_size_capped_at_512(self) -> None:
        result = generate_animation(
            _pet_image(640),
            AnimateOptions(actions=("walk",), atlas=True),
        )
        frame = Image.open(io.BytesIO(result.images["walk_0"]))
        self.assertEqual(frame.size, (512, 512))
        self.assertEqual((result.atlas or {})["cell"], 512)

    def test_align_like_base_keeps_bottom(self) -> None:
        base = _pet_image(256)
        frame = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rectangle((90, 110, 170, 240), fill=(200, 80, 60, 255))

        aligned = align_like_base(frame, base)
        base_box = base.getbbox()
        frame_box = aligned.getbbox()
        self.assertIsNotNone(base_box)
        self.assertIsNotNone(frame_box)
        self.assertEqual(aligned.size, base.size)
        # 底边对齐，避免 AI 帧上下漂移
        self.assertAlmostEqual(frame_box[3], base_box[3], delta=1)

    def test_dedupe_drops_identical_frames(self) -> None:
        base = _pet_image()
        self.assertEqual(len(dedupe([base, base, base])), 2)
        self.assertEqual(dedupe([]), [])

    def test_pack_merge(self) -> None:
        pack = {"schemaVersion": 1, "metrics": {"cutout": "flat"}}
        result = generate_animation(_pet_image(), AnimateOptions(actions=("walk",), atlas=True))
        write_pack_animation(pack, result)
        self.assertIn("walk", pack["animations"])
        self.assertEqual(pack["metrics"]["animate"], "procedural")
        self.assertIn("atlas", pack)
        json.dumps(pack, ensure_ascii=False)

    def test_workflow_injection(self) -> None:
        workflow = comfy.load_workflow()
        injected = comfy.inject(
            workflow,
            {
                "image": "petforge_base.png",
                "prompt": "a cat",
                "negative": "dog",
                "seed": 123,
                "denoise": 0.4,
                "checkpoint": "sd15.safetensors",
                "steps": 24,
                "cfg": 7.0,
            },
        )
        sampler = injected["6"]["inputs"]
        self.assertEqual(sampler["seed"], 123)
        self.assertIsInstance(sampler["seed"], int)
        self.assertEqual(sampler["denoise"], 0.4)
        self.assertEqual(injected["1"]["inputs"]["ckpt_name"], "sd15.safetensors")
        self.assertEqual(injected["4"]["inputs"]["text"], "a cat")
        self.assertNotIn("{{", json.dumps(injected))

    def test_comfyui_unavailable_falls_back(self) -> None:
        host = "http://127.0.0.1:65533"
        self.assertFalse(comfy.is_available(host, timeout=0.2))
        result = generate_animation(
            _pet_image(),
            AnimateOptions(engine="comfyui", actions=("walk",), comfy=comfy.ComfyOptions(host=host)),
        )
        self.assertEqual(result.engine, "procedural")
        self.assertIsNotNone(result.fallback)
        self.assertIn("walk", result.animations)


if __name__ == "__main__":
    unittest.main()
