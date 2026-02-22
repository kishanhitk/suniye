# VibeStoke — Native macOS Dictation App

## Context
Build a minimal, local-only speech-to-text dictation app for macOS (like WisprFlow/SuperWhisper). Uses NVIDIA Parakeet TDT 0.6B v3 via sherpa-onnx C API for transcription. User confirmed Parakeet works well for Indian English accent on M1 MacBook Air 16GB. No Electron — pure Swift/SwiftUI.

**Project directory**: `/Users/kishan/dev/vibestroke`

## Architecture

```
VibeStoke/
├── VibeStoke.swift                 -- @main, MenuBarExtra
├── AppState.swift                  -- Central state machine (@Observable)
├── Views/
│   ├── MenuBarView.swift           -- Menu bar popover (status, quick actions)
│   ├── OnboardingView.swift        -- First-launch welcome + model download UI
│   ├── MainWindowView.swift        -- Stats homepage (opens from menu bar)
│   ├── SidebarView.swift           -- Settings, About, Stats navigation
│   ├── ListeningOverlay.swift      -- Subtle animation when fn/globe held
│   ├── WelcomeView.swift           -- First page of onboarding
│   └── ModelDownloadView.swift     -- Second page of onboarding
├── Services/
│   ├── AudioCaptureService.swift   -- AVAudioEngine, 48kHz→16kHz conversion
│   ├── TranscriptionService.swift  -- sherpa-onnx C API wrapper
│   ├── HotkeyService.swift         -- Global NSEvent monitors (hold-to-talk)
│   ├── TextInsertionService.swift  -- Clipboard save → Cmd+V → restore
│   └── ModelManager.swift          -- Download, extract, validate model
├── SherpaOnnx.swift                -- Official Swift wrapper (copied from sherpa-onnx repo)
├── VibeStoke-Bridging-Header.h     -- #import "c-api.h"
├── c-api.h                         -- Copied from sherpa-onnx
└── Frameworks/
    ├── libsherpa-onnx-c-api.dylib
    └── libonnxruntime.dylib
```

## Pipeline

```
Hold fn/globe key → AVAudioEngine captures mic (48kHz) + listening animation starts
  → AVAudioConverter downsamples to 16kHz mono Float32
  → Samples buffered in memory
Release fn/globe key → Samples fed to sherpa-onnx offline recognizer
  → Parakeet TDT decodes → raw text
  → Final text result
  → Save clipboard → Set text → CGEvent Cmd+V → Restore clipboard (450ms)
```

## Build Phases (MVP Order)

