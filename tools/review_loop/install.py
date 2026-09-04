"""Install and manage the autonomous PR review watcher.

The preferred runtime is an Antigravity sidecar because only a sidecar receives
the official ``agentapi`` executable needed to message an existing GUI
conversation. Windows Task Scheduler and systemd remain fallback launchers.
"""
import argparse
import getpass
import html
import json
import os
import platform
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import (
    DEFAULT_LOG_FILE,
    DEFAULT_PID_FILE,
    REPO_ROOT,
    REVIEW_LOOP_DIR,
    RUN_WATCHER_BAT,
    SIDECAR_MARKER_FILE,
)

WINDOWS_TASK_NAME = "CubeSiegeReviewLoopWatcher"
LINUX_SERVICE_NAME = "cube-siege-review-watcher.service"
ANTIGRAVITY_SIDECAR_ID = "cube-siege-review-loop"


def is_pid_running(pid: int) -> bool:
    """Return whether a process exists."""
    if pid <= 0:
        return False
    if sys.platform == "win32":
        try:
            import ctypes
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            handle = kernel32.OpenProcess(0x1000, False, pid)
            if handle:
                kernel32.CloseHandle(handle)
                return True
            return ctypes.get_last_error() == 5
        except Exception:
            return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def get_current_pid() -> int:
    try:
        return int(DEFAULT_PID_FILE.read_text(encoding="utf-8").strip())
    except Exception:
        return 0


