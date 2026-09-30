"""Per-user Windows startup task for the Codex review watcher.

Antigravity keeps its own sidecar and PID; this task never owns its PRs.
"""
import getpass
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path

from tools.review_loop.config import REPO_ROOT, REVIEW_LOOP_DIR
from tools.review_loop.state_manager import is_pid_alive

SOURCE_ROOT = Path(__file__).resolve().parents[2]
SERVICE_CONFIG = REVIEW_LOOP_DIR / "codex_service.json"
PID_FILE = REVIEW_LOOP_DIR / "watcher_codex.pid"


def current_pid():
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
        return pid if is_pid_alive(pid) else 0
    except (OSError, ValueError):
        return 0


def _task(args):
    return subprocess.run(["schtasks", *args], capture_output=True, text=True,
                          errors="replace", timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)


def build_task_xml(pythonw, entry, config):
    user = html.escape(os.environ.get("USERDOMAIN", "") + "\\" + getpass.getuser())
    arguments = html.escape(subprocess.list2cmdline([str(entry), "--config", str(config)]))
    recovery_start = (datetime.now() + timedelta(seconds=10)).isoformat(timespec="seconds")
    return f'''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Codex PR review watcher; Antigravity is handled by its sidecar.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>{user}</UserId></LogonTrigger>
    <TimeTrigger><Repetition><Interval>PT1M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>{recovery_start}</StartBoundary><Enabled>true</Enabled></TimeTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>{user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled><Hidden>true</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure><Interval>PT1M</Interval><Count>999</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Author"><Exec><Command>{html.escape(str(pythonw))}</Command><Arguments>{arguments}</Arguments><WorkingDirectory>{html.escape(str(REPO_ROOT))}</WorkingDirectory></Exec></Actions>
</Task>'''


def install(task_name):
    pythonw = Path(sys.executable).with_name("pythonw.exe")
    if not pythonw.is_file():
        raise ValueError("pythonw.exe is required for a hidden Windows startup task.")
    codex = os.environ.get("REVIEW_LOOP_CODEX_EXE") or shutil.which("codex")
    if not codex or not Path(codex).is_file() or Path(codex).suffix.lower() in (".bat", ".cmd"):
        raise ValueError("Set REVIEW_LOOP_CODEX_EXE to the native Codex executable before installation.")
    # Validate the installed command without submitting any message.
    capability = subprocess.run([codex, "queue", "--help"], capture_output=True, timeout=15,
                                creationflags=subprocess.CREATE_NO_WINDOW)
    if capability.returncode:
        raise ValueError("The installed Codex does not support queue.")
    REVIEW_LOOP_DIR.mkdir(parents=True, exist_ok=True)
    configuration = {"source_root": str(SOURCE_ROOT), "repo_root": str(REPO_ROOT), "codex_exe": str(codex)}
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=REVIEW_LOOP_DIR, delete=False) as temp:
        json.dump(configuration, temp, ensure_ascii=False, indent=2)
        temporary_config = Path(temp.name)
    os.replace(temporary_config, SERVICE_CONFIG)
    xml = build_task_xml(pythonw, SOURCE_ROOT / "tools/review_loop/service_entry.py", SERVICE_CONFIG)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-16", suffix=".xml", delete=False) as temp:
        temp.write(xml)
        temporary_xml = Path(temp.name)
    try:
        result = _task(["/create", "/tn", task_name, "/xml", str(temporary_xml), "/f"])
    finally:
        temporary_xml.unlink(missing_ok=True)
    if result.returncode:
        print(f"[ERROR] Task installation failed: {result.stderr.strip() or result.stdout.strip()}")
        return False
    print(f"[SUCCESS] Installed login/recovery task '{task_name}'.")
    return True


def manage(action, task_name):
    if sys.platform != "win32":
        print("[ERROR] Persistent Codex installation currently supports Windows. Run watcher.py --agent codex under your service manager.")
        return False
    try:
        if action == "install":
            return install(task_name)
        if action == "status":
            result = _task(["/query", "/tn", task_name, "/fo", "LIST"])
            print(result.stdout.strip() or result.stderr.strip())
            print(f"Codex PID: {current_pid() or 'not running'}")
            print(f"Codex log: {REVIEW_LOOP_DIR / 'watcher_codex.log'}")
            return result.returncode == 0
        if action in ("stop", "uninstall"):
            result = _task(["/end", "/tn", task_name])
            if result.returncode == 0:
                deadline = time.monotonic() + 20
                while current_pid() and time.monotonic() < deadline:
                    time.sleep(0.25)
                if current_pid():
                    print("[ERROR] Scheduled watcher did not stop within 20 seconds.")
                    return False
            if action == "uninstall":
                result = _task(["/delete", "/tn", task_name, "/f"])
            return result.returncode == 0
        if action in ("ensure", "start"):
            installed = _task(["/query", "/tn", task_name]).returncode == 0
            if not installed and not install(task_name):
                return False
            if current_pid():
                return True
            result = _task(["/run", "/tn", task_name])
            if result.returncode:
                print(f"[ERROR] Task start failed: {result.stderr.strip() or result.stdout.strip()}")
                return False
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if current_pid():
                    return True
                time.sleep(0.25)
            print("[ERROR] No Codex watcher PID within 20 seconds. Inspect watcher_codex_startup.log.")
            return False
        raise ValueError(f"Unknown service action: {action}")
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"[ERROR] Codex service operation failed: {exc}")
        return False
