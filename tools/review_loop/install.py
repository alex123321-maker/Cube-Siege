"""
tools/review_loop/install.py - Service installer and lifecycle manager.

Configures per-user background watcher service on Windows (Task Scheduler with proper cwd)
and Linux (systemd --user).
"""
import argparse
import getpass
import html
import os
import platform
import subprocess
import sys
import tempfile
import time
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import (
    DEFAULT_LOG_FILE,
    DEFAULT_PID_FILE,
    REPO_ROOT,
    REVIEW_LOOP_DIR,
    RUN_WATCHER_BAT,
)

WINDOWS_TASK_NAME = "CubeSiegeReviewLoopWatcher"
LINUX_SERVICE_NAME = "cube-siege-review-watcher.service"


def is_windows_task_installed() -> bool:
    """Return whether the per-user watcher task exists."""
    res = subprocess.run(
        ["schtasks", "/query", "/tn", WINDOWS_TASK_NAME],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        errors="replace",
    )
    return res.returncode == 0


def wait_for_watcher(timeout_seconds: float = 10.0) -> bool:
    """Wait until the watcher-owned PID file points to a live process."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        pid = get_current_pid()
        if pid and is_pid_running(pid):
            return True
        time.sleep(0.25)
    return False


def build_windows_task_xml(username: str, launcher: Path) -> str:
    """Build a least-privilege logon task that restarts after failures."""
    escaped_user = html.escape(username)
    command_processor = os.environ.get(
        "ComSpec", r"C:\Windows\System32\cmd.exe"
    )
    escaped_command_processor = html.escape(command_processor)
    escaped_arguments = html.escape(f'/d /c ""{launcher}""')
    escaped_workdir = html.escape(str(REPO_ROOT))
    return f'''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Cube Siege PR review feedback watcher</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>{escaped_user}</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{escaped_user}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{escaped_command_processor}</Command>
      <Arguments>{escaped_arguments}</Arguments>
      <WorkingDirectory>{escaped_workdir}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
'''

def is_pid_running(pid: int) -> bool:
    """Check if process with PID is alive."""
    if pid <= 0:
        return False
    if sys.platform == "win32":
        try:
            res = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace"
            )
            return str(pid) in res.stdout
        except Exception:
            return False
    else:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

def get_current_pid() -> int:
    if DEFAULT_PID_FILE.exists():
        try:
            return int(DEFAULT_PID_FILE.read_text(encoding="utf-8").strip())
        except Exception:
            pass
    return 0

# ================= Windows Lifecycle =================

def create_windows_launcher() -> Path:
    """Generate a batch launcher that strictly changes directory to REPO_ROOT before running Python."""
    REVIEW_LOOP_DIR.mkdir(parents=True, exist_ok=True)
    python_exe = sys.executable
    watcher_py = REPO_ROOT / "tools" / "review_loop" / "watcher.py"

    bat_content = f"""@echo off
