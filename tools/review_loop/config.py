"""
Configuration and constants for the review loop watcher.
"""
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
REVIEW_LOOP_DIR = REPO_ROOT / ".review_loop"
DEFAULT_STATE_FILE = REVIEW_LOOP_DIR / "state.json"
DEFAULT_LOG_FILE = REVIEW_LOOP_DIR / "watcher.log"
DEFAULT_PID_FILE = REVIEW_LOOP_DIR / "watcher.pid"
RUN_WATCHER_BAT = REVIEW_LOOP_DIR / "run_watcher.bat"

# Watcher parameters
DEFAULT_POLL_INTERVAL_SECONDS = 30
DEFAULT_BACKOFF_INITIAL_SECONDS = 5
DEFAULT_BACKOFF_MAX_SECONDS = 300
DEFAULT_BACKOFF_FACTOR = 2.0

# Concurrency lock lease: generous default (30 mins) to accommodate complex fixes.
DEFAULT_LOCK_LEASE_SECONDS = 1800.0

# Marker used to tag comments created by automated agents to prevent infinite loops.
AGENT_COMMENT_MARKER = "<!-- agent:review-loop -->"

# Template for resuming the Antigravity conversation
RESUME_PROMPT_TEMPLATE = """New GitHub review feedback was received for PR #{pr_number}.

Read the authoritative Issue, current PR description, latest head, all current reviews, and all unresolved review threads.
Address valid feedback only within the Issue scope.
Do not change the gameplay/design contract.
Do not invent gameplay decisions.
If DESIGN DECISION REQUIRED is encountered, stop that part and report it clearly.
Run the repository verification workflow.
Commit and push the fixes to the existing PR branch.
Do not merge the PR.
"""
