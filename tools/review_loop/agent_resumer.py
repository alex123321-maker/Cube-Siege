"""
tools/review_loop/agent_resumer.py - Antigravity agent conversation resumption.

Supports two backends:
  - "agy": Official Antigravity CLI (agy --conversation <id> -p "<prompt>").
    Launched via Popen + PID tracking because agy blocks for the full agent turn.
  - "agentapi": Fast dispatch via agentapi send-message (synchronous, returns quickly).

Backend type is stored explicitly to avoid cross-platform Path.stem issues
(Windows backslash paths parsed on Linux POSIX).
"""
import logging
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import List, Optional, Tuple

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import (
    AGY_STARTUP_GRACE_SECONDS,
    DEFAULT_AGY_PRINT_TIMEOUT,
    REPO_ROOT,
    RESUME_PROMPT_TEMPLATE,
)

logger = logging.getLogger(__name__)

# Backend type constants
BACKEND_AGY = "agy"
BACKEND_AGENTAPI = "agentapi"


def detect_backend_from_path(exe_path: str) -> str:
    """
    Portable detection of backend type from an executable path.
    Handles both POSIX and Windows path separators regardless of host OS.
    """
    # Try PureWindowsPath first (handles backslash separators on any OS)
    stem_win = PureWindowsPath(exe_path).stem.lower()
    # Also try PurePosixPath (handles forward slash separators)
    stem_posix = PurePosixPath(exe_path).stem.lower()

    # Check both interpretations — the correct one will have a short stem
    for stem in (stem_win, stem_posix):
        if stem in ("agy", "agy.exe"):
            return BACKEND_AGY

    return BACKEND_AGENTAPI


class AgentResumerError(Exception):
    pass


