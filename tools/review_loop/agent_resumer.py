"""
tools/review_loop/agent_resumer.py - Antigravity agent conversation resumption.

Locates agentapi / language_server.exe and dispatches resume instructions to
the registered Antigravity conversation session.
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

from tools.review_loop.config import RESUME_PROMPT_TEMPLATE

logger = logging.getLogger(__name__)

class AgentResumerError(Exception):
    pass

class AgentResumer:
    def __init__(self, agentapi_cmd: Optional[List[str]] = None):
        self._custom_cmd = agentapi_cmd

    def _discover_command(self) -> List[str]:
        """Discover the executable command to invoke agentapi."""
        if self._custom_cmd:
            return list(self._custom_cmd)

        # 1. Check ANTIGRAVITY_AGENTAPI_EXE
        agentapi_exe = os.environ.get("ANTIGRAVITY_AGENTAPI_EXE")
        if agentapi_exe and Path(agentapi_exe).is_file():
            # Usually language_server.exe which requires subcommand 'agentapi'
            if "language_server" in Path(agentapi_exe).stem.lower():
                return [agentapi_exe, "agentapi"]
            return [agentapi_exe]

        # 2. Check ~/.gemini/antigravity/bin/agentapi.bat (Windows) or agentapi (Unix)
        home = Path.home()
        for candidate in [
            home / ".gemini" / "antigravity" / "bin" / "agentapi.bat",
            home / ".gemini" / "antigravity" / "bin" / "agentapi",
            Path(r"C:\Users\alexa\.gemini\antigravity\bin\agentapi.bat")
        ]:
            if candidate.is_file():
                return [str(candidate)]

        # 3. Check system PATH for agentapi or agentapi.bat
        for name in ["agentapi.bat", "agentapi", "agentapi.exe"]:
            found = shutil.which(name)
            if found:
                return [found]

        # 4. Check agy CLI as fallback
        agy_found = shutil.which("agy")
        if agy_found:
            return [agy_found, "--conversation"]

        raise AgentResumerError(
            "Could not locate agentapi binary or script. Ensure Antigravity is installed "
            "and ANTIGRAVITY_AGENTAPI_EXE is configured or agentapi is in PATH."
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
    ) -> Tuple[bool, str]:
        """
        Send resume instruction to conversation_id via agentapi.
        Uses bounded retry on transient failures.
        """
        cmd_prefix = self._discover_command()
        prompt = self.build_prompt(pr_number)

        # Construct full command
        if cmd_prefix and cmd_prefix[0].endswith("agy"):
            # agy --conversation <id> -p "<prompt>"
            full_cmd = cmd_prefix + [conversation_id, "-p", prompt]
        else:
            # agentapi send-message [--title=<title>] <recipient_id> <content>
            msg_args = ["send-message"]
            if title:
                msg_args.append(f"--title={title}")
            msg_args.extend([conversation_id, prompt])
            full_cmd = cmd_prefix + msg_args

        last_error = ""
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(
                    "Resuming conversation %s for PR #%s (attempt %s/%s)...",
                    conversation_id, pr_number, attempt, max_retries
                )
                res = subprocess.run(
                    full_cmd,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=timeout
                )
                output = f"{res.stdout}\n{res.stderr}".strip()
                if res.returncode == 0:
                    logger.info("Successfully dispatched resume message to %s.", conversation_id)
                    return True, output
                last_error = f"agentapi exited with code {res.returncode}: {output}"
                logger.warning("Resume attempt %s failed: %s", attempt, last_error)
            except subprocess.TimeoutExpired:
                last_error = f"agentapi timed out after {timeout}s"
                logger.warning("Resume attempt %s timed out.", attempt)
            except Exception as e:
                last_error = str(e)
                logger.warning("Resume attempt %s exception: %s", attempt, e)

            if attempt < max_retries:
                time.sleep(2 ** attempt)

        return False, last_error
