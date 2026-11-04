"""ComfyUI 客户端测试：用本地假服务验证上传 / 提交 / 轮询 / 下载全链路。"""

from __future__ import annotations

import io
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from PIL import Image

from petforge import comfy


def _png() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGBA", (8, 8), (255, 120, 60, 255)).save(buffer, format="PNG")
    return buffer.getvalue()


PNG = _png()


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *args) -> None:  # noqa: D401 - 静音测试日志
        pass

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.startswith("/system_stats"):
            self._send(200, b"{}")
        elif self.path.startswith("/history/"):
            payload = {
                "pid-1": {
                    "outputs": {
                        "8": {
                            "images": [
                                {
                                    "filename": "frame_00001_.png",
                                    "subfolder": "petforge",
                                    "type": "output",
                                }
                            ]
                        }
                    },
                    "status": {"status_str": "success", "completed": True},
                }
            }
            self._send(200, json.dumps(payload).encode())
        elif self.path.startswith("/view"):
            self.server.state["view_query"] = self.path
            self._send(200, PNG, "image/png")
        else:
            self._send(404, b"{}")

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        if self.path == "/upload/image":
            self.server.state["upload"] = body
            payload = {"name": "petforge_base.png", "subfolder": "", "type": "input"}
            self._send(200, json.dumps(payload).encode())
        elif self.path == "/prompt":
            self.server.state["prompt"] = json.loads(body.decode("utf-8"))
            self._send(200, json.dumps({"prompt_id": "pid-1", "number": 1}).encode())
        else:
            self._send(404, b"{}")


class ComfyClientTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self.server.state = {}
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.host = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()

    def test_generate_frame_roundtrip(self) -> None:
        self.assertTrue(comfy.is_available(self.host, timeout=2))
        options = comfy.ComfyOptions(
            host=self.host,
            checkpoint="fake.safetensors",
            timeout=5,
            poll_interval=0.02,
        )

        image = comfy.generate_frame(b"base-image-bytes", prompt="a cute cat", seed=7, options=options)

        self.assertEqual(image, PNG)
        # 底图确实以 multipart 上传了
        self.assertIn(b"petforge_base.png", self.server.state["upload"])
        self.assertIn(b"base-image-bytes", self.server.state["upload"])
        # 工作流占位符按类型注入
        prompt = self.server.state["prompt"]["prompt"]
        self.assertEqual(prompt["6"]["inputs"]["seed"], 7)
        self.assertEqual(prompt["6"]["inputs"]["denoise"], 0.45)
        self.assertEqual(prompt["4"]["inputs"]["text"], "a cute cat")
        self.assertEqual(prompt["1"]["inputs"]["ckpt_name"], "fake.safetensors")
        # 下载时带上了 ComfyUI 的 subfolder
        self.assertIn("subfolder=petforge", self.server.state["view_query"])


if __name__ == "__main__":
    unittest.main()
