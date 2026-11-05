"""MomoPet 单文件启动器（由 PyInstaller 打成 MomoPet.exe）。

Flutter Windows 程序无法真正「单文件」：运行时需要 flutter_windows.dll、插件 dll
和 data\\ 目录。这个启动器把整个绿色版压缩包作为资源内嵌，首次双击时按内容哈希
释放到 %LOCALAPPDATA%\\MomoPet\\runtime\\<hash>\\，之后直接启动里面的 momopet.exe。

- 内容哈希做目录名：exe 更新后自动释放新版本，不用手工维护版本号。
- 不等待子进程：launcher 退出后宠物继续运行，PyInstaller 的临时目录可安全清理。
- 子进程带 CREATE_BREAKAWAY_FROM_JOB：宿主（自动化工具、终端复用器）常用
  kill-on-close 的 Job 对象管理命令树，不脱离的话 launcher 一退出、
  宠物就被连带回收 —— 症状是「进程起过又静默消失」。Job 不允许 breakaway 时
  （ERROR_ACCESS_DENIED）退回普通创建，Explorer 双击路径本来就没有 Job。
- 无控制台（--noconsole），异常与子进程早退都写 %LOCALAPPDATA%\\MomoPet\\launcher.log。
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

APP_NAME = "MomoPet"
ZIP_NAME = "runtime.zip"
EXE_NAME = "momopet.exe"
MARKER = ".extracted"

CREATE_BREAKAWAY_FROM_JOB = 0x0100_0000
DETACHED_PROCESS = 0x0000_0008
CREATE_NEW_PROCESS_GROUP = 0x0000_0200


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
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with (root / "launcher.log").open("a", encoding="utf-8") as handle:
            handle.write(f"[{stamp}] {message}\n")
    except Exception:
        pass  # 没有写权限也不能影响启动


def _extract(runtime_zip: Path, target: Path) -> None:
    """释放运行时，写完整性标记。

    只检查 exe 是否存在不够：上次释放中途被杀（断电 / 杀软拦截 / 用户结束进程）
    会留下「exe 在、DLL 缺」的半成品，之后每次启动都拿到坏运行时。
    用标记文件保证释放要么完整、要么重来。
    """
    marker = target / MARKER
    if marker.exists():
        return
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(runtime_zip) as archive:
        archive.extractall(target)
    marker.write_text(time.strftime("%Y-%m-%d %H:%M:%S"), encoding="utf-8")
    _log(f"extracted runtime -> {target}")


def _prune_stale(runtime_root: Path, keep: str) -> None:
    """清理旧版本的释放目录。失败不影响启动（文件被占用很正常）。"""
    try:
        for child in runtime_root.iterdir():
            if child.name != keep and child.is_dir():
                for descendant in sorted(child.rglob("*"), reverse=True):
                    if descendant.is_file():
                        descendant.unlink()
                    elif descendant.is_dir():
                        descendant.rmdir()
                child.rmdir()
                _log(f"pruned stale runtime {child.name}")
    except Exception as error:  # noqa: BLE001
        _log(f"prune skipped: {error!r}")


def _spawn(exe: Path, cwd: Path) -> subprocess.Popen[bytes] | None:
    """创建与宿主 Job 脱离的子进程；breakaway 被拒绝时退回普通创建。"""
    flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_BREAKAWAY_FROM_JOB
    try:
        return subprocess.Popen([str(exe)], cwd=str(cwd), close_fds=True, creationflags=flags)
    except OSError as error:
        _log(f"breakaway spawn failed ({error!r}), retry without it")
        return subprocess.Popen([str(exe)], cwd=str(cwd), close_fds=True)


def main() -> int:
    try:
        runtime_zip = _bundle_dir() / ZIP_NAME
        if not runtime_zip.exists():
            _log(f"missing embedded {ZIP_NAME}")
            return 1

        payload = runtime_zip.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()[:12]
        runtime_root = _user_root() / "runtime"
        target = runtime_root / digest
        exe = target / EXE_NAME

        _extract(runtime_zip, target)
        _prune_stale(runtime_root, digest)

        process = _spawn(exe, target)
        if process is None:  # pragma: no cover - Popen 失败会抛异常而不是返回 None
            return 1
        _log(f"launched pid={process.pid} runtime={digest}")

        # 启动后观察 3 秒：立刻退出的子进程几乎都是运行时损坏或被拦截，
        # 此时静默返回 0 会让用户以为双击没用 —— 至少要把死因留到日志里。
        time.sleep(3)
        if (code := process.poll()) is not None:
            _log(f"child exited early rc={code}")
            return 1
        return 0
    except Exception as error:  # noqa: BLE001 - 顶层兜底，写日志后静默退出
        _log(f"launch failed: {error!r}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
