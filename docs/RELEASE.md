# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

Release automation treats the git tag as the source of truth for `MARKETING_VERSION`.
Release automation derives `CURRENT_PROJECT_VERSION` from one shared build-number formula: `git_commit_count * 10 + channel_rank`.
Stable uses channel rank `8`; Tip uses channel rank `1`. That makes a stable release from the same commit newer than its tip build, while the next main-branch tip build becomes newer again.
For local packaging, let `scripts/package_release.sh` compute the build number or pass `--build-number` / `SUNIYE_BUILD_NUMBER` for an explicit override.
Do not manually bump app version metadata in `project.yml` just to cut a release tag.

Release packaging always uses the default Stable app identity: `Suniye.app`, bundle id `dev.suniye.app`, and Sparkle release updates enabled. Local development builds that need to coexist with Stable should use `./scripts/build_app.sh Debug --preview --install-user --open`, which produces `Suniye Preview.app` with bundle id `dev.suniye.app.preview` and Sparkle release updates disabled. Do not publish Preview artifacts as official releases.

## Prerelease checklist
1. PR description and commits reflect the release changes accurately.
2. User-facing docs are updated for onboarding, settings, and supported model changes (`README.md`, `docs/*`).
3. `./scripts/doctor.sh` passes.
4. `./scripts/setup_llama_cpp.sh` has staged `Suniye/LocalLLM/llama-server` for Local Gemma.
5. `./scripts/e2e_preflight.sh` passes.
6. `./scripts/e2e_smoke.sh` passes.
7. `SUNIYE_CODESIGN_IDENTITY="Suniye Self-Signed Release" ./scripts/package_release.sh --version <version> --build-channel stable` runs locally.
8. `./scripts/verify_release.sh --dist-dir dist --version <version> --build-channel stable` passes.
9. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).
10. If the ASR catalog changed, verify the supported model names and download assets still match the published sherpa-onnx artifacts.

## Publish
1. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
2. GitHub Actions `release.yml` asks GitHub to generate release notes for the tag, embeds them in the Sparkle appcast, injects the tag version, computes the stable build number, builds artifacts, and creates the release.

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
Both Stable and Tip appcasts must include Sparkle release notes, either as an embedded `<description>` or a `<sparkle:releaseNotesLink>`.

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

## Code signing identity
Until Suniye moves to Apple Developer ID signing, releases use one long-lived self-signed code-signing identity named `Suniye Self-Signed Release`.

This identity is not trusted by Gatekeeper and does not notarize the app. Its purpose is to keep Suniye's designated requirement stable across updates so macOS Microphone and Accessibility permissions do not reset on every release.

Create the identity on the release owner's Mac:
1. Open Keychain Access.
2. Choose **Keychain Access > Certificate Assistant > Create a Certificate**.
3. Name it `Suniye Self-Signed Release`.
4. Choose **Self Signed Root** for identity type.
5. Choose **Code Signing** for certificate type.
6. Enable **Let me override defaults** and use a long validity period.
7. Finish certificate creation and confirm it appears in the login keychain with a private key.

Export the identity:
1. In Keychain Access, select the `Suniye Self-Signed Release` identity, including its private key.
2. Export as a password-protected `.p12`.
3. Store the `.p12` and password in a password manager.
4. Generate the GitHub secret value:
```bash
base64 -i Suniye-Self-Signed-Release.p12 | tr -d '\n' | pbcopy
```

Configure GitHub Actions secrets:
- `SUNIYE_CODESIGN_CERTIFICATE_P12_BASE64`: base64-encoded `.p12`
- `SUNIYE_CODESIGN_CERTIFICATE_PASSWORD`: `.p12` export password
- `SUNIYE_CODESIGN_IDENTITY`: `Suniye Self-Signed Release`

For an emergency local release, import the `.p12` into the local keychain and run:
```bash
SUNIYE_CODESIGN_IDENTITY="Suniye Self-Signed Release" \
  ./scripts/package_release.sh --version vX.Y.Z --build-channel stable --dist-dir dist
```

Do not rotate or recreate this self-signed identity unless there is no alternative. Changing it changes Suniye's designated requirement and can force users to grant Microphone and Accessibility permissions again.

Users moving from the current ad hoc-signed releases to the first self-signed release may need to grant Microphone and Accessibility permissions one more time. A later migration to Apple Developer ID signing will likely cause one more permission regrant, then should stabilize under the Apple Team ID.

## Homebrew tap
Stable releases publish a Homebrew Cask to the custom tap `kishanhitk/homebrew-tap`, so users can `brew install --cask kishanhitk/tap/suniye`.

`release.yml` runs `scripts/update_homebrew_tap.sh` after creating the GitHub release. It renders `packaging/homebrew/suniye.rb.tmpl` (injecting the tag version and the `Suniye.dmg` checksum from `SHA256SUMS.txt`) and pushes `Casks/suniye.rb` to the tap. The cask strips the download quarantine in a `postflight` so the self-signed app launches without a Gatekeeper prompt.

One-time setup:
1. Create the public repo `kishanhitk/homebrew-tap` (casks live under `Casks/`). Seed the first cask by running this from a checkout with `dist/` populated by a local `package_release.sh`:
```bash
HOMEBREW_TAP_TOKEN=<token> ./scripts/update_homebrew_tap.sh --version vX.Y.Z --dist-dir dist
```
2. Create a fine-grained personal access token with **Contents: Read and write** on `kishanhitk/homebrew-tap`, then add it as the GitHub Actions secret `HOMEBREW_TAP_TOKEN`.

If `HOMEBREW_TAP_TOKEN` is unset, the release step logs a warning and exits successfully, so the rest of the release is unaffected.

Official `homebrew-cask` is intentionally not targeted yet: it requires notarization (Suniye is self-signed) and higher repository notability. Revisit after moving to Apple Developer ID signing.

## Update contract
Sparkle updater behavior depends on release artifact names and signed appcast metadata:
- Preferred install artifact: `Suniye.dmg`
- Fallback install artifact: `Suniye.app.zip`
- Checksum manifest: `SHA256SUMS.txt`
- Sparkle appcast: `appcast.xml`, served to the app from `https://suniye.kishans.in/appcast.xml`
- Tip appcast: `appcast.xml` on the `tip` prerelease, served to the app from `https://suniye.kishans.in/appcast-tip.xml`
- App code signing: all Stable and Tip release artifacts must use the same `Suniye Self-Signed Release` identity.

`SHA256SUMS.txt` must include checksum lines for published artifacts, especially `Suniye.dmg`.
