# /implement-feature

Workflow for implementing a feature from a GitHub Issue or user specification:

1. **Read Issue**: Use `gh issue view <number>` to extract the authoritative Feature Contract.
2. **Inspect Implementation**: Examine existing scenes and scripts without modifying them.
3. **Ambiguity Check**: If design details are missing, emit `DESIGN DECISION REQUIRED`. Do not guess.
4. **Technical Plan**: Formulate an engineering plan preserving project invariants.
5. **Issue Branch**: Create branch `feat/<issue-number>-<slug>`.
6. **Tests First**: Add unit/smoke tests verifying the contract.
7. **Implementation**: Minimal code changes, adhering to `gdscript.md` / `cpp-gdextension.md`.
8. **Godot Validation**: Run headless import and script checks.
9. **Runtime Playtest**: Run the scene/game, observe runtime logs and behavior.
10. **Acceptance Criteria**: Verify each criterion individually.
11. **Git Diff**: Review diff for unintended changes.
12. **PR Report**: Produce PR summary with `Closes #N` and verified AC checklist.
