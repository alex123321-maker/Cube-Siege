"""
tools/review_loop/github_client.py - GitHub CLI interface wrapper.

Encapsulates all communication with GitHub via `gh`, ensuring cwd is always set to the repository root.
"""
import json
import logging
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import REPO_ROOT

logger = logging.getLogger(__name__)

class GitHubError(Exception):
    """Raised when a GitHub CLI command fails."""
    pass

class GitHubAuthError(GitHubError):
    """Raised when GitHub CLI authentication is missing or expired."""
    pass

def is_auth_error_message(msg: str) -> bool:
    """Check if an error output from gh CLI indicates authentication failure."""
    if not msg:
        return False
    msg_lower = msg.lower()
    return any(marker in msg_lower for marker in [
        "gh auth login",
        "not authenticated",
        "authentication failed",
        "could not authenticate",
        "bad credentials",
        "http 401",
        "token expired",
        "oauth",
        "unauthorized",
        "invalid token",
    ])

class GitHubClient:
    def __init__(self, gh_path: Optional[str] = None, cwd: Optional[Path] = None):
        self.gh_path = gh_path or shutil.which("gh") or "gh"
        self.cwd = Path(cwd or REPO_ROOT)

    def run_gh(self, args: List[str], timeout: int = 30) -> Tuple[int, str, str]:
        """Execute a `gh` command strictly within self.cwd and return (returncode, stdout, stderr)."""
        cmd = [self.gh_path] + args
        try:
            res = subprocess.run(
                cmd,
                cwd=str(self.cwd),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout
            )
            if res.returncode != 0 and args != ["auth", "status"]:
                err_msg = f"{res.stderr}\n{res.stdout}".strip()
                if is_auth_error_message(err_msg):
                    raise GitHubAuthError(f"GitHub authentication error: {err_msg}")
            return res.returncode, res.stdout.strip(), res.stderr.strip()
        except GitHubAuthError:
            raise
        except subprocess.TimeoutExpired:
            raise GitHubError(f"Command timed out after {timeout}s: {' '.join(cmd)}")
        except FileNotFoundError:
            raise GitHubError(f"GitHub CLI binary not found at '{self.gh_path}'")
        except Exception as e:
            raise GitHubError(f"Failed to execute gh command: {e}")

    def check_auth(self) -> Tuple[bool, str]:
        """Verify if `gh auth status` reports valid authentication."""
        try:
            rc, stdout, stderr = self.run_gh(["auth", "status"])
            output = f"{stdout}\n{stderr}".strip()
            if rc == 0 and "Logged in to" in output:
                return True, output
            return False, output or "GitHub CLI is not authenticated."
        except GitHubError as e:
            return False, str(e)

    def get_repo_owner_and_name(self) -> Tuple[str, str]:
        """Return (owner, repo_name) for repository in self.cwd."""
        rc, stdout, stderr = self.run_gh(["repo", "view", "--json", "owner,name"])
        if rc != 0:
            raise GitHubError(f"Failed to get repo info: {stderr or stdout}")
        data = json.loads(stdout)
        owner = data.get("owner", {}).get("login", "")
        name = data.get("name", "")
        return owner, name

    def find_pr_for_branch(self, branch_name: str) -> Optional[int]:
        """Find the open PR number associated with branch_name, if any."""
        rc, stdout, stderr = self.run_gh([
            "pr", "list",
            "--head", branch_name,
            "--state", "open",
            "--json", "number",
            "--limit", "1"
        ])
        if rc != 0:
            raise GitHubError(f"Failed to list PRs for branch {branch_name}: {stderr or stdout}")
        data = json.loads(stdout)
        if data and len(data) > 0:
            return data[0].get("number")
        return None

    def get_open_prs(self) -> List[Dict[str, Any]]:
        """Return open PR numbers and their source branches."""
        rc, stdout, stderr = self.run_gh([
            "pr", "list", "--state", "open",
            "--json", "number,headRefName", "--limit", "100",
        ])
        if rc != 0:
            raise GitHubError(f"Failed to list open PRs: {stderr or stdout}")
        data = json.loads(stdout)
        return data if isinstance(data, list) else []

    def get_pr_details(self, pr_number: int) -> Dict[str, Any]:
        """Fetch general PR details (state, headRefOid, isDraft, author, url, reviewDecision)."""
        rc, stdout, stderr = self.run_gh([
            "pr", "view", str(pr_number),
            "--json", "number,state,isDraft,headRefName,headRefOid,author,url,reviewDecision"
        ])
        if rc != 0:
            raise GitHubError(f"Failed to view PR #{pr_number}: {stderr or stdout}")
        return json.loads(stdout)

    def get_pr_reviews(self, pr_number: int) -> List[Dict[str, Any]]:
        """Fetch reviews for PR (REQUEST_CHANGES, APPROVED, COMMENTED)."""
        rc, stdout, stderr = self.run_gh([
            "pr", "view", str(pr_number),
            "--json", "reviews"
        ])
        if rc != 0:
            raise GitHubError(f"Failed to get reviews for PR #{pr_number}: {stderr or stdout}")
        data = json.loads(stdout)
        return data.get("reviews", [])

    def get_pr_comments(self, pr_number: int) -> List[Dict[str, Any]]:
        """Fetch top-level issue/PR comments."""
        rc, stdout, stderr = self.run_gh([
            "pr", "view", str(pr_number),
            "--json", "comments"
        ])
        if rc != 0:
            raise GitHubError(f"Failed to get comments for PR #{pr_number}: {stderr or stdout}")
        data = json.loads(stdout)
        return data.get("comments", [])

    def get_pr_inline_comments(self, pr_number: int) -> List[Dict[str, Any]]:
        """Fetch inline code review comments via REST API."""
        owner, repo = self.get_repo_owner_and_name()
        endpoint = f"repos/{owner}/{repo}/pulls/{pr_number}/comments"
        rc, stdout, stderr = self.run_gh(["api", endpoint])
        if rc != 0:
            raise GitHubError(f"Failed to get inline comments for PR #{pr_number}: {stderr or stdout}")
        return json.loads(stdout)

    def get_pr_review_threads(self, pr_number: int) -> List[Dict[str, Any]]:
        """Fetch review threads and resolution status using GraphQL."""
        owner, repo = self.get_repo_owner_and_name()
        query = """
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 50) {
                nodes {
                  id
                  isResolved
                  comments(first: 20) {
                    nodes {
                      id
                      author { login }
                      body
                      createdAt
                    }
                  }
                }
              }
            }
          }
        }
        """
        rc, stdout, stderr = self.run_gh([
            "api", "graphql",
            "-F", f"owner={owner}",
            "-F", f"repo={repo}",
            "-F", f"pr={pr_number}",
            "-f", f"query={query}"
        ])
        if rc != 0:
            logger.warning("GraphQL reviewThreads query failed: %s", stderr or stdout)
            return []
        data = json.loads(stdout)
        threads = (
            data.get("data", {})
            .get("repository", {})
            .get("pullRequest", {})
            .get("reviewThreads", {})
            .get("nodes", [])
        )
        return threads