class AgentResumer:
    def __init__(
        self,
        agentapi_cmd: Optional[List[str]] = None,
        backend_type: Optional[str] = None,
        cwd: Optional[Path] = None,
    ):
        self._custom_cmd = agentapi_cmd
        self._backend_type = backend_type
        self.cwd = Path(cwd or REPO_ROOT)

    def _discover_command(self) -> Tuple[List[str], str]:
        """
        Discover official Antigravity CLI or agentapi.
        Returns (command_list, backend_type).
        """
        if self._custom_cmd:
            backend = self._backend_type or detect_backend_from_path(
                self._custom_cmd[0]
            )
            return list(self._custom_cmd), backend

        # 1. Official standalone CLI (agy)
        agy_which = shutil.which("agy") or shutil.which("agy.exe")
        if agy_which:
            return [agy_which], BACKEND_AGY

        # 2. ANTIGRAVITY_AGENTAPI_EXE (sidecar runtime)
        agentapi_exe = os.environ.get("ANTIGRAVITY_AGENTAPI_EXE")
        if agentapi_exe and Path(agentapi_exe).is_file():
            if "language_server" in Path(agentapi_exe).stem.lower():
                return [agentapi_exe, "agentapi"], BACKEND_AGENTAPI
            return [agentapi_exe], BACKEND_AGENTAPI

        # 3. System PATH for agentapi
        for name in ["agentapi", "agentapi.bat", "agentapi.exe"]:
            found = shutil.which(name)
            if found:
                return [found], BACKEND_AGENTAPI

        # 4. Standard per-user install paths (no hardcoded usernames)
        home = Path.home()
        agy_candidates = [
            home / "AppData" / "Local" / "agy" / "bin" / "agy.exe",
        ]
        for candidate in agy_candidates:
            if candidate.is_file():
                return [str(candidate)], BACKEND_AGY

        api_candidates = [
            home
            / ".gemini"
            / "antigravity"
            / "bin"
            / ("agentapi.bat" if sys.platform == "win32" else "agentapi"),
        ]
        for candidate in api_candidates:
            if candidate.is_file():
                return [str(candidate)], BACKEND_AGENTAPI

        raise AgentResumerError(
            "Could not locate official 'agy' CLI or 'agentapi' binary. "
            "Ensure Google Antigravity is installed and 'agy' is on PATH."
        )

    def build_prompt(self, pr_number: int) -> str:
        """Construct canonical resume prompt as specified by contract."""
        return RESUME_PROMPT_TEMPLATE.format(pr_number=pr_number)

    def resume_conversation(
        self,
        conversation_id: str,
        pr_number: int,
        title: Optional[str] = None,
        timeout: int = 120,
        max_retries: int = 3,
    ) -> Tuple[bool, str, Optional[int]]:
        """
        Send resume instruction to conversation_id.

        For agy backend: launches a long-lived Popen process and returns its PID.
            The watcher tracks liveness via is_pid_alive() in subsequent cycles.
        For agentapi backend: synchronous send-message dispatch.

        Returns (success, output_or_error, pid_if_launched).
        """
        cmd_list, backend = self._discover_command()
        prompt = self.build_prompt(pr_number)

        if backend == BACKEND_AGY:
            return self._resume_via_agy(
                cmd_list, conversation_id, prompt, max_retries
            )
        else:
            return self._resume_via_agentapi(
                cmd_list, conversation_id, prompt, title, timeout, max_retries
            )

    def _resume_via_agy(
        self,
        cmd_list: List[str],
        conversation_id: str,
        prompt: str,
        max_retries: int,
    ) -> Tuple[bool, str, Optional[int]]:
        """
        Launch agy as a long-lived subprocess (Popen) and return its PID.

        agy --conversation <id> -p "<prompt>" --print-timeout <timeout>
        is synchronous — it blocks until the agent turn completes.
        We launch it detached and track PID instead of waiting.
        """
        full_cmd = cmd_list + [
            "--conversation",
            conversation_id,
            "-p",
            prompt,
            "--print-timeout",
            DEFAULT_AGY_PRINT_TIMEOUT,
        ]

        last_error = ""
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(
                    "Launching agy for conversation %s PR #%s (attempt %s/%s)...",
                    conversation_id,
                    "?",
                    attempt,
                    max_retries,
                )

                # Build Popen kwargs
                popen_kwargs = {
                    "cwd": str(self.cwd),
                    "stdout": subprocess.DEVNULL,
                    "stderr": subprocess.DEVNULL,
                    "stdin": subprocess.DEVNULL,
                }
                # On Windows, detach from parent console
                if sys.platform == "win32":
                    creation_flags = 0
                    if hasattr(subprocess, "DETACHED_PROCESS"):
                        creation_flags |= subprocess.DETACHED_PROCESS
                    if hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP"):
                        creation_flags |= subprocess.CREATE_NEW_PROCESS_GROUP
                    popen_kwargs["creationflags"] = creation_flags

                proc = subprocess.Popen(full_cmd, **popen_kwargs)

                # Brief grace period to detect instant crashes
                time.sleep(AGY_STARTUP_GRACE_SECONDS)
                exit_code = proc.poll()

                if exit_code is not None:
                    last_error = (
                        f"agy process exited immediately with code {exit_code}"
                    )
                    logger.warning(
                        "agy startup failed (attempt %s): %s",
                        attempt,
                        last_error,
                    )
                    if attempt < max_retries:
                        time.sleep(2**attempt)
                    continue

                logger.info(
                    "agy launched successfully (PID %s) for conversation %s.",
                    proc.pid,
                    conversation_id,
                )
                return True, f"agy launched (PID {proc.pid})", proc.pid

            except Exception as e:
                last_error = str(e)
                logger.warning(
                    "agy launch exception (attempt %s): %s", attempt, e
                )
                if attempt < max_retries:
                    time.sleep(2**attempt)

        return False, last_error, None

    def _resume_via_agentapi(
        self,
        cmd_list: List[str],
        conversation_id: str,
        prompt: str,
        title: Optional[str],
        timeout: int,
        max_retries: int,
    ) -> Tuple[bool, str, Optional[int]]:
        """
        Synchronous dispatch via agentapi send-message.
        agentapi is a fast message dispatch (not a full agent turn),
        so synchronous subprocess.run with generous timeout is appropriate.
        """
        msg_args = ["send-message"]
        if title:
            msg_args.append(f"--title={title}")
        msg_args.extend([conversation_id, prompt])
        full_cmd = cmd_list + msg_args

        last_error = ""
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(
                    "Dispatching via agentapi to %s (attempt %s/%s)...",
                    conversation_id,
                    attempt,
                    max_retries,
                )
                res = subprocess.run(
                    full_cmd,
                    cwd=str(self.cwd),
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=timeout,
                )
                output = f"{res.stdout}\n{res.stderr}".strip()
                if res.returncode == 0:
                    logger.info(
                        "Successfully dispatched resume message to %s.",
                        conversation_id,
                    )
                    return True, output, None
                last_error = (
                    f"agentapi exited with code {res.returncode}: {output}"
                )
                logger.warning(
                    "agentapi attempt %s failed: %s", attempt, last_error
                )
            except subprocess.TimeoutExpired:
                last_error = f"agentapi timed out after {timeout}s"
                logger.warning(
                    "agentapi attempt %s timed out.", attempt
                )
            except Exception as e:
                last_error = str(e)
                logger.warning(
                    "agentapi attempt %s exception: %s", attempt, e
                )

            if attempt < max_retries:
                time.sleep(2**attempt)

        return False, last_error, None