def wait_for_watcher(timeout: float = 15.0) -> bool:
    """Wait until the watcher has claimed its PID file."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pid = get_current_pid()
        if pid and is_pid_running(pid):
            return True
        time.sleep(0.25)
    return False


# ================= Antigravity sidecar =================

def get_antigravity_config_root() -> Path:
    return Path.home() / ".gemini" / "config"


def _write_json_atomic(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    temp_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temp_path, path)


def is_antigravity_sidecar_enabled(config_root: Optional[Path] = None) -> bool:
    root = config_root or get_antigravity_config_root()
    try:
        config = json.loads((root / "config.json").read_text(encoding="utf-8"))
        enabled = bool(
            config.get("sidecars", {})
            .get(ANTIGRAVITY_SIDECAR_ID, {})
            .get("enabled")
        )
        manifest = root / "sidecars" / ANTIGRAVITY_SIDECAR_ID / "sidecar.json"
        return enabled and manifest.exists()
    except (OSError, ValueError, TypeError):
        return False


def install_antigravity_sidecar(config_root: Optional[Path] = None) -> bool:
    """Install a global sidecar while preserving unrelated Antigravity config."""
    root = config_root or get_antigravity_config_root()
    config_path = root / "config.json"
    sidecar_path = root / "sidecars" / ANTIGRAVITY_SIDECAR_ID / "sidecar.json"
    watcher_path = REPO_ROOT / "tools" / "review_loop" / "watcher.py"
    try:
        config: Dict[str, Any] = {}
        if config_path.exists():
            config = json.loads(config_path.read_text(encoding="utf-8"))
            if not isinstance(config, dict):
                raise ValueError("Antigravity config.json root must be an object")
        sidecars = config.setdefault("sidecars", {})
        if not isinstance(sidecars, dict):
            raise ValueError("Antigravity config.json sidecars must be an object")
        sidecars[ANTIGRAVITY_SIDECAR_ID] = {"enabled": True}

        sidecar = {
            "description": "Watch Cube Siege PR reviews and wake the attached Antigravity conversation.",
            "display_name": "Cube Siege PR Review Loop",
            "command": sys.executable,
            "args": [str(watcher_path)],
            "restart_policy": "always",
            "env": {"PYTHONUNBUFFERED": "1"},
        }
        _write_json_atomic(sidecar_path, sidecar)
        _write_json_atomic(config_path, config)
        REVIEW_LOOP_DIR.mkdir(parents=True, exist_ok=True)
        SIDECAR_MARKER_FILE.write_text(
            "Managed by Antigravity sidecar; fallback launchers must remain idle.\n",
            encoding="utf-8",
        )
        print(f"[SUCCESS] Enabled Antigravity sidecar '{ANTIGRAVITY_SIDECAR_ID}'.")
        print("Restart Antigravity once if the watcher is not already running.")
        return True
    except Exception as exc:
        print(f"[WARN] Could not install Antigravity sidecar: {exc}")
        return False


def uninstall_antigravity_sidecar(config_root: Optional[Path] = None) -> bool:
    root = config_root or get_antigravity_config_root()
    config_path = root / "config.json"
    try:
        if config_path.exists():
            config = json.loads(config_path.read_text(encoding="utf-8"))
            sidecars = config.get("sidecars", {})
            if isinstance(sidecars, dict):
                sidecars.pop(ANTIGRAVITY_SIDECAR_ID, None)
            _write_json_atomic(config_path, config)
        if SIDECAR_MARKER_FILE.exists():
            SIDECAR_MARKER_FILE.unlink()
        return True
    except Exception as exc:
        print(f"[WARN] Could not disable Antigravity sidecar: {exc}")
        return False


# ================= Windows fallback =================

def create_windows_launcher() -> Path:
    REVIEW_LOOP_DIR.mkdir(parents=True, exist_ok=True)
    watcher_path = REPO_ROOT / "tools" / "review_loop" / "watcher.py"
    content = (
        "@echo off\n"
        f'if exist "{SIDECAR_MARKER_FILE}" exit /b 0\n'
        f'cd /d "{REPO_ROOT}"\n'
        f'"{sys.executable}" "{watcher_path}" %*\n'
    )
    RUN_WATCHER_BAT.write_text(content, encoding="utf-8")
    return RUN_WATCHER_BAT


def build_windows_task_xml() -> str:
    """Build a per-user task that restarts the watcher after failures."""
    launcher = html.escape(str(create_windows_launcher()))
    user = html.escape(getpass.getuser())
    return f'''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals><Principal id="Author"><UserId>{user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure><Interval>PT1M</Interval><Count>999</Count></RestartOnFailure>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>{launcher}</Command><WorkingDirectory>{html.escape(str(REPO_ROOT))}</WorkingDirectory></Exec></Actions>
</Task>'''


def is_windows_task_installed() -> bool:
    result = subprocess.run(
        ["schtasks", "/query", "/tn", WINDOWS_TASK_NAME],
        cwd=str(REPO_ROOT), capture_output=True, text=True, errors="replace",
    )
    return result.returncode == 0


def install_windows() -> bool:
    xml_text = build_windows_task_xml()
    temp_path: Optional[Path] = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".xml", delete=False, encoding="utf-16"
        ) as temp_file:
            temp_file.write(xml_text)
            temp_path = Path(temp_file.name)
        result = subprocess.run(
            ["schtasks", "/create", "/tn", WINDOWS_TASK_NAME, "/xml", str(temp_path), "/f"],
            cwd=str(REPO_ROOT), capture_output=True, text=True, errors="replace",
        )
        if result.returncode == 0:
            print(f"[SUCCESS] Scheduled Task '{WINDOWS_TASK_NAME}' configured.")
            return True
        print(f"[WARN] Failed to configure Scheduled Task: {result.stderr.strip() or result.stdout.strip()}")
        return False
    finally:
        if temp_path:
            try:
                temp_path.unlink()
            except OSError:
                pass


def start_windows() -> bool:
    pid = get_current_pid()
    if pid and is_pid_running(pid):
        return True
    if is_windows_task_installed():
        subprocess.run(
            ["schtasks", "/run", "/tn", WINDOWS_TASK_NAME],
            cwd=str(REPO_ROOT), capture_output=True, errors="replace",
        )
        if wait_for_watcher():
            return True
    launcher = create_windows_launcher()
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    subprocess.Popen(
        [str(launcher)], cwd=str(REPO_ROOT), creationflags=flags,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
    )
    return wait_for_watcher()


def stop_windows() -> bool:
    subprocess.run(
        ["schtasks", "/end", "/tn", WINDOWS_TASK_NAME],
        cwd=str(REPO_ROOT), capture_output=True, errors="replace",
    )
    pid = get_current_pid()
    if pid and is_pid_running(pid):
        subprocess.run(
            ["taskkill", "/F", "/PID", str(pid)],
            cwd=str(REPO_ROOT), capture_output=True, errors="replace",
        )
    try:
        DEFAULT_PID_FILE.unlink()
    except OSError:
        pass
    return True


def uninstall_windows() -> bool:
    stop_windows()
    subprocess.run(
        ["schtasks", "/delete", "/tn", WINDOWS_TASK_NAME, "/f"],
        cwd=str(REPO_ROOT), capture_output=True, errors="replace",
    )
    return True


# ================= Linux fallback =================

def install_linux() -> bool:
    watcher_path = REPO_ROOT / "tools" / "review_loop" / "watcher.py"
    service_dir = Path.home() / ".config" / "systemd" / "user"
    service_dir.mkdir(parents=True, exist_ok=True)
    service_path = service_dir / LINUX_SERVICE_NAME
    service_path.write_text(
        "[Unit]\nDescription=Cube Siege Antigravity PR Review Feedback Watcher\nAfter=network.target\n\n"
        "[Service]\nType=simple\n"
        f"WorkingDirectory={REPO_ROOT}\nExecStart={sys.executable} {watcher_path}\n"
        "Restart=on-failure\nRestartSec=10\n\n[Install]\nWantedBy=default.target\n",
        encoding="utf-8",
    )
    reload_result = subprocess.run(
        ["systemctl", "--user", "daemon-reload"], cwd=str(REPO_ROOT), capture_output=True, text=True,
    )
    if reload_result.returncode != 0:
        return False
    enable_result = subprocess.run(
        ["systemctl", "--user", "enable", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), capture_output=True, text=True,
    )
    return enable_result.returncode == 0


def start_linux() -> bool:
    result = subprocess.run(
        ["systemctl", "--user", "start", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), capture_output=True, text=True,
    )
    if result.returncode == 0 and wait_for_watcher():
        return True
    subprocess.Popen([sys.executable, str(REPO_ROOT / "tools" / "review_loop" / "watcher.py")], cwd=str(REPO_ROOT))
    return wait_for_watcher()


def stop_linux() -> bool:
    subprocess.run(["systemctl", "--user", "stop", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), check=False)
    pid = get_current_pid()
    if pid and is_pid_running(pid):
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    return True


def uninstall_linux() -> bool:
    stop_linux()
    subprocess.run(["systemctl", "--user", "disable", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), check=False)
    service_path = Path.home() / ".config" / "systemd" / "user" / LINUX_SERVICE_NAME
    try:
        service_path.unlink()
    except OSError:
        pass
    subprocess.run(["systemctl", "--user", "daemon-reload"], cwd=str(REPO_ROOT), check=False)
    return True


# ================= Common dispatch =================

def ensure_service() -> bool:
    """Ensure the sidecar watcher is alive before creating/registering a PR."""
    pid = get_current_pid()
    if pid and is_pid_running(pid):
        return True
    if is_antigravity_sidecar_enabled():
        if wait_for_watcher():
            return True
        print("[WARN] Antigravity sidecar is enabled but not running. Restart Antigravity and retry.")
        return False
    if not install_service():
        return False
    if is_antigravity_sidecar_enabled():
        return wait_for_watcher()
    return start_service()


def install_service() -> bool:
    if install_antigravity_sidecar():
        # Keep any legacy Windows task harmless if it cannot be removed.
        if sys.platform == "win32":
            create_windows_launcher()
        return True
    if sys.platform == "win32":
        return install_windows()
    if sys.platform.startswith("linux"):
        return install_linux()
    return False


def start_service() -> bool:
    if is_antigravity_sidecar_enabled():
        if wait_for_watcher():
            return True
        print("[WARN] Restart Antigravity to start the configured sidecar.")
        return False
    return start_windows() if sys.platform == "win32" else start_linux()


def stop_service() -> bool:
    return stop_windows() if sys.platform == "win32" else stop_linux()


def uninstall_service() -> bool:
    sidecar_ok = uninstall_antigravity_sidecar()
    fallback_ok = uninstall_windows() if sys.platform == "win32" else uninstall_linux()
    return sidecar_ok and fallback_ok


def print_status() -> None:
    pid = get_current_pid()
    running = bool(pid and is_pid_running(pid))
    print("=" * 60)
    print(" Cube Siege - Review Loop Watcher Status")
    print("=" * 60)
    print(f"Platform: {platform.system()} ({platform.release()})")
    print(f"Repository Root: {REPO_ROOT}")
    print(f"Antigravity Sidecar: [{'ENABLED' if is_antigravity_sidecar_enabled() else 'DISABLED'}]")
    print(f"Process Status: [{'RUNNING' if running else 'STOPPED'}]" + (f" (PID: {pid})" if running else ""))
    print(f"Log file: {DEFAULT_LOG_FILE}")
    if DEFAULT_LOG_FILE.exists():
        print("\n--- Recent Log Activity (last 10 lines) ---")
        for line in DEFAULT_LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()[-10:]:
            print(f"  {line}")
    print("=" * 60)


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage the PR review watcher.")
    parser.add_argument("action", choices=["install", "ensure", "uninstall", "start", "stop", "status"])
    args = parser.parse_args()
    actions = {
        "install": install_service,
        "ensure": ensure_service,
        "uninstall": uninstall_service,
        "start": start_service,
        "stop": stop_service,
    }
    if args.action == "status":
        print_status()
        return
    raise SystemExit(0 if actions[args.action]() else 1)


if __name__ == "__main__":
    main()
