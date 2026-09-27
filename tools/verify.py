#!/usr/bin/env python3
"""
tools/verify.py - Comprehensive verification runner for Cube Siege.

Performs complete, fail-closed health audit of the project:
  1. Toolchain discovery (python, git, gh, scons, c++ compiler, godot)
  2. Git submodule status (godot-cpp)
  3. C++ GDExtension debug build (via scons)
  4. Godot headless project import and script validation
  5. GUT automated smoke, unit, and integration tests (fail-closed, report verified)
  6. Python tooling and review loop unit tests (independent discovery)
  7. Procedural world, vertical combat, and streaming verification (Issue #18)
  8. Headless menu smoke run (scenes/main_menu.tscn)
  9. Headless gameplay smoke harness (all 3 classes, combat hits, chunk streaming)

Enforces timeouts on all subprocess commands to prevent hangs.
Returns non-zero exit code on any failure.
"""

import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO_DIR = Path(__file__).resolve().parent.parent
LOCAL_GODOT_PATH_FILE = REPO_DIR / ".godot_path"

# Default timeouts in seconds for distinct verification phases
TIMEOUT_TOOLS: float = 15.0
TIMEOUT_SCONS: float = 180.0
TIMEOUT_IMPORT: float = 90.0
TIMEOUT_GUT: float = 180.0
TIMEOUT_PYTHON: float = 60.0
TIMEOUT_ISSUE_18: float = 90.0
TIMEOUT_MENU_SMOKE: float = 30.0
TIMEOUT_GAMEPLAY_HARNESS: float = 90.0

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass


def log_header(title: str) -> None:
    print("\n" + "=" * 70)
    print(f" [VERIFY] {title}")
    print("=" * 70)


def log_step(name: str, status: str, detail: str = "") -> None:
    marker = "[PASS]" if status == "PASS" else ("[FAIL]" if status == "FAIL" else "[INFO]")
    print(f"  {marker:7s} | {name:<35s} | {detail}")


def run_command(
    cmd: List[str],
    cwd: Path,
    desc: str,
    timeout: Optional[float] = 120.0,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[bool, str]:
    """Execute a subprocess command with guaranteed timeout and test storage isolation."""
    full_env = os.environ.copy()
    # Always enforce isolated test storage profile for verification runs (F01)
    full_env["CUBE_SIEGE_TEST_PROFILE"] = "user://test_profile/"
    if env:
        full_env.update(env)

    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            env=full_env,
        )
        return (proc.returncode == 0, proc.stdout)
    except subprocess.TimeoutExpired as te:
        raw_out = te.stdout or ""
        out_str = raw_out if isinstance(raw_out, str) else raw_out.decode("utf-8", "replace")
        return (False, f"[TIMEOUT] Command '{desc}' timed out after {timeout} seconds.\nOutput before timeout:\n{out_str}")
    except Exception as e:
        return (False, f"[ERROR] Execution failed for '{desc}': {e}")


def find_godot_binary() -> Optional[str]:
    # 1. Environment variable
    env_path = os.environ.get("GODOT_BIN")
    if env_path and Path(env_path).is_file():
        return env_path

    # 2. Local config file (.godot_path)
    if LOCAL_GODOT_PATH_FILE.is_file():
        saved = LOCAL_GODOT_PATH_FILE.read_text(encoding="utf-8").strip()
        if saved and Path(saved).is_file():
            return saved

    # 3. System PATH
    for name in ["godot", "godot4", "godot.exe", "godot4.exe", "Godot_v4.6.1-stable_win64_console.exe"]:
        which_path = shutil.which(name)
        if which_path:
            return which_path

    # 4. Known platform locations
    if sys.platform.startswith("win"):
        candidates = [
            r"D:\ProgramFiles\godot\Godot_v4.6.1-stable_win64_console.exe",
            r"D:\ProgramFiles\godot\godot.exe",
            r"C:\Program Files\Godot\godot.exe",
            r"C:\Godot\godot.exe",
        ]
        for c in candidates:
            if Path(c).is_file():
                try:
                    LOCAL_GODOT_PATH_FILE.write_text(c, encoding="utf-8")
                except Exception:
                    pass
                return c

    return None


