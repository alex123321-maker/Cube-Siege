"""
tools/review_loop/agent_resumer.py - Antigravity agent conversation resumption.

Uses official Antigravity CLI (agy --conversation <id> -p "<prompt>") or official
agentapi (agentapi send-message <id> "<prompt>"). No hardcoded user paths.
"""
import logging
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import REPO_ROOT, RESUME_PROMPT_TEMPLATE

logger = logging.getLogger(__name__)

class AgentResumerError(Exception):
    pass

class AgentResumer:
    def __init__(self, agentapi_cmd: Optional[List[str]] = None, cwd: Optional[Path] = None):
        self._custom_cmd = agentapi_cmd
        self.cwd = Path(cwd or REPO_ROOT)

    def _discover_command(self) -> List[str]:
        """
        Discover official Antigravity CLI (`agy`) or `agentapi`.
        Strictly portable: never uses hardcoded absolute user directory paths.
        """
        if self._custom_cmd:
            return list(self._custom_cmd)

        # 1. Official standalone CLI (agy)
        agy_which = shutil.which("agy") or shutil.which("agy.exe")
        if agy_which:
            return [agy_which]

        # 2. Check ANTIGRAVITY_AGENTAPI_EXE (if provided by agent/sidecar runtime)
        agentapi_exe = os.environ.get("ANTIGRAVITY_AGENTAPI_EXE")
        if agentapi_exe and Path(agentapi_exe).is_file():
            if "language_server" in Path(agentapi_exe).stem.lower():
                return [agentapi_exe, "agentapi"]
            return [agentapi_exe]

        # 3. Check system PATH for agentapi
        for name in ["agentapi", "agentapi.bat", "agentapi.exe"]:
            found = shutil.which(name)
            if found:
                return [found]

        # 4. Standard per-user install paths without hardcoded usernames
        home = Path.home()
        candidates = [
            home / ".gemini" / "antigravity" / "bin" / ("agentapi.bat" if sys.platform == "win32" else "agentapi"),
            home / "AppData" / "Local" / "agy" / "bin" / "agy.exe"
        ]
        for candidate in candidates:
            if candidate.is_file():
                return [str(candidate)]

        raise AgentResumerError(
            "Could not locate official 'agy' CLI or 'agentapi' binary. "
            "Ensure Google Antigravity is installed and 'agy' is added to system PATH."
        )

    def build_prompt(self, pr_number: int) -> str:
        """Construct canonical resume prompt as specified by contract."""
        return RESUME_PROMPT_TEMPLATE.format(pr_number=pr_number)

    def resume_conversation(
        self,
        conversation_id: str,
        pr_number: int,
        title: Optional[str] = None,
        timeout: int = 60,
        max_retries: int = 3
    ) -> Tuple[bool, str, Optional[int]]:
        """
        Send resume instruction to conversation_id.
        Returns (success: bool, output_or_error: str, pid: Optional[int]).
        Uses bounded retry on transient failures.
        """
        cmd_prefix = self._discover_command()
        prompt = self.build_prompt(pr_number)

        binary_stem = Path(cmd_prefix[0]).stem.lower()

        # Build command based on discovered tool
        if binary_stem in ["agy", "agy.exe"]:
            # Official agy CLI: agy --conversation <id> -p "<prompt>"
            full_cmd = cmd_prefix + ["--conversation", conversation_id, "-p", prompt]
        else:
            # agentapi: agentapi send-message [--title=<title>] <recipient_id> <content>
            msg_args = ["send-message"]
            if title:
                msg_args.append(f"--title={title}")
            msg_args.extend([conversation_id, prompt])
            full_cmd = cmd_prefix + msg_args

        last_error = ""
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(
                    "Resuming conversation %s for PR #%s (attempt %s/%s, binary: %s)...",
                    conversation_id, pr_number, attempt, max_retries, binary_stem
                )
                res = subprocess.run(
                    full_cmd,
                    cwd=str(self.cwd),
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=timeout
                )
                output = f"{res.stdout}\n{res.stderr}".strip()
                if res.returncode == 0:
                    logger.info("Successfully dispatched resume message to %s.", conversation_id)
                    return True, output, None
                last_error = f"Resume command exited with code {res.returncode}: {output}"
                logger.warning("Resume attempt %s failed: %s", attempt, last_error)
            except subprocess.TimeoutExpired:
                last_error = f"Resume command timed out after {timeout}s"
                logger.warning("Resume attempt %s timed out.", attempt)
            except Exception as e:
                last_error = str(e)
                logger.warning("Resume attempt %s exception: %s", attempt, e)

            if attempt < max_retries:
                time.sleep(2 ** attempt)

        return False, last_error, None
