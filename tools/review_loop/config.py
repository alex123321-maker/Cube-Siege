"""
Configuration and constants for the review loop watcher.
"""
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
REVIEW_LOOP_DIR = REPO_ROOT / ".review_loop"
DEFAULT_STATE_FILE = REVIEW_LOOP_DIR / "state.json"
DEFAULT_STATE_LOCK_FILE = REVIEW_LOOP_DIR / "state.lock"
DEFAULT_LOG_FILE = REVIEW_LOOP_DIR / "watcher.log"
DEFAULT_HOOK_LOG_FILE = REVIEW_LOOP_DIR / "hook.log"
DEFAULT_PID_FILE = REVIEW_LOOP_DIR / "watcher.pid"
RUN_WATCHER_BAT = REVIEW_LOOP_DIR / "run_watcher.bat"
SIDECAR_MARKER_FILE = REVIEW_LOOP_DIR / "antigravity_sidecar.enabled"

# Watcher parameters
DEFAULT_POLL_INTERVAL_SECONDS = 30
DEFAULT_BACKOFF_INITIAL_SECONDS = 5
DEFAULT_BACKOFF_MAX_SECONDS = 300
DEFAULT_BACKOFF_FACTOR = 2.0

# Concurrency lock lease: generous default (30 mins) to accommodate complex fixes.
DEFAULT_LOCK_LEASE_SECONDS = 1800.0

# Marker used to tag comments created by automated agents to prevent infinite loops.
AGENT_COMMENT_MARKER = "<!-- agent:review-loop -->"

# agy headless CLI configuration
DEFAULT_AGY_PRINT_TIMEOUT = "30m"
AGY_STARTUP_GRACE_SECONDS = 3.0
AGENT_STARTUP_GRACE_PERIOD_SECONDS = 60.0
AGENTAPI_COMPLETION_TIMEOUT_SECONDS = 1800.0
MAX_AGENT_RETRIES = 3
DESIGN_DECISION_MARKER = "DESIGN DECISION REQUIRED"

# Template for resuming the Antigravity conversation
RESUME_PROMPT_TEMPLATE = """New GitHub review feedback was received for PR #{pr_number}.

Read the authoritative Issue, current PR description, latest head, all current reviews, and all unresolved review threads.
Address valid feedback only within the Issue scope.
This is an autonomous remediation run, not a planning request.
Do not create or update an implementation plan, do not request plan approval, and do not wait for user confirmation.
Plan internally and begin inspecting and editing the code immediately.
Preserve all pre-existing uncommitted changes outside the review feedback scope; do not revert, stage, commit, or modify them.
Do not change the gameplay/design contract.
Do not invent gameplay decisions.
Only if a real DESIGN DECISION REQUIRED is encountered, stop that part and report it clearly; continue all independent work.
Run the repository verification workflow.
Commit and push the fixes to the existing PR branch.
Do not merge the PR.

SILENT PR MODE: Never post a PR comment or submit a review. Report results only in this Antigravity chat.
If you changed code, the pushed commit is the completion signal. If no code change is required, finish silently in chat.

DEFENSE IN DEPTH: If a tool nevertheless forces you to post a Pull Request comment,
you MUST include the exact marker `""" + AGENT_COMMENT_MARKER + """` at the END of the body.
"""