def step_check_tools(timeout: float = TIMEOUT_TOOLS) -> Tuple[bool, Optional[str]]:
    log_header("1. Checking Development Toolchain")
    all_ok = True

    # Python
    py_ver = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    log_step("Python Runtime", "PASS", f"v{py_ver}")

    # Git
    git_path = shutil.which("git")
    if git_path:
        ok, out = run_command(["git", "--version"], REPO_DIR, "git version", timeout=timeout)
        if ok:
            log_step("Git CLI", "PASS", out.strip())
        else:
            log_step("Git CLI", "FAIL", "git --version failed")
            all_ok = False
    else:
        log_step("Git CLI", "FAIL", "git not found in PATH")
        all_ok = False

    # GitHub CLI (gh)
    gh_path = shutil.which("gh")
    if gh_path:
        ok, out = run_command(["gh", "--version"], REPO_DIR, "gh version", timeout=timeout)
        first_line = out.splitlines()[0] if out else "installed"
        auth_ok, auth_out = run_command(["gh", "auth", "status"], REPO_DIR, "gh auth status", timeout=timeout)
        if auth_ok:
            acct = "Authenticated"
            for line in (auth_out or "").splitlines():
                if "Logged in to" in line:
                    clean = line.replace("✓", "").strip()
                    acct = clean
                    break
            log_step("GitHub CLI (gh)", "PASS", f"{first_line} ({acct})")
        else:
            if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS"):
                log_step("GitHub CLI (gh)", "PASS", f"{first_line} (CI runner)")
            else:
                log_step("GitHub CLI (gh)", "FAIL", f"{first_line} (Not logged in. Run 'gh auth login' to enable Issue-Driven workflow)")
                all_ok = False
    else:
        if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS"):
            log_step("GitHub CLI (gh)", "PASS", "Not installed (CI runner)")
        else:
            log_step("GitHub CLI (gh)", "FAIL", "gh not found in PATH. Required for Issue-Driven workflow.")
            all_ok = False

    # SCons
    scons_path = shutil.which("scons")
    if scons_path:
        ok, out = run_command(["scons", "--version"], REPO_DIR, "scons version", timeout=timeout)
        first_line = out.splitlines()[0] if out else ""
        if ok:
            log_step("SCons Build System", "PASS", first_line)
        else:
            log_step("SCons Build System", "FAIL", "scons --version failed")
            all_ok = False
    else:
        log_step("SCons Build System", "FAIL", "scons not found in PATH")
        all_ok = False

    # C++ Compiler
    cc_path = shutil.which("gcc") or shutil.which("clang") or shutil.which("cl")
    if cc_path:
        ok, out = run_command([cc_path, "--version"], REPO_DIR, "compiler version", timeout=timeout)
        first_line = out.splitlines()[0] if out else Path(cc_path).name
        if ok:
            log_step("C++ Compiler", "PASS", first_line)
        else:
            log_step("C++ Compiler", "FAIL", f"{cc_path} --version failed")
            all_ok = False
    else:
        log_step("C++ Compiler", "FAIL", "No C++ compiler (gcc/clang/cl) found in PATH")
        all_ok = False

    # Godot Binary
    godot_path = find_godot_binary()
    if godot_path:
        log_step("Godot 4.6 Binary", "PASS", godot_path)
    else:
        log_step("Godot 4.6 Binary", "FAIL", "Not found. Set GODOT_BIN environment variable or .godot_path")
        all_ok = False

    return all_ok, godot_path


def step_check_submodules() -> bool:
    log_header("2. Checking Git Submodules")
    godot_cpp_dir = REPO_DIR / "godot-cpp"
    sconstruct = godot_cpp_dir / "SConstruct"
    if not sconstruct.is_file():
        log_step("godot-cpp submodule", "FAIL", "SConstruct not found in godot-cpp. Run 'git submodule update --init --recursive'")
        return False

    log_step("godot-cpp submodule", "PASS", "Initialized and present")
    return True


