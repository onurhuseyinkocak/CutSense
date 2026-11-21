import SwiftUI

/// Pure onboarding scene maths (no SwiftUI state): every visual is a function of (page, τ).
/// Spec: docs/onboarding-offer-1.1.0.md §1. Design space is 342 × 300 pt; the view scales it uniformly.
enum OnboardingTimeline {
    static let width: CGFloat = 342
    static let height: CGFloat = 300
    static let slots = 48
    static let slot = width / CGFloat(slots)
    /// Silence ranges A, B, C (20 of 48 slots = 41.7%; 32 s → 19 s).
    static let silences: [ClosedRange<Int>] = [8...13, 20...26, 34...40]
    /// Static frame per page for Reduce Motion (matches the FREEZE screenshots).
    static let restTime: [Double] = [4, 2.5, 3]
    static let morphDuration: Double = 0.55

    struct BarPose {
        var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        /// 1 = white, 0 = `waveCut` gray.
        var white: Double
        var alpha: Double
    }

    struct Region {
        var rect: CGRect
        /// Opacity of the `raised` fill.
        var fill: Double
        /// White opacity of the 1 pt stroke (0.22 = `strong`, 0.10 = `hairline`).
        var stroke: Double
        var trim: Double
    }

    struct Line {
        var x: CGFloat, y: CGFloat, h: CGFloat, width: CGFloat, alpha: Double
    }

    enum Label: Equatable { case original, withoutSilence }

    struct Frame {
        var bars: [BarPose] = []
        // Canvas decor (cross-fades on page change)
        var regions: [Region] = []
        var lines: [Line] = []
        var phoneTrim: Double = 0
        var scan: Line?
        // SwiftUI overlay state
        var seconds = 0
        var label: Label = .original
        var badge = false
        var rowsShown = false
        var kept = false
        var tap: (scale: Double, opacity: Double)?
        var seal = false
        /// Haptic cues; true only during the first loop so a frozen or looping frame never re-fires.
        var collapseCue = false
        var keepCue = false
    }

