#!/usr/bin/env python3
"""Collect a dependency-free hardware/toolchain report for the art pipeline."""

from __future__ import annotations

import argparse
import base64
import ctypes
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def run(command: list[str]) -> dict[str, Any]:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
        )
        output = (result.stdout or result.stderr).strip()
        return {"available": result.returncode == 0, "output": output, "returncode": result.returncode}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"available": False, "output": str(exc), "returncode": None}


def windows_cim(class_name: str, properties: list[str]) -> list[dict[str, Any]]:
    if platform.system() != "Windows":
        return []
    quoted = ",".join(properties)
    command = [
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        f"$json = Get-CimInstance {class_name} | Select-Object {quoted} | ConvertTo-Json -Compress; "
        "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))",
    ]
    result = run(command)
    if not result["available"] or not result["output"]:
        return []
    try:
        decoded = base64.b64decode(result["output"]).decode("utf-8")
        parsed = json.loads(decoded)
        return parsed if isinstance(parsed, list) else [parsed]
    except json.JSONDecodeError:
        return []


def total_memory_bytes() -> int | None:
    if platform.system() == "Windows":
        class MemoryStatus(ctypes.Structure):
            _fields_ = [
                ("length", ctypes.c_ulong),
                ("memory_load", ctypes.c_ulong),
                ("total_physical", ctypes.c_ulonglong),
                ("available_physical", ctypes.c_ulonglong),
                ("total_page_file", ctypes.c_ulonglong),
                ("available_page_file", ctypes.c_ulonglong),
                ("total_virtual", ctypes.c_ulonglong),
                ("available_virtual", ctypes.c_ulonglong),
                ("available_extended_virtual", ctypes.c_ulonglong),
            ]

        status = MemoryStatus()
        status.length = ctypes.sizeof(MemoryStatus)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return int(status.total_physical)
        return None
    try:
        return int(os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES"))
    except (AttributeError, ValueError, OSError):
        return None


def find_binary(env_name: str, names: list[str], candidates: list[Path]) -> str | None:
    configured = os.environ.get(env_name)
    if configured and Path(configured).is_file():
        return str(Path(configured).resolve())
    for name in names:
        located = shutil.which(name)
        if located:
            return str(Path(located).resolve())
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate.resolve())
    return None


def bytes_to_gib(value: int | None) -> float | None:
    return round(value / (1024**3), 2) if value is not None else None


def collect() -> dict[str, Any]:
    gpu_rows = windows_cim("Win32_VideoController", ["Name", "AdapterCompatibility", "AdapterRAM", "DriverVersion"])
    cpu_rows = windows_cim("Win32_Processor", ["Name", "NumberOfCores", "NumberOfLogicalProcessors"])
    os_rows = windows_cim("Win32_OperatingSystem", ["Caption", "Version", "BuildNumber", "OSArchitecture"])

    blender = find_binary(
        "BLENDER_BIN",
        ["blender", "blender.exe"],
        [
            Path(r"D:\ProgramFiles\cube-siege-art-tools\blender-5.2.1-windows-x64\blender.exe"),
            Path(r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"),
        ],
    )
    godot = find_binary(
        "GODOT_BIN",
        ["godot", "godot4", "godot.exe", "godot4.exe"],
        [
            Path(r"D:\ProgramFiles\godot\Godot_v4.6.1-stable_win64_console.exe"),
            Path(r"C:\Program Files\Godot\godot.exe"),
        ],
    )
    disk = shutil.disk_usage(REPO_ROOT.anchor or str(REPO_ROOT))
    nvidia = run(["nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"])
    cuda = run(["nvcc", "--version"])
    git = run(["git", "--version"])
    blender_version = run([blender, "--background", "--version"]) if blender else {"available": False, "output": "not found"}
    godot_version = run([godot, "--version"]) if godot else {"available": False, "output": "not found"}

    for gpu in gpu_rows:
        raw_ram = gpu.get("AdapterRAM")
        gpu["AdapterRAMGiBReported"] = bytes_to_gib(int(raw_ram)) if raw_ram else None

    return {
        "schema_version": 1,
        "repository": str(REPO_ROOT),
        "os": os_rows[0] if os_rows else {"system": platform.system(), "release": platform.release()},
        "cpu": cpu_rows,
        "ram_gib": bytes_to_gib(total_memory_bytes()),
        "gpu": gpu_rows,
        "nvidia_smi": nvidia,
        "cuda_toolkit": cuda,
        "disk": {
            "volume": REPO_ROOT.anchor,
            "total_gib": bytes_to_gib(disk.total),
            "used_gib": bytes_to_gib(disk.used),
            "free_gib": bytes_to_gib(disk.free),
        },
        "python": {"executable": sys.executable, "version": platform.python_version()},
        "git": git,
        "blender": {"path": blender, "version_check": blender_version},
        "godot": {"path": godot, "version_check": godot_version},
    }


def markdown(report: dict[str, Any]) -> str:
    os_data = report["os"]
    cpu = report["cpu"][0] if report["cpu"] else {}
    gpu_lines = []
    for gpu in report["gpu"]:
        gpu_lines.append(
            f"- {gpu.get('Name', 'unknown')} — driver {gpu.get('DriverVersion', 'unknown')}, "
            f"reported adapter memory {gpu.get('AdapterRAMGiBReported', 'unknown')} GiB"
        )
    if not gpu_lines:
        gpu_lines.append("- No GPU data available")
    return "\n".join(
        [
            "# Art pipeline hardware report",
            "",
            f"- OS: {os_data.get('Caption', os_data.get('system', 'unknown'))} "
            f"{os_data.get('Version', os_data.get('release', ''))} ({os_data.get('OSArchitecture', platform.machine())})",
            f"- CPU: {cpu.get('Name', platform.processor() or 'unknown')} "
            f"({cpu.get('NumberOfCores', '?')} cores / {cpu.get('NumberOfLogicalProcessors', '?')} threads)",
            f"- RAM: {report['ram_gib']} GiB",
            "- GPU:",
            *gpu_lines,
            f"- NVIDIA driver: {report['nvidia_smi']['output'] if report['nvidia_smi']['available'] else 'not available'}",
            f"- CUDA toolkit: {report['cuda_toolkit']['output'] if report['cuda_toolkit']['available'] else 'not available'}",
            f"- Repository disk free: {report['disk']['free_gib']} GiB on {report['disk']['volume']}",
            f"- Python: {report['python']['version']} ({report['python']['executable']})",
            f"- Git: {report['git']['output']}",
            f"- Blender: {report['blender']['path'] or 'not found'}",
            f"- Godot: {report['godot']['path'] or 'not found'}",
            "",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    args = parser.parse_args()
    report = collect()
    print(markdown(report) if args.format == "markdown" else json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
