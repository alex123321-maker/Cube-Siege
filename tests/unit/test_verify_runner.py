"""
tests/unit/test_verify_runner.py - Unit tests for tools/verify.py runner.

Validates the fail-closed verification contract specified in Issue #44 (F26):
  1. Success text in log + nonzero exit code -> FAILS.
  2. Zero exit code + incomplete/empty GUT report (0 tests executed) -> FAILS.
  3. Script error or parse error in Godot log -> FAILS.
  4. Missing GUT test suite file -> FAILS.
  5. Subprocess timeout expiration -> FAILS cleanly without hang.
  6. Python test discovery functions independently of test_review_loop.py sentinel.
"""

import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.verify import (
    discover_python_tests,
    run_command,
    step_run_gut_tests,
    verify_gut_output,
    REPO_DIR,
)


class TestVerifyRunnerContracts(unittest.TestCase):
    """Unit tests for tools/verify.py runner logic and fail-closed validation."""

    def test_success_text_with_nonzero_exit_code_fails(self) -> None:
        """Contradiction case: log contains success markers but exit code is non-zero."""
        mock_output = (
            "==============================================\n"
            "Tests               10\n"
            "Passing Tests       10\n"
            "---- All tests passed! ----\n"
        )
        passed, reason = verify_gut_output(ok=False, out=mock_output)
        self.assertFalse(passed, "Non-zero exit code must ALWAYS fail even if success text is in log")
        self.assertIn("non-zero", reason.lower())

    def test_zero_exit_code_with_empty_or_incomplete_report_fails(self) -> None:
        """Empty or incomplete GUT report without test summary must fail."""
        # Case A: completely missing summary
        passed_a, reason_a = verify_gut_output(ok=True, out="Godot Engine initialized.\nQuit.")
        self.assertFalse(passed_a, "Missing GUT summary must result in failure")
        self.assertIn("incomplete or empty", reason_a.lower())

        # Case B: zero tests executed
        zero_tests_output = (
            "==============================================\n"
            "Tests               0\n"
            "Passing Tests       0\n"
            "---- All tests passed! ----\n"
        )
        passed_b, reason_b = verify_gut_output(ok=True, out=zero_tests_output)
        self.assertFalse(passed_b, "Running zero tests must result in failure")
        self.assertIn("zero", reason_b.lower())

    def test_script_or_parse_error_in_log_fails(self) -> None:
        """Script errors or parse errors in the log must trigger failure."""
        output_with_script_error = (
            "SCRIPT ERROR: Attempt to call function 'foo' in base 'null instance'.\n"
            "Tests               10\n"
            "Passing Tests       10\n"
            "---- All tests passed! ----\n"
        )
        passed, reason = verify_gut_output(ok=True, out=output_with_script_error)
        self.assertFalse(passed, "Log with SCRIPT ERROR must fail")
        self.assertIn("script or parse error", reason.lower())

        output_with_parse_error = (
            "SCRIPT ERROR: Parse Error: Expected parameter name.\n"
            "Tests               5\n"
            "Passing Tests       5\n"
            "---- All tests passed! ----\n"
        )
        passed_parse, reason_parse = verify_gut_output(ok=True, out=output_with_parse_error)
        self.assertFalse(passed_parse, "Log with Parse Error must fail")

    def test_failing_or_errored_gut_tests_fail(self) -> None:
        """Any reported failing test count or error count must result in failure."""
        output_with_failures = (
            "==============================================\n"
            "Tests               10\n"
            "Passing Tests       8\n"
            "Failing Tests       2\n"
            "Errors              0\n"
        )
        passed, reason = verify_gut_output(ok=True, out=output_with_failures)
        self.assertFalse(passed, "Failing tests count must fail verification")
        self.assertIn("failed", reason.lower())

        output_with_errors = (
            "==============================================\n"
            "Tests               10\n"
            "Passing Tests       10\n"
            "Failing Tests       0\n"
            "Errors              1\n"
        )
        passed_err, reason_err = verify_gut_output(ok=True, out=output_with_errors)
        self.assertFalse(passed_err, "GUT errors must fail verification")
        self.assertIn("error", reason_err.lower())

    def test_missing_gut_suite_script_fails(self) -> None:
        """Attempting to run GUT when the runner script is absent must fail."""
        with patch.object(Path, "is_file", return_value=False):
            result = step_run_gut_tests("dummy_godot_path")
            self.assertFalse(result, "Missing GUT script must return False")

    def test_command_timeout_expiration_fails_cleanly(self) -> None:
        """Commands that exceed their configured timeout must terminate and return failure."""
        # Launch a python sleep command with a 0.2s timeout
        cmd = [sys.executable, "-c", "import time; time.sleep(2.0)"]
        ok, out = run_command(cmd, REPO_DIR, "sleep test", timeout=0.2)
        self.assertFalse(ok, "Timed-out command must return ok=False")
        self.assertIn("[TIMEOUT]", out, "Output must indicate timeout occurred")

    def test_python_discovery_independent_of_single_sentinel(self) -> None:
        """Python test discovery must find all test_*.py files across tests/."""
        discovered = discover_python_tests()
        self.assertIsInstance(discovered, list)
        self.assertGreater(len(discovered), 0, "Must discover python unit test files in repo")
        # Verify that discovery finds test files regardless of test_review_loop.py
        file_names = [f.name for f in discovered]
        self.assertIn("test_verify_runner.py", file_names)


if __name__ == "__main__":
    unittest.main()
