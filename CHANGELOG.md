# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Fixed
- Improved the Model settings UX so download state, retry errors, local install details, and folder access are surfaced in one place.
- Prevented sherpa/ONNX native recognizer construction failures from aborting the app process; model load errors now surface in-app.

## [0.0.3] - 2026-03-15
### Added
- Custom status bar icon and app icon assets with SF Symbol fallback
- Manual updater v1 with launch-time background checks, menu-bar update actions, and checksum-verified downloads
- Pixel-faithful main window rebuild with dedicated `Dashboard`, `History`, `Hotkey`, `Model`, `Vocabulary`, `LLM`, and `General` pages
- Persisted history store with session duration tracking shared by Dashboard and History
- Configurable global hold-to-talk shortcuts, preferred microphone selection, vocabulary management, and launch-at-login controls
- Open-source governance documents, CI and release automation, release packaging and verification scripts

### Changed
- Renamed app from VibeStroke to Suniye

## [0.0.2] - 2026-02-22
### Added
- Main window split into dedicated Stats, Settings, About, and shared components for maintainability.
- New LLM settings controls in-app for timeout and max tokens with persistence.
- Centralized attention item model to surface runtime/configuration issues in UI.

### Fixed
- Prevented false `ready` state when recognizer load fails.
- Corrected recent activity metadata so LLM labels are derived from LLM output changes only.
- Stabilized CI release/debug app builds to use the active host architecture.
- Hardened CI model setup with retry + archive validation before extraction.

## [0.0.1] - 2026-02-22
### Added
- Initial public prerelease baseline
