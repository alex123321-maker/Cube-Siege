[CmdletBinding()]
param(
    [string]$BlenderBin = $env:BLENDER_BIN,
    [string]$GodotBin = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$blenderDir = Join-Path $PSScriptRoot 'blender'
$verificationDir = Join-Path $repoRoot 'docs\art_pipeline\verification'
$workDir = Join-Path $repoRoot 'art\work\pipeline_verification'
$referenceDir = Join-Path $workDir 'references'
$referenceBlend = Join-Path $workDir 'reference_setup.blend'
$testBlend = Join-Path $repoRoot 'art\pipeline_test\calibration_blockout.blend'
$testGlb = Join-Path $repoRoot 'assets\models\validation\calibration_blockout.glb'
$renderDir = Join-Path $verificationDir 'renders'

function Find-Tool([string]$Configured, [string[]]$Candidates) {
    if ($Configured -and (Test-Path -LiteralPath $Configured -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $Configured).Path
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Invoke-Checked([string]$Name, [string]$Executable, [string[]]$Arguments) {
    Write-Host "`n[$Name] $Executable $($Arguments -join ' ')"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

$BlenderBin = Find-Tool $BlenderBin @(
    'D:\ProgramFiles\cube-siege-art-tools\blender-5.2.1-windows-x64\blender.exe',
    'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
)
$GodotBin = Find-Tool $GodotBin @(
    'D:\ProgramFiles\godot\Godot_v4.6.1-stable_win64_console.exe',
    'C:\Program Files\Godot\godot.exe'
)
if (-not $BlenderBin) { throw 'Blender not found. Run tools/art_pipeline/setup_blender.ps1 or set BLENDER_BIN.' }
if (-not $GodotBin) { throw 'Godot not found. Set GODOT_BIN to a project-compatible Godot 4.6 executable.' }

New-Item -ItemType Directory -Force -Path $verificationDir, $referenceDir, $renderDir, (Split-Path $testBlend), (Split-Path $testGlb) | Out-Null

Invoke-Checked 'Blender runtime' $BlenderBin @('--background', '--factory-startup', '--python-exit-code', '1', '--python', (Join-Path $blenderDir 'validate_blender.py'), '--', '--report', (Join-Path $verificationDir 'blender_report.json'))
Invoke-Checked 'Synthetic references' $BlenderBin @('--background', '--factory-startup', '--python-exit-code', '1', '--python', (Join-Path $blenderDir 'create_test_references.py'), '--', '--output-dir', $referenceDir)
Invoke-Checked 'Reference placement' $BlenderBin @('--background', '--factory-startup', '--python-exit-code', '1', '--python', (Join-Path $blenderDir 'import_reference.py'), '--', '--front', (Join-Path $referenceDir 'front.png'), '--side', (Join-Path $referenceDir 'side.png'), '--back', (Join-Path $referenceDir 'back.png'), '--three-quarter', (Join-Path $referenceDir 'three_quarter.png'), '--output-blend', $referenceBlend, '--report', (Join-Path $verificationDir 'reference_report.json'))
Invoke-Checked 'Calibration blockout' $BlenderBin @('--background', '--factory-startup', '--python-exit-code', '1', '--python', (Join-Path $blenderDir 'create_test_asset.py'), '--', '--output-blend', $testBlend)
Invoke-Checked 'Turnaround renders' $BlenderBin @('--background', $testBlend, '--python-exit-code', '1', '--python', (Join-Path $blenderDir 'render_turnaround.py'), '--', '--output-dir', $renderDir, '--resolution', '512', '--report', (Join-Path $verificationDir 'render_report.json'))
Invoke-Checked 'GLB export' $BlenderBin @('--background', $testBlend, '--python-exit-code', '1', '--python', (Join-Path $blenderDir 'export_gltf.py'), '--', '--output', $testGlb, '--report', (Join-Path $verificationDir 'export_report.json'))
Invoke-Checked 'Godot headless import' $GodotBin @('--headless', '--editor', '--recovery-mode', '--import', '--path', $repoRoot)
Invoke-Checked 'Godot GLB contract' $GodotBin @('--headless', '--path', $repoRoot, '--script', (Join-Path $repoRoot 'tools\art_pipeline\godot\validate_import.gd'), '--', '--asset', 'res://assets/models/validation/calibration_blockout.glb', '--report', 'res://docs/art_pipeline/verification/godot_report.json')

Write-Host "`nArt pipeline verification passed. Evidence: $verificationDir"