cd /d "{REPO_ROOT}"
"{python_exe}" "{watcher_py}" %*
"""
    RUN_WATCHER_BAT.write_text(bat_content, encoding="utf-8")
    return RUN_WATCHER_BAT

def install_windows() -> bool:
    launcher = create_windows_launcher()
    print(f"Configuring Windows Scheduled Task '{WINDOWS_TASK_NAME}' with launcher at '{launcher}'...")
    identity = subprocess.run(
        ["whoami"], capture_output=True, text=True, errors="replace"
    )
    username = identity.stdout.strip() if identity.returncode == 0 else getpass.getuser()
    task_xml = build_windows_task_xml(username, launcher)
    REVIEW_LOOP_DIR.mkdir(parents=True, exist_ok=True)
    xml_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-16",
            suffix=".xml",
            dir=REVIEW_LOOP_DIR,
            delete=False,
        ) as xml_file:
            xml_file.write(task_xml)
            xml_path = Path(xml_file.name)
        schtasks_cmd = [
            "schtasks", "/create",
            "/tn", WINDOWS_TASK_NAME,
            "/xml", str(xml_path),
            "/f",
        ]
        res = subprocess.run(
            schtasks_cmd,
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            errors="replace",
        )
    finally:
        if xml_path and xml_path.exists():
            xml_path.unlink()
    if res.returncode == 0:
        print(f"[SUCCESS] Scheduled Task '{WINDOWS_TASK_NAME}' created successfully.")
        print("Watcher will auto-start at user logon. To start now, run: python tools/review_loop/install.py start")
        return True
    else:
        print(f"[WARN] Failed to create scheduled task via schtasks: {res.stderr.strip() or res.stdout.strip()}")
        print("Fallback: You can start the background watcher anytime using: python tools/review_loop/install.py start")
        return False

def uninstall_windows() -> bool:
    stop_service()
    res = subprocess.run(
        ["schtasks", "/delete", "/tn", WINDOWS_TASK_NAME, "/f"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        errors="replace"
    )
    if RUN_WATCHER_BAT.exists():
        try:
            RUN_WATCHER_BAT.unlink()
        except Exception:
            pass
    if res.returncode == 0:
        print(f"[SUCCESS] Deleted Windows Scheduled Task '{WINDOWS_TASK_NAME}'.")
        return True
    else:
        print(f"[INFO] Task '{WINDOWS_TASK_NAME}' was not found in Task Scheduler.")
        return True

def start_windows() -> bool:
    pid = get_current_pid()
    if pid and is_pid_running(pid):
        print(f"[INFO] Review watcher is already running (PID: {pid}).")
        return True

    # First attempt to run task scheduler task
    res = subprocess.run(
        ["schtasks", "/run", "/tn", WINDOWS_TASK_NAME],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        errors="replace"
    )
    if res.returncode == 0:
        if wait_for_watcher():
            print(f"[SUCCESS] Started scheduled task '{WINDOWS_TASK_NAME}'.")
            return True
        print(
            f"[ERROR] Task '{WINDOWS_TASK_NAME}' was triggered but the watcher "
            "did not stay running. Check .review_loop/watcher.log."
        )
        return False

    # Fallback to detached process using launcher
    launcher = create_windows_launcher()
    creationflags = 0
    if hasattr(subprocess, "DETACHED_PROCESS"):
        creationflags |= subprocess.DETACHED_PROCESS
    if hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP"):
        creationflags |= subprocess.CREATE_NEW_PROCESS_GROUP

    proc = subprocess.Popen(
        [str(launcher)],
        cwd=str(REPO_ROOT),
        creationflags=creationflags,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL
    )
    if wait_for_watcher():
        print(f"[SUCCESS] Started background review watcher process (launcher PID: {proc.pid}).")
        return True
    print("[ERROR] Background watcher did not stay running. Check .review_loop/watcher.log.")
    return False

def stop_windows() -> bool:
    subprocess.run(["schtasks", "/end", "/tn", WINDOWS_TASK_NAME], cwd=str(REPO_ROOT), capture_output=True, errors="replace")

    pid = get_current_pid()
    if pid:
        if is_pid_running(pid):
            try:
                subprocess.run(["taskkill", "/F", "/PID", str(pid)], cwd=str(REPO_ROOT), capture_output=True, errors="replace")
                print(f"[SUCCESS] Terminated watcher process (PID: {pid}).")
            except Exception as e:
                print(f"[WARN] Failed to terminate PID {pid}: {e}")
        try:
            if DEFAULT_PID_FILE.exists():
                DEFAULT_PID_FILE.unlink()
        except Exception:
            pass
    else:
        print("[INFO] No active PID file found.")
    return True

# ================= Linux Lifecycle =================

def install_linux() -> bool:
    python_exe = sys.executable
    watcher_py = REPO_ROOT / "tools" / "review_loop" / "watcher.py"
    user_systemd_dir = Path.home() / ".config" / "systemd" / "user"
    user_systemd_dir.mkdir(parents=True, exist_ok=True)
    service_path = user_systemd_dir / LINUX_SERVICE_NAME

    service_content = f"""[Unit]
Description=Cube Siege Antigravity PR Review Feedback Watcher
After=network.target

