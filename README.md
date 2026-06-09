# ReedKit

A small iOS Swift package that adds **tap‑and‑hold to speak** dictation to any
app: hold a button, speak, release — clean text appears. The pipeline:

**hold mic → `AVAudioEngine` (16 kHz mono WAV) → Groq Whisper → optional Claude cleanup → text.**

No third‑party package dependencies — it calls Groq and Anthropic directly over HTTPS.

## Install (Swift Package Manager)

```
https://github.com/MiDa-Inc/reed-kit
```
Xcode → File → Add Package Dependencies → paste the URL. Or in `Package.swift`:

```swift
.package(url: "https://github.com/MiDa-Inc/reed-kit", from: "0.1.0")
```

## Use it

**Drop-in button:**
```swift
import SwiftUI
import ReedKit

struct DictateView: View {
    @StateObject private var engine = DictationEngine(
        config: .init(groqKey: "gsk_…", anthropicKey: "sk-…")   // anthropic optional
    )
    @State private var text = ""

    var body: some View {
        VStack {
            Text(text)
            HoldToTalkButton(engine: engine)
        }
        .onAppear { engine.onResult = { text = $0 } }
    }
}
```

**Or drive it yourself** (e.g. your own button / a tap-to-toggle flow):
```swift
let engine = DictationEngine(config: .init(groqKey: "gsk_…", autoStopOnSilence: true))
engine.onResult = { print($0) }
await engine.start()   // …user speaks…
await engine.stop()    // transcribe; with autoStopOnSilence it also stops itself
```

## Required host-app setup

Add a **microphone usage string** to your app's Info.plist (the package can't
declare it for you):

```
NSMicrophoneUsageDescription = "Used to transcribe your voice into text."
```

API keys are supplied by **your** app via `DictationConfig` — ReedKit stores
nothing. (Keep them out of source; load from your own secure store.)

## Public API

- `DictationConfig` — keys, models, `enableCleanup`, `autoStopOnSilence`, `silenceFloorDB`.
- `DictationEngine` (`@MainActor`, `ObservableObject`) — `state`, `transcript`, `onResult`, `start()`, `stop()`.
- `DictationState` — `idle · recording · transcribing · done · error`.
- `HoldToTalkButton` — the bundled hold-to-talk mic (themeable `tint`).
- `WaveBars`, `PulseRing`, `ReedTheme` — building blocks for a custom UI.

## Behavior notes

- **Silence is skipped.** A take whose average level is below `silenceFloorDB`
  (default −45 dBFS) returns nothing — avoids Whisper hallucinating "Thank you."
- **Cleanup is best-effort.** If the Anthropic call fails (or no key), you still
  get the raw Groq transcript.

## Requirements
iOS 17+. Cleanup uses Claude Haiku; transcription uses Groq Whisper.
