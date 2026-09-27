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
    step_run_issue_18_verification,
    step_run_python_tests,
    verify_gameplay_harness_output,
    verify_gut_output,
    verify_python_test_output,
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
        file_names = [f.name for f in discovered]
        self.assertIn("test_verify_runner.py", file_names)

    def test_missing_python_tests_fails(self) -> None:
        """When zero python test files are discovered, step_run_python_tests must FAIL (fail-closed)."""
        with patch("tools.verify.discover_python_tests", return_value=[]):
            result = step_run_python_tests()
            self.assertFalse(result, "Missing python test suite must fail-closed with False")

    def test_missing_issue_18_verifier_fails(self) -> None:
        """When tools/verify_issue_18.gd is absent, step_run_issue_18_verification must FAIL."""
        with patch.object(Path, "is_file", return_value=False):
            result = step_run_issue_18_verification("dummy_godot_bin")
            self.assertFalse(result, "Missing verify_issue_18.gd script must fail-closed with False")

    def test_python_tests_outside_tests_unit_are_executed(self) -> None:
        """Python tests outside tests/unit/ (e.g. tests/smoke/test_custom.py) must be passed to unittest."""
        mock_files = [
            REPO_DIR / "tests" / "unit" / "test_a.py",
            REPO_DIR / "tests" / "smoke" / "test_custom.py",
        ]
        with patch("tools.verify.discover_python_tests", return_value=mock_files):
            with patch("tools.verify.run_command", return_value=(True, "Ran 5 tests\nOK")) as mock_run:
                result = step_run_python_tests()
                self.assertTrue(result)
                mock_run.assert_called_once()
                executed_cmd = mock_run.call_args[0][0]
                custom_rel = str((REPO_DIR / "tests" / "smoke" / "test_custom.py").relative_to(REPO_DIR))
                self.assertIn(custom_rel, executed_cmd, "Test file outside tests/unit must be included in execution")

    def test_python_output_missing_summary_fails(self) -> None:
        """Python output with code 0 but missing 'Ran N tests' summary must fail."""
        passed, reason, count = verify_python_test_output(ok=True, out="Execution finished without summary")
        self.assertFalse(passed, "Missing unittest summary must fail-closed")
        self.assertIn("missing", reason.lower())

        # Also verify step_run_python_tests fails when run_command returns output without summary
        mock_files = [REPO_DIR / "tests" / "unit" / "test_a.py"]
        with patch("tools.verify.discover_python_tests", return_value=mock_files):
            with patch("tools.verify.run_command", return_value=(True, "Some output without unittest summary")):
                result = step_run_python_tests()
                self.assertFalse(result, "step_run_python_tests must return False on missing summary")

    def test_python_output_with_traceback_fails(self) -> None:
        """Python output containing an unhandled Traceback must fail."""
        passed, reason, _count = verify_python_test_output(
            ok=True,
            out="Traceback (most recent call last):\n  File 'foo.py', line 1\nRan 1 tests\nOK"
        )
        self.assertFalse(passed, "Traceback in output must fail")
        self.assertIn("traceback", reason.lower())

    def test_python_output_zero_tests_fails(self) -> None:
        """Python output reporting 'Ran 0 tests' must fail."""
        passed, reason, _count = verify_python_test_output(ok=True, out="Ran 0 tests in 0.001s\nOK")
        self.assertFalse(passed, "Zero tests executed must fail")
        self.assertIn("zero", reason.lower())

    def test_gameplay_harness_output_with_script_error_fails(self) -> None:
        """Gameplay harness output with code 0 and '0 Failed' but with SCRIPT ERROR must fail."""
        mock_out = "[GAMEPLAY SMOKE HARNESS] Summary: 24/24 Passed, 0 Failed\nSCRIPT ERROR: Nil value"
        passed, reason = verify_gameplay_harness_output(ok=True, out=mock_out)
        self.assertFalse(passed, "Engine SCRIPT ERROR in gameplay output must fail")
        self.assertIn("script or parse error", reason.lower())

    def test_gameplay_harness_output_missing_summary_fails(self) -> None:
        """Gameplay harness output without completed summary must fail."""
        passed, reason = verify_gameplay_harness_output(ok=True, out="Godot Engine initialized\nQuit.")
        self.assertFalse(passed, "Missing summary must fail")
        self.assertIn("missing", reason.lower())

    def test_gameplay_harness_output_zero_checks_fails(self) -> None:
        """Gameplay harness output reporting 0 checks must fail."""
        passed, reason = verify_gameplay_harness_output(ok=True, out="[GAMEPLAY SMOKE HARNESS] Summary: 0/0 Passed, 0 Failed")
        self.assertFalse(passed, "Zero checks executed must fail")
        self.assertIn("zero", reason.lower())

    def test_gameplay_harness_output_with_failed_checks_fails(self) -> None:
        """Gameplay harness output reporting failed checks must fail."""
        passed, reason = verify_gameplay_harness_output(ok=True, out="[GAMEPLAY SMOKE HARNESS] Summary: 23/24 Passed, 1 Failed")
        self.assertFalse(passed, "Failed checks in gameplay harness must fail")
        self.assertIn("failed", reason.lower())

    def test_gameplay_harness_output_valid_passes(self) -> None:
        """Gameplay harness output with clean pass and 0 Failed must pass."""
        passed, reason = verify_gameplay_harness_output(ok=True, out="[GAMEPLAY SMOKE HARNESS] Summary: 24/24 Passed, 0 Failed")
        self.assertTrue(passed, "Valid gameplay summary must pass")
        self.assertIn("24", reason)


if __name__ == "__main__":
    unittest.main()