[Service]
Type=simple
WorkingDirectory={REPO_ROOT}
ExecStart={python_exe} {watcher_py}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
"""
    service_path.write_text(service_content, encoding="utf-8")
    print(f"[SUCCESS] Created systemd user unit at {service_path}")

    res1 = subprocess.run(["systemctl", "--user", "daemon-reload"], cwd=str(REPO_ROOT), capture_output=True, text=True)
    if res1.returncode != 0:
        print(f"[ERROR] systemctl --user daemon-reload failed: {res1.stderr.strip() or res1.stdout.strip()}")
        return False

    res2 = subprocess.run(["systemctl", "--user", "enable", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), capture_output=True, text=True)
    if res2.returncode != 0:
        print(f"[ERROR] systemctl --user enable failed: {res2.stderr.strip() or res2.stdout.strip()}")
        return False

    print(f"[SUCCESS] Enabled {LINUX_SERVICE_NAME}.")
    print("To start service: python tools/review_loop/install.py start")
    return True

def uninstall_linux() -> bool:
    subprocess.run(["systemctl", "--user", "disable", "--now", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), check=False)
    service_path = Path.home() / ".config" / "systemd" / "user" / LINUX_SERVICE_NAME
    if service_path.exists():
        service_path.unlink()
        print(f"[SUCCESS] Removed {service_path}")
    subprocess.run(["systemctl", "--user", "daemon-reload"], cwd=str(REPO_ROOT), check=False)
    return True

def start_linux() -> bool:
    res = subprocess.run(["systemctl", "--user", "start", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), capture_output=True, text=True)
    if res.returncode == 0:
        print(f"[SUCCESS] Started {LINUX_SERVICE_NAME}")
        return True
    python_exe = sys.executable
    watcher_py = REPO_ROOT / "tools" / "review_loop" / "watcher.py"
    proc = subprocess.Popen([python_exe, str(watcher_py)], cwd=str(REPO_ROOT))
    print(f"[SUCCESS] Started background watcher process (PID: {proc.pid})")
    return True

def stop_linux() -> bool:
    subprocess.run(["systemctl", "--user", "stop", LINUX_SERVICE_NAME], cwd=str(REPO_ROOT), check=False)
    pid = get_current_pid()
    if pid and is_pid_running(pid):
        try:
            os.kill(pid, 15)
            print(f"[SUCCESS] Stopped PID {pid}")
        except Exception:
            pass
    if DEFAULT_PID_FILE.exists():
        DEFAULT_PID_FILE.unlink()
    return True

# ================= Common Status & Dispatch =================

def print_status() -> None:
    print("=" * 60)
    print(" Cube Siege - Review Loop Watcher Status")
    print("=" * 60)
    print(f"Platform: {platform.system()} ({platform.release()})")
    print(f"Repository Root: {REPO_ROOT}")
    print(f"Log file: {DEFAULT_LOG_FILE}")
    print(f"PID file: {DEFAULT_PID_FILE}")

    pid = get_current_pid()
    running = is_pid_running(pid) if pid else False

    if running:
        print(f"Process Status: [RUNNING] (PID: {pid})")
    else:
        print("Process Status: [STOPPED]")

    if sys.platform == "win32":
        res = subprocess.run(
            ["schtasks", "/query", "/tn", WINDOWS_TASK_NAME],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            errors="replace"
        )
        if res.returncode == 0:
            print(f"Scheduled Task: [CONFIGURED] ({WINDOWS_TASK_NAME})")
        else:
            print("Scheduled Task: [NOT INSTALLED]")
    elif sys.platform == "linux":
        res = subprocess.run(
            ["systemctl", "--user", "is-active", LINUX_SERVICE_NAME],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True
        )
        print(f"Systemd Service: [{res.stdout.strip() or 'inactive'}]")

    if DEFAULT_LOG_FILE.exists():
        print("\n--- Recent Log Activity (last 10 lines) ---")
        try:
            lines = DEFAULT_LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
            for l in lines[-10:]:
                print(f"  {l}")
        except Exception as e:
            print(f"  Could not read log file: {e}")
    print("=" * 60)

def install_service() -> bool:
    if sys.platform == "win32":
        return install_windows()
    elif sys.platform.startswith("linux"):
        return install_linux()
    else:
        print(f"[WARN] OS '{sys.platform}' does not have an automatic service installer.")
        return False

def uninstall_service() -> bool:
    if sys.platform == "win32":
        return uninstall_windows()
    elif sys.platform.startswith("linux"):
        return uninstall_linux()
    else:
        return stop_service()

def start_service() -> bool:
    if sys.platform == "win32":
        return start_windows()
    else:
        return start_linux()

def stop_service() -> bool:
    if sys.platform == "win32":
        return stop_windows()
    else:
        return stop_linux()


def ensure_service() -> bool:
    """Idempotently install and start the background watcher."""
    if sys.platform == "win32":
        if not is_windows_task_installed() and not install_windows():
            return False
        pid = get_current_pid()
        if pid and is_pid_running(pid):
            return True
        return start_windows()

    if sys.platform.startswith("linux"):
        status = subprocess.run(
            ["systemctl", "--user", "is-enabled", LINUX_SERVICE_NAME],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        if status.returncode != 0 and not install_linux():
            return False
        return start_linux()

    return start_service()

def main() -> None:
    parser = argparse.ArgumentParser(description="Lifecycle manager for the review loop watcher service.")
    parser.add_argument("action", choices=["install", "uninstall", "start", "stop", "status", "ensure"], help="Action to perform.")
    args = parser.parse_args()

    success = True
    if args.action == "install":
        success = install_service()
    elif args.action == "uninstall":
        success = uninstall_service()
    elif args.action == "start":
        success = start_service()
    elif args.action == "stop":
        success = stop_service()
    elif args.action == "status":
        print_status()
    elif args.action == "ensure":
        success = ensure_service()

    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
