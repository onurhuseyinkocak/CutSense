import SwiftUI

enum MonoWave {
    /// Normalised bar heights (0.06...1) from analysis RMS windows. Compute once per analysis.
    static func bars(from rms: [Float], count: Int = 84) -> [Float] {
        guard count > 0 else { return [] }
        let floor: Float = 0.06
        guard !rms.isEmpty else { return Array(repeating: floor, count: count) }
        let n = rms.count
        let buckets: [Float] = (0..<count).map { b in
            let lo = b * n / count
            let hi = max(lo + 1, (b + 1) * n / count)
            return rms[lo..<min(hi, n)].reduce(0) { max($0, $1.isFinite ? $1 : 0) }
        }
        let sorted = buckets.sorted()
        let p95 = max(sorted[Int(Float(count - 1) * 0.95)], 1e-4)
        return buckets.map { max(floor, pow(min(max($0 / p95, 0), 1), 0.6)) }
    }
}

/// Review waveform: one capsule per slot; kept = white full height, cut = short `waveCut`.
/// One accessibility element; the caller sets its label (the "Timeline" key).
struct WaveformTimeline: View {
    let bars: [Float]
    let plan: QuickSilenceEngine.CutPlan
    var playhead: Double? = nil
    var compacted: Bool = false
    var onScrub: ((Double) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    /// Share (0...1) of each slot's window removed by active cuts. Drives dimming and compaction,
    /// so a 0.4 s cut in a 7 s slot (10-min video) barely changes it, while a short video's slots go fully dim.
    nonisolated static func coverage(count: Int, plan: QuickSilenceEngine.CutPlan) -> [Double] {
        guard count > 0, plan.duration > 0 else { return Array(repeating: 0, count: max(count, 0)) }
        let active = plan.cuts.filter { !$0.isRestored }.map(\.range)
        let window = plan.duration / Double(count)
        return (0..<count).map { i in
            let lo = Double(i) * window, hi = lo + window
            let removed = active.reduce(0) { $0 + max(0, min(hi, $1.upperBound) - max(lo, $1.lowerBound)) }
            return min(removed / window, 1)
        }
    }

    var body: some View {
        let cover = Self.coverage(count: bars.count, plan: plan)
        GeometryReader { geo in
            let h = geo.size.height
            let slot = bars.isEmpty ? 0 : geo.size.width / CGFloat(bars.count)
            HStack(spacing: 0) {
                ForEach(bars.indices, id: \.self) { i in
                    let c = CGFloat(cover[i])
                    let full = CGFloat(bars[i]) * h
                    let height = max(3, full * (1 - 0.65 * c))
                    // Compacted: each slot keeps only its kept share, so the strip shrinks by the real cut ratio.
                    let width = compacted ? slot * (1 - c) : slot
                    // Colour blends by the removed share too: white fades toward `waveCut`.
                    Capsule()
                        .fill(Mono.C.waveCut)
                        .overlay(Capsule().fill(Mono.C.text).opacity(1 - c))
                        .frame(width: width * 0.6, height: grown ? height : 0)
                        .frame(width: width, height: h)
                        .animation(
                            reduceMotion ? Mono.Motion.fade : Mono.Motion.smooth.delay(Double(i) * 0.004),
                            value: [c, compacted ? 1 : 0, grown ? 1 : 0]
                        )
                }
            }
            .frame(width: geo.size.width, height: h)
            .overlay(alignment: .leading) {
                if let playhead, !compacted, plan.duration > 0 {
                    Rectangle()
                        .fill(Mono.C.text)
                        .frame(width: 1.5, height: h)
                        .offset(x: geo.size.width * min(max(playhead / plan.duration, 0), 1) - 0.75)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: geo.size.width), including: onScrub == nil ? .none : .all)
        }
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(plan.duration > 0 ? "\(Int(((playhead ?? 0) / plan.duration * 100).rounded()))%" : "")
        .accessibilityAdjustableAction { direction in
            guard let onScrub else { return }
            let now = playhead ?? 0
            switch direction {
            case .increment: onScrub(min(plan.duration, now + 5))
            case .decrement: onScrub(max(0, now - 5))
            @unknown default: break
            }
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            guard width > 0 else { return }
            onScrub?(min(max(value.location.x / width, 0), 1) * plan.duration)
        }
    }
}
