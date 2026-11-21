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

    /// A slot is cut if an active cut covers >= 40% of its window or contains a cut's midpoint.
    nonisolated static func cutMask(count: Int, plan: QuickSilenceEngine.CutPlan) -> [Bool] {
        guard count > 0, plan.duration > 0 else { return Array(repeating: false, count: max(count, 0)) }
        let active = plan.cuts.filter { !$0.isRestored }.map(\.range)
        let window = plan.duration / Double(count)
        return (0..<count).map { i in
            let lo = Double(i) * window, hi = lo + window
            return active.contains { cut in
                let overlap = min(hi, cut.upperBound) - max(lo, cut.lowerBound)
                let mid = (cut.lowerBound + cut.upperBound) / 2
                return overlap >= window * 0.4 || (mid >= lo && mid < hi)
            }
        }
    }

    var body: some View {
        let mask = Self.cutMask(count: bars.count, plan: plan)
        GeometryReader { geo in
            let h = geo.size.height
            let slot = bars.isEmpty ? 0 : geo.size.width / CGFloat(bars.count)
            HStack(spacing: 0) {
                ForEach(bars.indices, id: \.self) { i in
                    let cut = mask[i]
                    let full = CGFloat(bars[i]) * h
                    let height = cut ? max(3, full * 0.35) : full
                    Capsule()
                        .fill(cut ? Mono.C.waveCut : Mono.C.text)
                        .frame(width: compacted && cut ? 0 : slot * 0.6, height: grown ? height : 0)
                        .frame(width: compacted && cut ? 0 : slot, height: h)
                        .animation(
                            reduceMotion ? Mono.Motion.fade : Mono.Motion.smooth.delay(Double(i) * 0.004),
                            value: [cut, compacted, grown]
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