### Phase 1: Pre-requisites — Build sherpa-onnx dylibs
- Clone sherpa-onnx repo, run `build-swift-macos.sh`
- Output: `libsherpa-onnx-c-api.dylib` + `libonnxruntime.dylib`
- Copy `swift-api-examples/SherpaOnnx.swift` and `sherpa-onnx/c-api/c-api.h`
- Manually download Parakeet model for testing:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2`

### Phase 2: Xcode project skeleton
- SwiftUI app with `MenuBarExtra`, `LSUIElement = YES` (no Dock icon)
- Link dylibs in Frameworks/, set up bridging header
- Fix dylib install names with `install_name_tool`
- Entitlements: no sandbox (CGEvent needs it), mic usage description
- Basic `MenuBarView` showing status + quit button

### Phase 3: TranscriptionService
- Wrap sherpa-onnx C API: create recognizer → create stream → accept waveform → decode → get result
- Config: transducer encoder/decoder/joiner paths, tokens, model_type="nemo_transducer", num_threads=4, greedy_search
- Test with a hardcoded WAV file to validate integration

### Phase 4: AudioCaptureService
- AVAudioEngine input node tap at hardware rate
- AVAudioConverter to 16kHz mono Float32
- Buffer samples in `[Float]` array with lock
- `startCapture()` / `stopCapture() -> [Float]`

### Phase 5: HotkeyService (hold-to-talk)
- `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents`
- `.flagsChanged` for fn/globe key (keyCode 179 / kVK_Function)
- Filter `isARepeat`, track `isHeld` state
- No fallback hotkey in MVP (fn/globe only)
- Callbacks: `onHotkeyDown` / `onHotkeyUp`
- Trigger listening animation overlay on screen

### Phase 6: TextInsertionService
- Save all clipboard `pasteboardItems` (preserve rich content)
- Set clipboard to transcribed text (plain string)
- `CGEvent` simulate Cmd+V (keyCode 9 with `.maskCommand`)
  - Target: active application regardless of type (browsers, terminals, Slack, etc.)
  - Works with: Ghostty, Slack, VS Code, Safari, Chrome, TextEdit, Notes
  - Does NOT work when: Secure Input is active (password fields, Lock Screen)
  - Handles: Non-ASCII characters, emoji, multi-line text
- Restore clipboard after 450ms via `DispatchQueue.main.asyncAfter`
- No App Sandbox (hard requirement for CGEvent posting)
- Test matrix: Slack message input, Ghostty terminal, VS Code editor, browser text fields

### Phase 7: AppState wiring
- State machine: `needsModel → downloadingModel → loading → ready ↔ recording → transcribing → ready`
- Wire hotkey callbacks → audio start/stop → transcribe on background thread → insert text on main thread
- Show `ListeningOverlay` with subtle wave/ripple animation during recording
- Main window access from menu bar (⌘+Click or "Open VibeStoke" button)

### Phase 8: Onboarding + ModelManager
- **WelcomeView**: App intro, "Get Started" button
- **ModelDownloadView**: Download tar.bz2 via URLSession with progress delegate
  - Extract with `/usr/bin/tar -xjf`
  - Store in `~/Library/Application Support/VibeStoke/models/`
  - Validate required files: encoder.int8.onnx, decoder.int8.onnx, joiner.int8.onnx, tokens.txt
  - Progress bar + status text + "Done" button
- Two-page navigation: Welcome → Download → Main app

### Phase 9: UI Polish & Main Window
- **Design System**: Minimal, clean, monochromatic aesthetic
  - Color palette: Grayscale only (black, white, grays), no accent colors
  - Typography: Google Sans for UI text, Fragment Mono for code/stats/monospace elements (fallback to installed system fonts if unavailable)
  - Spacing: Generous padding, clean dividers, subtle shadows
  - Animations: Subtle, quick (0.2-0.3s), ease-out curves
- `ListeningOverlay`: Subtle wave/ripple animation when fn/globe held
  - Monochromatic visual feedback (grayscale ripples)
  - Appears near cursor or screen corner (configurable)
  - Fade in/out transitions
- **MainWindowView**: Stats homepage
  - Total dictation time, words transcribed, sessions count
  - Recent activity timeline
  - Quick settings access
  - Fragment Mono for metrics/numbers, Google Sans for labels
- **SidebarView**: Navigation drawer
  - Clean iconography (SF Symbols, monochromatic)
  - Stats (default view)
  - Settings: Hotkey customization, audio device selection, animation toggle
  - About: Version, credits, model info
- Permission checks: `AXIsProcessTrustedWithOptions`, mic access
- Menu bar icon: `mic` (ready) / `mic.fill` (recording) — monochromatic template images
- Error states surfaced in menu bar popover with subtle styling

## Key Technical Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| sherpa-onnx integration | C API direct link | Lower latency than WebSocket server (OpenWhispr pattern) |
| Audio format | 16kHz mono Float32 | sherpa-onnx requirement |
| Hotkey | fn/globe key (hold) | Native macOS dictation convention, single-hand |
| Design Language | Minimal, clean, monochromatic | Visual clarity, no distractions |
| Typography | Google Sans + Fragment Mono (with system fallback) | Preferred visual style with graceful local fallback |
| Text insertion | Clipboard + CGEvent Cmd+V | Only reliable cross-app method on macOS |
| Sandbox | Disabled | CGEvent posting blocked in sandbox |
| Model storage | ~/Library/Application Support/ | Standard macOS pattern |
| Threading | Transcription on background Task | Keep UI responsive during inference |

## Model Details
- **Model**: `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
- **Size**: 680MB (INT8 quantized)
- **Files**: encoder.int8.onnx (622MB), decoder.int8.onnx (12MB), joiner.int8.onnx (6MB), tokens.txt (92KB)
- **Expected perf on M1**: ~8-10x realtime on CPU (5s audio → ~0.5-0.6s inference)

## Verification
1. Build & run → menu bar icon appears, no Dock icon
2. First launch → onboarding shows, model downloads with progress
3. After download → status shows "Ready"
4. Hold fn/globe key → icon changes to mic.fill, status shows "Recording"
5. Release → brief "Transcribing..." → text appears at cursor in TextEdit/browser/VS Code
6. Clipboard contents preserved after paste
7. Test with Indian English accent phrases
