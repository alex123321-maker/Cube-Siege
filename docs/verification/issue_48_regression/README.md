# Issue #48: reproducible baseline regression

The same [legacy-compatible test](../../../tests/regression/test_warrior_legacy_compatible.gd) ran on baseline `722bac40e1f4ba8f4619501dcc579a7d290ed1f1` and final gameplay `a953e945b13d1f07d9ab42bbd80d1f551b954ded`, with Godot 4.6.1 and isolated storage. Baseline gameplay handlers were not edited. See [results.json](results.json) for versions, test hash and exit codes.

- [Complete baseline output](baseline.log): exit 1, three behavioral failures, no missing methods/constants or script loading errors. Basic LMB damages both enemies and emits two confirmations; parry deals 30 counter damage and applies knockback; damage during the moving dash is ignored.
- [Complete final output](final.log): exit 0, all three tests and 26 assertions pass.
- [Full final verification](full-verify.log): native build, import, 321 GUT tests, 135 Python tests, 26 world checks, menu smoke and 24 gameplay checks pass.

This test adapts three final integration scenarios to the shared public interface. It omits the new `hits_landed` field and `is_dash_invulnerable()` method, and does not reference the new parry cooldown constants. It still calls real `perform_attack()`, `perform_utility()`, `perform_dash()` and `take_damage()`, uses physical overlaps, checks actual HP, hit signals, knockback and horizontal dash displacement. Both revisions execute the identical file. This is a behavioral control, not a source mutation test.

On baseline, `PlayerPrototype.take_damage()` passes `movement.is_dashing` directly into `PlayerHealth.take_damage()`, whose first guard rejects damage during a dash. There is no baseline `is_dash_invulnerable()` method.

## Reproduce in PowerShell

Run from a checkout containing this report. Set `$godotExe` to the installed Godot 4.6.1 executable. First run `python tools/verify.py` to build the unchanged native extension. Choose unused sibling directories for the two temporary worktrees.

```powershell
$sourceCheckout = (Get-Location).Path
$evidenceRevision = (git rev-parse HEAD).Trim()
$baselineDir = Join-Path (Split-Path $sourceCheckout -Parent) 'warrior-regression-baseline'
$finalDir = Join-Path (Split-Path $sourceCheckout -Parent) 'warrior-regression-final'
$godotExe = $env:GODOT_BIN
$env:CUBE_SIEGE_TEST_PROFILE = 'user://warrior_regression_reproduction/'

git worktree add --detach $baselineDir 722bac40e1f4ba8f4619501dcc579a7d290ed1f1
git worktree add --detach $finalDir a953e945b13d1f07d9ab42bbd80d1f551b954ded
foreach ($checkout in @($baselineDir, $finalDir)) {
    git -C $checkout restore --source=$evidenceRevision -- tests/regression
    Get-ChildItem -LiteralPath (Join-Path $sourceCheckout 'bin') -Filter '*.dll' |
        Copy-Item -Destination (Join-Path $checkout 'bin')
    & $godotExe --headless --editor --path $checkout --quit
    & $godotExe --headless --path $checkout -s addons/gut/gut_cmdln.gd `
        -gconfig=res://tests/regression/warrior_legacy.gutconfig.json
    Write-Output "Regression exit code: $LASTEXITCODE"
}
```

Expect three assertion failures and exit 1 on baseline, followed by three passing tests and exit 0 on final. The configuration deliberately selects only these three tests, without inheriting the full `.gutconfig.json` suite. Import can report the existing resource teardown warning; it is separate from the regression result. Bound import to 180 seconds and each regression process to 60 seconds as required by [operation timeouts](../../OPERATION_TIMEOUTS.md).

The previously published visual packet is for the same final gameplay revision. This follow-up changes only reproducibility evidence, not runtime behavior or visual output.
