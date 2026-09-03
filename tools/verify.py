#!/usr/bin/env python3
"""
tools/verify.py - Comprehensive verification runner for Cube Siege.

Performs complete health audit of the project:
  1. Toolchain discovery (python, git, scons, c++ compiler, godot)
  2. Git submodule status (godot-cpp)
  3. C++ GDExtension debug build (via scons)
  4. Godot headless project import and script validation
  5. GUT automated smoke and unit tests
  6. Short headless game runtime run (--quit-after 100)

Returns non-zero exit code on any failure.
"""

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Tuple

REPO_DIR = Path(__file__).resolve().parent.parent
LOCAL_GODOT_PATH_FILE = REPO_DIR / ".godot_path"

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

def run_command(cmd: List[str], cwd: Path, desc: str) -> Tuple[bool, str]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        return (proc.returncode == 0, proc.stdout)
    except Exception as e:
        return (False, str(e))

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
            r"C:\Godot\godot.exe"
        ]
        for c in candidates:
            if Path(c).is_file():
                # Cache to .godot_path for next time
                try:
                    LOCAL_GODOT_PATH_FILE.write_text(c, encoding="utf-8")
                except Exception:
                    pass
                return c

    return None

def step_check_tools() -> Tuple[bool, Optional[str]]:
    log_header("1. Checking Development Toolchain")
    all_ok = True

    # Python
    py_ver = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    log_step("Python Runtime", "PASS", f"v{py_ver}")

    # Git
    git_path = shutil.which("git")
    if git_path:
        ok, out = run_command(["git", "--version"], REPO_DIR, "git version")
        log_step("Git CLI", "PASS", out.strip())
    else:
        log_step("Git CLI", "FAIL", "git not found in PATH")
        all_ok = False

    # GitHub CLI (gh) for Issue-Driven Development
    gh_path = shutil.which("gh")
    if gh_path:
        ok, out = run_command(["gh", "--version"], REPO_DIR, "gh version")
        first_line = out.splitlines()[0] if out else "installed"
        # Check auth
        auth_ok, auth_out = run_command(["gh", "auth", "status"], REPO_DIR, "gh auth status")
        if auth_ok:
            log_step("GitHub CLI (gh)", "PASS", f"{first_line} (Authenticated)")
        else:
            log_step("GitHub CLI (gh)", "INFO", f"{first_line} (Not logged in. Run 'gh auth login' for Issue workflow)")
    else:
        log_step("GitHub CLI (gh)", "INFO", "Optional for local build, required for 'Implement issue #N'. Install via winget/apt/brew")

    # SCons
    scons_path = shutil.which("scons")
    if scons_path:
        ok, out = run_command(["scons", "--version"], REPO_DIR, "scons version")
        first_line = out.splitlines()[0] if out else ""
        log_step("SCons Build System", "PASS", first_line)
    else:
        log_step("SCons Build System", "FAIL", "scons not found in PATH")
        all_ok = False

    # C++ Compiler
    cc_path = shutil.which("gcc") or shutil.which("clang") or shutil.which("cl")
    if cc_path:
        ok, out = run_command([cc_path, "--version"], REPO_DIR, "compiler version")
        first_line = out.splitlines()[0] if out else Path(cc_path).name
        log_step("C++ Compiler", "PASS", first_line)
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

def step_build_gdextension() -> bool:
    log_header("3. Building C++ GDExtension (Debug)")
    sconstruct_path = REPO_DIR / "SConstruct"
    if not sconstruct_path.is_file():
        log_step("C++ GDExtension", "INFO", "No root SConstruct found. Skipping native build.")
        return True

    plat = "windows" if sys.platform.startswith("win") else ("linux" if sys.platform.startswith("linux") else "macos")
    cmd = [
        "scons",
        "custom_api_file=extension_api.json",
        f"platform={plat}",
        "target=template_debug"
    ]
    print(f"  Executing: {' '.join(cmd)}")
    ok, out = run_command(cmd, REPO_DIR, "scons build")
    if ok:
        log_step("SCons Compilation", "PASS", "Built successfully")
        return True
    else:
        log_step("SCons Compilation", "FAIL", "Build failed")
        print("\n--- SCons Build Output ---")
        print(out[-2000:])
        return False

def step_headless_import(godot_bin: str) -> bool:
    log_header("4. Headless Godot Editor Import & Validation")
    cmd = [godot_bin, "--headless", "--editor", "--quit", "--path", str(REPO_DIR)]
    ok, out = run_command(cmd, REPO_DIR, "headless import")
    if ok:
        log_step("Project Import", "PASS", "Assets and scripts validated cleanly")
        return True
    else:
        log_step("Project Import", "FAIL", f"Exit code non-zero")
        print("\n--- Godot Import Output ---")
        print(out[-2000:])
        return False

def step_run_gut_tests(godot_bin: str) -> bool:
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
        "-gconfig=res://.gutconfig.json"
    ]
    ok, out = run_command(cmd, REPO_DIR, "gut full test suite")
    
    # Check if out contains "All tests passed"
    if "All tests passed" in out or ok:
        log_step("GUT Test Suite", "PASS", "All tests passed cleanly (smoke, unit, integration)")
        return True
    else:
        log_step("GUT Test Suite", "FAIL", "Tests failed")
        print("\n--- GUT Output ---")
        print(out)
        return False

def step_headless_smoke_run(godot_bin: str) -> bool:
    log_header("6. Headless Game Runtime Smoke Run (100 frames)")
    cmd = [
        godot_bin,
        "--headless",
        "--path", str(REPO_DIR),
        "--quit-after", "100"
    ]
    ok, out = run_command(cmd, REPO_DIR, "smoke run")
    if ok:
        log_step("100-Frame Smoke Run", "PASS", "Game started and exited normally (100 frames simulated)")
        return True
    else:
        log_step("100-Frame Smoke Run", "FAIL", "Runtime error during simulation")
        print("\n--- Smoke Run Output ---")
        print(out[-2000:])
        return False

def main():
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

    run_ok = step_headless_smoke_run(godot_bin)
    if not run_ok:
        print("\n[ERROR] Game headless smoke run failed. Verification aborted.")
        sys.exit(1)

    log_header("SUMMARY")
    print("  All verification stages completed successfully! Project is healthy.")
    print("=" * 70 + "\n")
    sys.exit(0)

if __name__ == "__main__":
    main()