def step_build_gdextension(timeout: float = TIMEOUT_SCONS) -> bool:
    log_header("3. Building C++ GDExtension (Debug)")
    sconstruct_path = REPO_DIR / "SConstruct"
    if not sconstruct_path.is_file():
        log_step("C++ GDExtension", "INFO", "No root SConstruct found. Skipping native build.")
        return True

    plat = "windows" if sys.platform.startswith("win") else ("linux" if sys.platform.startswith("linux") else "macos")
    jobs = str(os.cpu_count() or 2)
    cmd = [
        "scons",
        "custom_api_file=extension_api.json",
        f"platform={plat}",
        "target=template_debug",
        f"-j{jobs}",
    ]
    print(f"  Executing: {' '.join(cmd)}")
    ok, out = run_command(cmd, REPO_DIR, "scons build", timeout=timeout)
    if ok:
        log_step("SCons Compilation", "PASS", "Built successfully")
        return True
    else:
        log_step("SCons Compilation", "FAIL", "Build failed")
        print("\n--- SCons Build Output ---")
        print(out[-2000:])
        return False


def step_headless_import(godot_bin: str, timeout: float = TIMEOUT_IMPORT) -> bool:
    log_header("4. Headless Godot Editor Import & Validation")
    cmd = [godot_bin, "--headless", "--editor", "--quit", "--path", str(REPO_DIR)]
    ok, out = run_command(cmd, REPO_DIR, "headless import", timeout=timeout)
    if not ok:
        log_step("Project Import", "FAIL", "Exit code non-zero or import failed")
        print("\n--- Godot Import Output ---")
        print(out[-2000:])
        return False

    # Check for parse errors or script errors in import log
    if "SCRIPT ERROR:" in out or "Parse Error:" in out:
        log_step("Project Import", "FAIL", "Script or parse errors detected during import")
        print("\n--- Godot Import Output ---")
        print(out[-2000:])
        return False

    log_step("Project Import", "PASS", "Assets and scripts validated cleanly")
    return True


def verify_gut_output(ok: bool, out: str) -> Tuple[bool, str]:
    """Fail-closed validator for GUT test runner output (F26).
    
    Guarantees:
      - Nonzero returncode is ALWAYS a failure regardless of output text.
      - Engine script errors and parse errors fail the step.
      - A complete test summary with > 0 tests is required.
      - Failing tests or GUT errors result in failure.
    """
    if not ok:
        return (False, "GUT process returned non-zero exit code.")

    if "SCRIPT ERROR:" in out or "Parse Error:" in out:
        return (False, "Godot script or parse error detected in GUT test log.")

    # Search for GUT summary table
    tests_match = re.search(r"Tests\s+(\d+)", out)
    passing_match = re.search(r"Passing Tests\s+(\d+)", out)
    failing_match = re.search(r"Failing Tests\s+(\d+)", out)
    errors_match = re.search(r"Errors\s+(\d+)", out)

    if not tests_match:
        return (False, "Incomplete or empty GUT report: no test summary found.")

    total_tests = int(tests_match.group(1))
    if total_tests == 0:
        return (False, "Zero GUT tests were executed.")

    if failing_match and int(failing_match.group(1)) > 0:
        return (False, f"{failing_match.group(1)} test(s) failed in GUT suite.")

    if errors_match and int(errors_match.group(1)) > 0:
        return (False, f"{errors_match.group(1)} GUT runtime error(s) occurred.")

    if passing_match and int(passing_match.group(1)) != total_tests:
        return (False, f"Not all tests passed: {passing_match.group(1)}/{total_tests} passing.")

    if "---- All tests passed! ----" not in out and not (passing_match and int(passing_match.group(1)) == total_tests):
        return (False, "GUT test suite did not confirm clean pass.")

    scripts_match = re.search(r"Scripts\s+(\d+)", out)
    scripts_info = f" across {scripts_match.group(1)} scripts" if scripts_match else ""
    return (True, f"All {total_tests} tests passed{scripts_info}")


