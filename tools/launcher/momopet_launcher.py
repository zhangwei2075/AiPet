"""MomoPet 单文件启动器（由 PyInstaller 打成 MomoPet.exe）。

Flutter Windows 程序无法真正「单文件」：运行时需要 flutter_windows.dll、插件 dll
和 data\\ 目录。这个启动器把整个绿色版压缩包作为资源内嵌，首次双击时按内容哈希
释放到 %LOCALAPPDATA%\\MomoPet\\runtime\\<hash>\\，之后直接启动里面的 momopet.exe。

- 内容哈希做目录名：exe 更新后自动释放新版本，不用手工维护版本号。
- 不等待子进程：launcher 退出后宠物继续运行，PyInstaller 的临时目录可安全清理。
- 无控制台（--noconsole），异常写 %LOCALAPPDATA%\\MomoPet\\launcher.log。
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

APP_NAME = "MomoPet"
ZIP_NAME = "runtime.zip"
EXE_NAME = "momopet.exe"


def _bundle_dir() -> Path:
    """PyInstaller --onefile 解压出的资源目录；开发时退化为脚本所在目录。"""
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
    return Path(__file__).resolve().parent


def _user_root() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or tempfile.gettempdir()) / APP_NAME


def _log(message: str) -> None:
    try:
        root = _user_root()
        root.mkdir(parents=True, exist_ok=True)
        with (root / "launcher.log").open("a", encoding="utf-8") as handle:
            handle.write(message + "\n")
    except Exception:
        pass  # 没有写权限也不能影响启动


def main() -> int:
    try:
        runtime_zip = _bundle_dir() / ZIP_NAME
        if not runtime_zip.exists():
            _log(f"missing embedded {ZIP_NAME}")
            return 1

        payload = runtime_zip.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()[:12]
        target = _user_root() / "runtime" / digest
        exe = target / EXE_NAME

        if not exe.exists():
            target.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(runtime_zip) as archive:
                archive.extractall(target)

        subprocess.Popen([str(exe)], cwd=str(target), close_fds=True)
        return 0
    except Exception as error:  # noqa: BLE001 - 顶层兜底，写日志后静默退出
        _log(f"launch failed: {error!r}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