    // MARK: Helpers

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func ease(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
    static func easeOut(_ x: Double) -> Double { let c = clamp(x); return 1 - (1 - c) * (1 - c) * (1 - c) }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    static func region(of i: Int) -> Int? { silences.firstIndex { $0.contains(i) } }

    static func envelope(_ i: Int) -> Double {
        switch region(of: i) {
        case 1: return 0.16
        case .some: return 0.05
        case nil:
            let x = Double(i)
            return 0.28 + 0.72 * abs(sin(x * 1.31) * 0.6 + sin(x * 0.47 + 1.3) * 0.4)
        }
    }

    /// Breathing uses unlooped time so bars never pop at a loop seam.
    static func breathe(_ i: Int, _ t: Double) -> Double { 0.85 + 0.15 * sin(t * 2.4 + Double(i) * 0.55) }

    static func lerp(_ a: [BarPose], _ b: [BarPose], _ t: Double) -> [BarPose] {
        guard a.count == b.count, t < 1 else { return b }
        return zip(a, b).map { p, q in
            BarPose(x: lerp(p.x, q.x, t), y: lerp(p.y, q.y, t), w: lerp(p.w, q.w, t), h: lerp(p.h, q.h, t),
                    white: lerp(p.white, q.white, t), alpha: lerp(p.alpha, q.alpha, t))
        }
    }

    /// Slot widths and left edges for collapse amount `c` (silence slots shrink to `slot * (1 − c)`, row centred).
    static func layout(c: Double) -> (widths: [CGFloat], lefts: [CGFloat]) {
        let widths = (0..<slots).map { region(of: $0) == nil ? slot : slot * CGFloat(1 - c) }
        var x = (width - widths.reduce(0, +)) / 2
        var lefts: [CGFloat] = []
        for w in widths { lefts.append(x); x += w }
        return (widths, lefts)
    }

    static func frame(page: Int, t: Double, grow: Bool) -> Frame {
        switch page {
        case 0: collapse(t, grow: grow)
        case 1: review(t)
        default: onDevice(t)
        }
    }

    // MARK: Page 1 — Collapse

    static func collapse(_ t: Double, grow: Bool) -> Frame {
        let midY: CGFloat = 150, maxH: CGFloat = 132, bandH = maxH + 12
        let first = t < 6.8
        let p = first ? t : 0.6 + (t - 0.6).truncatingRemainder(dividingBy: 6.2)
        let c: Double = switch p {
        case ..<2.5: 0
        case ..<3.4: ease((p - 2.5) / 0.9)
        case ..<6.0: 1
        default: 1 - ease((p - 6.0) / 0.8)
        }
        let playX: CGFloat = p < 0.6 ? -1 : (p < 2.2 ? width * CGFloat((p - 0.6) / 1.6) : width + 1)
        // Passed brightness eases back to unplayed while the row expands, so τ 6.8 == τ 0.6.
        let passedWeight = p >= 6.0 ? c : 1
        let (widths, lefts) = layout(c: c)

        var f = Frame()
        f.bars = (0..<slots).map { i in
            let silent = region(of: i) != nil
            let g = grow ? easeOut((t - 0.012 * Double(i)) / 0.35) : 1
            let h = max(2, CGFloat(envelope(i) * (silent ? 1 : breathe(i, t))) * maxH) * CGFloat(g)
            let passed = CGFloat(i) * slot + slot / 2 <= playX
            let target = silent ? 0.22 : 1.0
            let alpha = passed ? 0.45 + (target - 0.45) * passedWeight : 0.45
            return BarPose(x: lefts[i] + widths[i] / 2, y: midY, w: widths[i] * 0.5, h: h, white: 1, alpha: alpha)
        }
        let frameAlpha = (2.2..<6.0).contains(p) ? 0.22 * (1 - c) : 0
        for r in silences {
            let x0 = lefts[r.lowerBound]
            let w = lefts[r.upperBound] + widths[r.upperBound] - x0
            f.regions.append(Region(rect: CGRect(x: x0, y: midY - bandH / 2, width: w, height: bandH),
                                    fill: 0, stroke: frameAlpha, trim: clamp((p - 2.2) / 0.3)))
            if c > 0 { f.lines.append(Line(x: x0 + w / 2, y: midY, h: bandH, width: 1, alpha: 0.5 * c)) }
        }
        if (0.6..<2.5).contains(p) {
            f.lines.append(Line(x: min(playX, width), y: midY, h: bandH + 12, width: 1.5,
                                alpha: p < 2.2 ? 1 : 1 - (p - 2.2) / 0.3))
        }
        f.seconds = Int((32 - 13 * c).rounded())
        f.label = c >= 0.5 ? .withoutSilence : .original
        f.badge = c >= 0.5
        f.collapseCue = first && p >= 2.5
        return f
    }

    // MARK: Page 2 — Review

    static let rowTop: CGFloat = 100
    static let rowHeight: CGFloat = 52

    static func review(_ t: Double) -> Frame {
        let midY: CGFloat = 44, maxH: CGFloat = 64
        let first = t < 5
        let p = first ? t : 1 + (t - 1).truncatingRemainder(dividingBy: 4)
        let k: Double = switch p {
        case 1.7..<3.2: ease((p - 1.7) / 0.45)
        case 3.2..<3.5: 1 - ease((p - 3.2) / 0.3)
        default: 0
        }
        var f = Frame()
        f.bars = (0..<slots).map { i in
            let x = CGFloat(i) * slot + slot / 2
            let env = envelope(i)
            switch region(of: i) {
            case nil:
                return BarPose(x: x, y: midY, w: slot * 0.5, h: max(2, CGFloat(env * breathe(i, t)) * maxH), white: 1, alpha: 1)
            case let r?:
                let cutH = max(3, CGFloat(env) * maxH * 0.35)
                let kk = r == 1 ? k : 0
                return BarPose(x: x, y: midY, w: slot * 0.5, h: lerp(cutH, CGFloat(env) * maxH, kk), white: kk, alpha: 1)
            }
        }
        f.regions = silences.enumerated().map { idx, r in
            let fade = idx == 1 ? 1 - k : 1
            return Region(rect: CGRect(x: CGFloat(r.lowerBound) * slot, y: midY - (maxH + 8) / 2,
                                       width: CGFloat(r.count) * slot, height: maxH + 8),
                          fill: fade, stroke: 0.10 * fade, trim: 1)
        }
        f.kept = (1.7..<3.2).contains(p)
        f.seconds = f.kept ? 24 : 19
        f.rowsShown = t >= 0.3
        let dt = p - 1.4
        if (0..<0.6).contains(dt) {
            f.tap = (0.6 + 0.4 * easeOut(dt / 0.25), 0.3 * (dt < 0.35 ? 1 : 1 - (dt - 0.35) / 0.25))
        }
        f.keepCue = first && f.kept
        return f
    }

    // MARK: Page 3 — On-device

    static let phone = CGRect(x: width / 2 - 70, y: height / 2 - 140, width: 140, height: 280)
    static let sealCenter = CGPoint(x: width / 2, y: 236)

    static func onDevice(_ t: Double) -> Frame {
        let midY: CGFloat = 150, maxH: CGFloat = 72
        let (widths, lefts) = layout(c: 1)
        let rowWidth = widths.reduce(0, +)
        let k = 108 / rowWidth, cx = width / 2
        var f = Frame()
        f.bars = (0..<slots).map { i in
            let silent = region(of: i) != nil
            let x = cx + (lefts[i] + widths[i] / 2 - cx) * k
            let h = max(2, CGFloat(envelope(i) * (silent ? 1 : breathe(i, t))) * maxH)
            return BarPose(x: x, y: midY, w: widths[i] * 0.5 * k, h: h, white: 1, alpha: 1)
        }
        f.phoneTrim = ease(t / 0.7)
        if t >= 0.9 {
            let s = (t - 0.9).truncatingRemainder(dividingBy: 4)
            if s < 1.2 {
                let top = phone.minY + 14, span = phone.height - 28
                f.scan = Line(x: phone.midX, y: top + span * CGFloat(s / 1.2), h: 1, width: phone.width - 16,
                              alpha: 0.6 * min(1, s / 0.1, (1.2 - s) / 0.1))
            }
        }
        f.seal = t >= 2.1
        return f
    }
}

/// Onboarding scene: Canvas bars + decor and SwiftUI overlays inside one `TimelineView`.
struct OnboardingStage: View {
    let page: Int
    let language: AppLanguage
    /// DEBUG `CUTSENSE_ONBOARDING_FREEZE`: renders every page at this τ, no clock, no morph.
    var fixedTime: Double? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int
    @State private var start = Date.now
    @State private var grow: Bool
    @State private var morph: Morph?
    @State private var pausedAt: Date?