def step_run_gut_tests(godot_bin: str, timeout: float = TIMEOUT_GUT) -> bool:
    log_header("5. Running GUT Automated Tests")
    gut_script = "addons/gut/gut_cmdln.gd"
    if not (REPO_DIR / gut_script).is_file():
        log_step("GUT Test Suite", "FAIL", f"{gut_script} not found in repository")
        return False

    cmd = [
        godot_bin,
        "--headless",
        "--path", str(REPO_DIR),
        "-s", gut_script,
        "-gconfig=res://.gutconfig.json",
    ]
    ok, out = run_command(cmd, REPO_DIR, "gut full test suite", timeout=timeout)
    passed, detail = verify_gut_output(ok, out)

    if passed:
        log_step("GUT Test Suite", "PASS", detail)
        return True
    else:
        log_step("GUT Test Suite", "FAIL", detail)
        print("\n--- GUT Output ---")
        print(out[-3000:])
        return False


def discover_python_tests(tests_dir: Optional[Path] = None) -> List[Path]:
    """Discover all python unit test files in the repository (F26)."""
    base = tests_dir or (REPO_DIR / "tests")
    if not base.is_dir():
        return []
    return sorted(list(base.glob("**/test_*.py")))


def step_run_python_tests(timeout: float = TIMEOUT_PYTHON) -> bool:
    log_header("6. Running Python Tooling & Unit Tests")
    py_test_files = discover_python_tests()
    if not py_test_files:
        log_step("Python Unit Tests", "FAIL", "No python test files found in tests/ (required suite missing)")
        return False

    # Explicitly pass all discovered files so discovery and execution match 1:1 across all subdirectories
    test_args = [str(p.relative_to(REPO_DIR)) for p in py_test_files]
    cmd = [sys.executable, "-m", "unittest"] + test_args
    ok, out = run_command(cmd, REPO_DIR, "python unit tests", timeout=timeout)

    if not ok:
        log_step("Python Unit Tests", "FAIL", "Python unittest exited with non-zero code")
        print("\n--- Python Unit Tests Output ---")
        print(out)
        return False

    if "FAILED" in out:
        log_step("Python Unit Tests", "FAIL", "Failures or errors reported in python unit tests")
        print("\n--- Python Unit Tests Output ---")
        print(out)
        return False

    ran_match = re.search(r"Ran (\d+) tests?", out)
    if ran_match:
        test_count = ran_match.group(1)
        if int(test_count) == 0:
            log_step("Python Unit Tests", "FAIL", "Zero python tests were executed")
            return False
        log_step("Python Unit Tests", "PASS", f"All {test_count} python unit tests passed ({len(py_test_files)} test files)")
        return True

    log_step("Python Unit Tests", "PASS", f"Python tests passed ({len(py_test_files)} test files)")
    return True


def step_run_issue_18_verification(godot_bin: str, timeout: float = TIMEOUT_ISSUE_18) -> bool:
    log_header("7. Running Issue #18 Procedural World & Combat Verification")
    verifier = "tools/verify_issue_18.gd"
    verifier_path = REPO_DIR / verifier
    if not verifier_path.is_file():
        log_step("Issue #18 Verification", "FAIL", f"Required verifier script {verifier} missing in repository")
        return False

    cmd = [
        godot_bin,
        "--headless",
        "--path", str(REPO_DIR),
        "-s", verifier,
    ]
    ok, out = run_command(cmd, REPO_DIR, "issue 18 verification", timeout=timeout)
    if ok and "Summary:" in out and "0 Failed" in out:
        log_step("Issue #18 Verification", "PASS", "All procedural world, vertical combat, and streaming checks passed")
        return True
    else:
        log_step("Issue #18 Verification", "FAIL", "Verification failed or exited non-zero")
        print("\n--- Issue #18 Output ---")
        print(out)
        return False


