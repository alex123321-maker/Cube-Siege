# /fix-bug

Workflow for fixing bugs with mandatory reproduction:

1. **Read Bug Issue**: Extract Current, Expected, Reproduction Steps, Acceptance Criteria.
2. **Reproduce**: Replicate the bug before modifying any code and collect evidence.
3. **Regression Test**: Add a failing test verifying the bug scenario.
4. **Root Cause**: Locate the true cause, create branch `fix/<issue-number>-<slug>`.
5. **Minimal Fix**: Apply targeted fix without drive-by changes.
6. **Reproduce Again**: Verify the original scenario no longer fails and regression test passes.
7. **Full Verification**: Run `python tools/verify.py`.
8. **PR**: Open PR with `Fixes #N` and verified AC.
