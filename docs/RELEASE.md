# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

Release automation treats the git tag as the source of truth for `MARKETING_VERSION`.
GitHub release automation derives `CURRENT_PROJECT_VERSION` from `GITHUB_RUN_NUMBER`, which is monotonic for the Release workflow and keeps Sparkle update ordering stable across normal and hotfix release branches.
For local packaging, pass `--build-number` or set `SUNIYE_BUILD_NUMBER` when you need to match or preview an exact release build. If neither value is supplied outside GitHub Actions, the scripts fall back to `git rev-list --count HEAD` for local test artifacts only.
Do not manually bump app version metadata in `project.yml` just to cut a release tag.

## Pre-release checklist
1. PR description and commits reflect the release changes accurately.
2. User-facing docs are updated for onboarding, settings, and supported model changes (`README.md`, `docs/*`).
3. `./scripts/doctor.sh` passes.
4. `./scripts/e2e_preflight.sh` passes.
5. `./scripts/e2e_smoke.sh` passes.
6. `./scripts/package_release.sh --version <version>` runs locally.
7. `./scripts/verify_release.sh --dist-dir dist --version <version>` passes.
8. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).
9. If the ASR catalog changed, verify the supported model names and download assets still match the published sherpa-onnx artifacts.

## Publish
1. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
2. GitHub Actions `release.yml` injects the tag version, derives the build number from git history, builds artifacts, and creates the release.

## Artifacts
- `Suniye.dmg`
- `Suniye.app.zip`
- `SHA256SUMS.txt`
- `appcast.xml`

## Sparkle signing key
GitHub Actions stores the Sparkle private key in `SPARKLE_PRIVATE_KEY`, but GitHub secrets are write-only and cannot be retrieved later.

The local owner copy is stored in the macOS Keychain under Sparkle account `suniye`. To export it from a Sparkle distribution:
```bash
./bin/generate_keys --account suniye -x ./suniye-sparkle-private-key
```
Move the exported file to a password manager or another secret store, then delete the local export.

## Update contract
Sparkle updater behavior depends on release artifact names and signed appcast metadata:
- Preferred install artifact: `Suniye.dmg`
- Fallback install artifact: `Suniye.app.zip`
- Checksum manifest: `SHA256SUMS.txt`
- Sparkle appcast: `appcast.xml`, served to the app from `https://suniye.kishans.in/appcast.xml`

`SHA256SUMS.txt` must include checksum lines for published artifacts, especially `Suniye.dmg`.
