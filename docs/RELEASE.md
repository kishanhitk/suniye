# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

Release automation treats the git tag as the source of truth for `MARKETING_VERSION`.
Release automation derives `CURRENT_PROJECT_VERSION` from one shared build-number formula: `git_commit_count * 10 + channel_rank`.
Stable uses channel rank `8`; Tip uses channel rank `1`. That makes a stable release from the same commit newer than its tip build, while the next main-branch tip build becomes newer again.
For local packaging, let `scripts/package_release.sh` compute the build number or pass `--build-number` / `SUNIYE_BUILD_NUMBER` for an explicit override.
Do not manually bump app version metadata in `project.yml` just to cut a release tag.

## Pre-release checklist
1. PR description and commits reflect the release changes accurately.
2. User-facing docs are updated for onboarding, settings, and supported model changes (`README.md`, `docs/*`).
3. `./scripts/doctor.sh` passes.
4. `./scripts/e2e_preflight.sh` passes.
5. `./scripts/e2e_smoke.sh` passes.
6. `./scripts/package_release.sh --version <version> --build-channel stable` runs locally.
7. `./scripts/verify_release.sh --dist-dir dist --version <version> --build-channel stable` passes.
8. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).
9. If the ASR catalog changed, verify the supported model names and download assets still match the published sherpa-onnx artifacts.

## Publish
1. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
2. GitHub Actions `release.yml` injects the tag version, computes the stable build number, builds artifacts, and creates the release.

## Tip builds
Every push to `main` publishes a mutable prerelease/tag named `tip`.

The Tip workflow packages the latest `main` commit with:
```bash
./scripts/package_release.sh \
  --version <latest-tag> \
  --build-channel tip \
  --appcast-channel tip \
  --download-url-prefix https://github.com/kishanhitk/suniye/releases/download/tip/
```

The Tip appcast is served from `https://suniye.kishans.in/appcast-tip.xml`.

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
- Tip appcast: `appcast.xml` on the `tip` prerelease, served to the app from `https://suniye.kishans.in/appcast-tip.xml`

`SHA256SUMS.txt` must include checksum lines for published artifacts, especially `Suniye.dmg`.