def step_menu_smoke_run(godot_bin: str, timeout: float = TIMEOUT_MENU_SMOKE) -> bool:
    log_header("8. Headless Main Menu Smoke Run (60 frames)")
    cmd = [
        godot_bin,
        "--headless",
        "--path", str(REPO_DIR),
        "res://scenes/main_menu.tscn",
        "--quit-after", "60",
    ]
    ok, out = run_command(cmd, REPO_DIR, "menu smoke run", timeout=timeout)
    if ok and "SCRIPT ERROR:" not in out:
        log_step("Menu Smoke Run", "PASS", "Main menu initialized and ran 60 frames cleanly")
        return True
    else:
        log_step("Menu Smoke Run", "FAIL", "Runtime error during menu simulation")
        print("\n--- Menu Smoke Output ---")
        print(out[-2000:])
        return False


def step_gameplay_smoke_harness(godot_bin: str, timeout: float = TIMEOUT_GAMEPLAY_HARNESS) -> bool:
    log_header("9. Headless Gameplay Smoke Harness (F27)")
    harness = "tools/gameplay_smoke_harness.gd"
    if not (REPO_DIR / harness).is_file():
        log_step("Gameplay Smoke Harness", "FAIL", f"{harness} not found in repository")
        return False

    cmd = [
        godot_bin,
        "--headless",
        "--path", str(REPO_DIR),
        "-s", harness,
    ]
    ok, out = run_command(cmd, REPO_DIR, "gameplay smoke harness", timeout=timeout)
    if ok and "0 Failed" in out:
        log_step("Gameplay Smoke Harness", "PASS", "All 3 classes (Warrior, Archer, Engineer) validated combat hits and streaming")
        return True
    else:
        log_step("Gameplay Smoke Harness", "FAIL", "Gameplay smoke harness reported failures or non-zero exit")
        print("\n--- Gameplay Harness Output ---")
        print(out)
        return False


def main() -> None:
    print("\n" + "#" * 70)
    print(" CUBE SIEGE - AUTOMATED ENVIRONMENT & CODEBASE AUDIT")
    print("#" * 70)

    tools_ok, godot_bin = step_check_tools()
    if not tools_ok or not godot_bin:
        print("\n[ERROR] Missing required development tools. Verification aborted.")
        sys.exit(1)

    submodules_ok = step_check_submodules()
    if not submodules_ok:
        print("\n[ERROR] Git submodule check failed. Verification aborted.")
        sys.exit(1)

    build_ok = step_build_gdextension()
    if not build_ok:
        print("\n[ERROR] C++ GDExtension compilation failed. Verification aborted.")
        sys.exit(1)

    import_ok = step_headless_import(godot_bin)
    if not import_ok:
        print("\n[ERROR] Godot headless import failed. Verification aborted.")
        sys.exit(1)

    gut_ok = step_run_gut_tests(godot_bin)
    if not gut_ok:
        print("\n[ERROR] GUT tests failed. Verification aborted.")
        sys.exit(1)

    python_tests_ok = step_run_python_tests()
    if not python_tests_ok:
        print("\n[ERROR] Python tooling unit tests failed. Verification aborted.")
        sys.exit(1)

    issue_18_ok = step_run_issue_18_verification(godot_bin)
    if not issue_18_ok:
        print("\n[ERROR] Issue #18 verification failed. Audit aborted.")
        sys.exit(1)

    menu_ok = step_menu_smoke_run(godot_bin)
    if not menu_ok:
        print("\n[ERROR] Menu smoke run failed. Verification aborted.")
        sys.exit(1)

    gameplay_ok = step_gameplay_smoke_harness(godot_bin)
    if not gameplay_ok:
        print("\n[ERROR] Gameplay smoke harness failed. Verification aborted.")
        sys.exit(1)

    log_header("SUMMARY")
    print("  All verification stages completed successfully! Project is healthy.")
    print("=" * 70 + "\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
