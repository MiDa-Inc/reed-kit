import SwiftUI

/// Row of capsule bars. `animate: true` gives a live listening waveform.
public struct WaveBars: View {
    public var color: Color
    public var heights: [CGFloat]
    public var barWidth: CGFloat
    public var spacing: CGFloat
    public var animate: Bool

    @State private var on = false

    public init(color: Color, heights: [CGFloat], barWidth: CGFloat = 6,
                spacing: CGFloat = 5, animate: Bool = true) {
        self.color = color
        self.heights = heights
        self.barWidth = barWidth
        self.spacing = spacing
        self.animate = animate
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: height)
                    .scaleEffect(y: animate ? (on ? 1 : 0.35) : 1, anchor: .center)
                    .animation(animate ? .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.08) : nil,
                               value: on)
            }
        }
        .onAppear { if animate { on = true } }
    }
}

/// Expanding, fading ring shown behind the mic while recording.
public struct PulseRing: View {
    public var color: Color
    public var size: CGFloat

    @State private var expanded = false

    public init(color: Color, size: CGFloat = 118) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(expanded ? 1.26 : 0.85)
            .opacity(expanded ? 0 : 0.5)
            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: expanded)
            .onAppear { expanded = true }
    }
}
