[CmdletBinding()]
param(
    [ValidateSet('blender-only')]
    [string]$Backend = 'blender-only'
)

$ErrorActionPreference = 'Stop'
Write-Host 'Cube Siege AI backend: blender-only'
Write-Host 'No Python environment or checkpoint is installed on this hardware.'
Write-Host 'Reason: no NVIDIA GPU/CUDA runtime; evaluated upstream backends require CUDA-class acceleration.'
Write-Host 'Run: python tools/art_pipeline/check_environment.py --format markdown'
Write-Host 'Re-evaluate docs/art_pipeline/LICENSES.md before approving any future model/checkpoint.'