    private struct Morph {
        let bars: [OnboardingTimeline.BarPose]
        let decor: OnboardingTimeline.Frame
        let at: Date
    }

    init(page: Int, language: AppLanguage, fixedTime: Double? = nil) {
        self.page = page
        self.language = language
        self.fixedTime = fixedTime
        _shown = State(initialValue: page)
        _grow = State(initialValue: page == 0)
    }

    private var fixed: Double? { fixedTime ?? (reduceMotion ? OnboardingTimeline.restTime[shown] : nil) }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / OnboardingTimeline.width, geo.size.height / OnboardingTimeline.height)
            ZStack {
                if let fixed {
                    scene(OnboardingTimeline.frame(page: shown, t: fixed, grow: false), at: nil)
                        .id(shown)
                        .transition(.opacity.animation(Mono.Motion.fade))
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) { tl in
                        scene(OnboardingTimeline.frame(page: shown, t: tl.date.timeIntervalSince(start), grow: grow), at: tl.date)
                    }
                }
            }
            .frame(width: OnboardingTimeline.width, height: OnboardingTimeline.height)
            .scaleEffect(s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
        // τ is wall-clock based; shift the clock by any inactive gap so a paused scene resumes where it stopped.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase != .active {
                if pausedAt == nil { pausedAt = .now }
            } else if let pausedAt {
                let gap = Date.now.timeIntervalSince(pausedAt)
                start = start.addingTimeInterval(gap)
                if let m = morph { morph = Morph(bars: m.bars, decor: m.decor, at: m.at.addingTimeInterval(gap)) }
                self.pausedAt = nil
            }
        }
        .onChange(of: page) { _, new in
            let now = Date.now
            if fixed == nil {
                let current = OnboardingTimeline.frame(page: shown, t: now.timeIntervalSince(start), grow: grow)
                morph = Morph(bars: OnboardingTimeline.lerp(morph?.bars ?? current.bars, current.bars, progress(at: now)),
                              decor: current, at: now)
            } else {
                morph = nil
            }
            shown = new
            grow = false
            // Re-entering Collapse starts at the loop point, past the grow-in.
            start = new == 0 ? now.addingTimeInterval(-0.6) : now
        }
    }

    private func progress(at date: Date?) -> Double {
        guard let date, let morph else { return 1 }
        return OnboardingTimeline.ease(date.timeIntervalSince(morph.at) / OnboardingTimeline.morphDuration)
    }

    private func scene(_ f: OnboardingTimeline.Frame, at date: Date?) -> some View {
        let m = progress(at: date)
        let bars = m < 1 ? OnboardingTimeline.lerp(morph?.bars ?? f.bars, f.bars, m) : f.bars
        let old = m < 1 ? morph?.decor : nil
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                if let old { Self.drawBack(&ctx, old, alpha: 1 - m) }
                Self.drawBack(&ctx, f, alpha: m)
                Self.drawBars(&ctx, bars)
                if let old { Self.drawFront(&ctx, old, alpha: 1 - m) }
                Self.drawFront(&ctx, f, alpha: m)
            }
            overlay(f)
                .id(shown)
                .transition(.opacity.animation(.easeInOut(duration: OnboardingTimeline.morphDuration)))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: f.collapseCue) { _, new in new }
        .sensoryFeedback(.selection, trigger: f.keepCue) { _, new in new }
    }

    // MARK: Canvas

    private static let cutGray = 58.0 / 255

    private static func drawBars(_ ctx: inout GraphicsContext, _ bars: [OnboardingTimeline.BarPose]) {
        for b in bars where b.w > 0.1 && b.h > 0.1 && b.alpha > 0 {
            let rect = CGRect(x: b.x - b.w / 2, y: b.y - b.h / 2, width: b.w, height: b.h)
            let tone = OnboardingTimeline.lerp(cutGray, 1, b.white)
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(b.w, b.h) / 2), with: .color(Color(white: tone).opacity(b.alpha)))
        }
    }

    private static func drawBack(_ ctx: inout GraphicsContext, _ f: OnboardingTimeline.Frame, alpha: Double) {
        guard alpha > 0 else { return }
        for r in f.regions where r.rect.width > 0.5 {
            let path = Path(roundedRect: r.rect, cornerRadius: 6, style: .continuous)
            if r.fill > 0 { ctx.fill(path, with: .color(Mono.C.raised.opacity(r.fill * alpha))) }
            if r.stroke > 0, r.trim > 0 {
                ctx.stroke(path.trimmedPath(from: 0, to: r.trim), with: .color(.white.opacity(r.stroke * alpha)), lineWidth: 1)
            }
        }
    }

    private static func drawFront(_ ctx: inout GraphicsContext, _ f: OnboardingTimeline.Frame, alpha: Double) {
        guard alpha > 0 else { return }
        for l in f.lines + [f.scan].compactMap({ $0 }) where l.alpha > 0 {
            let rect = CGRect(x: l.x - l.width / 2, y: l.y - l.h / 2, width: l.width, height: l.h)
            ctx.fill(Path(rect), with: .color(.white.opacity(l.alpha * alpha)))
        }
        if f.phoneTrim > 0 {
            let phone = Path(roundedRect: OnboardingTimeline.phone, cornerRadius: 30, style: .continuous)
            ctx.stroke(phone.trimmedPath(from: 0, to: f.phoneTrim), with: .color(.white.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private func overlay(_ f: OnboardingTimeline.Frame) -> some View {
        switch shown {
        case 0: collapseOverlay(f)
        case 1: reviewOverlay(f)
        default: onDeviceOverlay(f)
        }
    }

    private func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private var smooth: Animation { Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion) }

    private func counter(_ seconds: Int) -> some View {
        Text(clock(seconds))
            .monoText(.numeralM)
            .contentTransition(.numericText(value: Double(seconds)))
            .animation(smooth, value: seconds)
    }

    private func collapseOverlay(_ f: OnboardingTimeline.Frame) -> some View {
        let label = f.label == .original
            ? appText(language, "Orijinal", "Original")
            : appText(language, "Sessizlik olmadan", "Without silence")
        return HStack(spacing: Mono.Space.xs) {
            counter(f.seconds)
            if f.badge {
                MonoBadge("−41%", filled: true)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer(minLength: Mono.Space.xs)
            Text(label)
                .monoText(.overline)
                .foregroundStyle(Mono.C.text3)
                .lineLimit(1)
                .id(f.label)
                .transition(.blurReplace)
        }
        .animation(Mono.Motion.pick(Mono.Motion.bouncy, reduce: reduceMotion), value: f.badge)
        .animation(smooth, value: f.label)
        .frame(height: 28)
        .padding(.top, 14)
        .frame(width: OnboardingTimeline.width, height: OnboardingTimeline.height, alignment: .top)
        .foregroundStyle(Mono.C.text)
    }

    private func reviewOverlay(_ f: OnboardingTimeline.Frame) -> some View {
        let ranges = ["0:05 – 0:09", "0:13 – 0:18", "0:23 – 0:27"]
        return ZStack(alignment: .topLeading) {
            if f.rowsShown {
                VStack(spacing: 0) {
                    ForEach(ranges.indices, id: \.self) { i in
                        reviewRow(index: i, range: ranges[i], kept: i == 1 && f.kept)
                            .monoEntrance(i)
                    }
                    HStack {
                        Text(appText(language, "Yeni süre", "New length"))
                            .monoText(.label)
                            .foregroundStyle(Mono.C.text2)
                        Spacer()
                        counter(f.seconds)
                    }
                    .frame(height: 24)
                    .monoEntrance(3)
                }
                .padding(.top, OnboardingTimeline.rowTop)
            }
            if let tap = f.tap {
                Circle()
                    .fill(Color.white.opacity(tap.opacity))
                    .frame(width: 28, height: 28)
                    .scaleEffect(tap.scale)
                    .position(x: OnboardingTimeline.width - 25.5,
                              y: OnboardingTimeline.rowTop + OnboardingTimeline.rowHeight * 1.5)
            }
        }
        .frame(width: OnboardingTimeline.width, height: OnboardingTimeline.height, alignment: .topLeading)
        .foregroundStyle(Mono.C.text)
    }

    private func reviewRow(index: Int, range: String, kept: Bool) -> some View {
        HStack(spacing: Mono.Space.s) {
            Text(String(format: "%02d", index + 1))
                .monoText(.overline)
                .foregroundStyle(Mono.C.text3)
                .frame(width: 28, alignment: .leading)
            Text(range)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(kept ? Mono.C.text3 : Mono.C.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: .constant(!kept)) {
                Text(kept ? appText(language, "Kalsın", "Keep") : appText(language, "Kes", "Cut"))
                    .monoText(.label)
                    .foregroundStyle(kept ? Mono.C.text2 : Mono.C.text)
            }
            .toggleStyle(MonoToggleStyle())
            .fixedSize()
            .allowsHitTesting(false)
        }
        .frame(height: OnboardingTimeline.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Mono.C.hairline).frame(height: 1) }
        // `.constant` bindings bypass the style's own animation; slide the knob here.
        .animation(Mono.Motion.pick(Mono.Motion.snappy, reduce: reduceMotion), value: kept)
    }

    private func onDeviceOverlay(_ f: OnboardingTimeline.Frame) -> some View {
        ZStack {
            if f.seal {
                MonoCheckSeal(size: 44)
                    .position(OnboardingTimeline.sealCenter)
            }
        }
        .frame(width: OnboardingTimeline.width, height: OnboardingTimeline.height)
    }
}
