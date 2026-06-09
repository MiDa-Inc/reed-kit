import SwiftUI

/// Drop-in **tap-and-hold to speak** button. Press and hold to record, release to
/// transcribe; the result arrives via the engine's `onResult` (and `engine.transcript`).
///
/// ```swift
/// HoldToTalkButton(engine: engine)
/// ```
public struct HoldToTalkButton: View {
    @ObservedObject private var engine: DictationEngine
    private let tint: Color
    private let micBackground: Color

    @State private var pressing = false

    public init(engine: DictationEngine,
                tint: Color = ReedTheme.charcoal,
                micBackground: Color = ReedTheme.micBG) {
        self.engine = engine
        self.tint = tint
        self.micBackground = micBackground
    }

    public var body: some View {
        ZStack {
            if engine.state == .recording { PulseRing(color: ReedTheme.ring) }
            Circle()
                .fill(micBackground)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 6)
            content
        }
        .frame(width: 132, height: 132)
        .contentShape(Circle())
        .gesture(gesture)
        .accessibilityLabel("Hold to talk")
    }

    @ViewBuilder private var content: some View {
        if engine.state == .recording {
            WaveBars(color: tint, heights: [14, 26, 34, 22, 12])
        } else if engine.state == .transcribing {
            ProgressView().tint(tint)
        } else {
            Image(systemName: "mic.fill").font(.system(size: 34)).foregroundStyle(tint)
        }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressing else { return }
                pressing = true
                Task { await engine.start() }
            }
            .onEnded { _ in
                pressing = false
                Task { await engine.stop() }
            }
    }
}
