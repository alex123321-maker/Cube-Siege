# /review-ready

Workflow for certifying a feature or bugfix as PR-ready:

1. **Build & Test**: Run `python tools/verify.py` to confirm zero errors.
2. **Project Health**: Ensure headless import and script validation pass cleanly.
3. **Acceptance Criteria Checklist**: Generate a checklist of all criteria from the Issue (`[x]` for verified, `[ ]` with reason for unverified).
4. **Git Diff Audit**: Inspect `git diff` for out-of-scope changes, design constants alterations, or debug artifacts.
5. **Documentation**: Ensure `docs/STATUS.md` is updated if subcomponents changed.
6. **PR-Ready Summary**: Create structured PR report with `Closes #N`, test evidence, and remaining limitations.
