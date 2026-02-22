# Contributing to VibeStoke

Thanks for your interest in contributing.

## Development setup
1. Install full Xcode and select it with `xcode-select`.
2. Install XcodeGen: `brew install xcodegen`.
3. Build runtime dependencies: `./scripts/setup_sherpa.sh`.
4. Download ASR model: `./scripts/setup_model.sh`.
5. Validate environment: `./scripts/doctor.sh`.
6. Build app: `./scripts/build_app.sh Debug`.

## Workflow
1. Create a feature branch.
2. Keep changes small and focused.
3. Run checks locally before opening PR:
   - `./scripts/e2e_preflight.sh`
   - `./scripts/e2e_smoke.sh`
4. Update docs/changelog when behavior changes.

## Pull request expectations
- Explain the problem and solution.
- Include test evidence (commands + result).
- Call out risks and follow-ups.

## Commit and versioning
- Use clear commit messages.
- Releases use semantic version tags: `vMAJOR.MINOR.PATCH`.
