import SwiftUI

/// CutSense 1.1.0 mono design system: black, white and grays only; one red accent (`offer`) reserved for the timed flash offer. Spec: docs/design-1.1.0.md §2–§3.
enum Mono {
    enum C {
        static let bg = Color.black
        static let raised = Color(white: 14 / 255)
        static let elevated = Color(white: 23 / 255)
        static let hairline = Color.white.opacity(0.10)
        static let strong = Color.white.opacity(0.22)
        static let text = Color.white
        static let text2 = Color(white: 163 / 255)
        static let text3 = Color(white: 128 / 255)
        static let disabled = Color(white: 77 / 255)
        static let waveCut = Color(white: 58 / 255)
        static let onWhite2 = Color(white: 107 / 255)
        static let pressedWhite = Color(white: 230 / 255)
        static let scrim = Color.black.opacity(0.9)
        /// Flash offer only, on bg only. Never on raised/white, never as a fill under white text.
        static let offer = Color(red: 1, green: 69 / 255, blue: 58 / 255)
        /// Decorative hairline only; never for text.
        static let offerDim = offer.opacity(0.35)
    }

    enum Style {
        case display, title, numeralXL, numeralL, numeralM, headline, body, label, overline, caption

        var size: CGFloat {
            switch self {
            case .display: 40
            case .title: 28
            case .numeralXL: 56
            case .numeralL: 34
            case .numeralM: 20
            case .headline: 17
            case .body: 15
            case .label: 13
            case .overline: 11
            case .caption: 12
            }
        }

        var weight: Font.Weight {
            switch self {
            case .display, .title, .numeralL, .headline: .semibold
            case .numeralXL, .numeralM, .label, .overline: .medium
            case .body, .caption: .regular
            }
        }

        var tracking: CGFloat {
            switch self {
            case .display: -1.2
            case .title: -0.6
            case .numeralXL: -1
            case .headline: -0.2
            case .overline: 0.8
            default: 0
            }
        }

        func font(size override: CGFloat? = nil, scale: CGFloat = 1) -> Font {
            let s = (override ?? size) * scale
            switch self {
            case .numeralXL, .numeralL:
                return .system(size: s, weight: weight).width(.expanded).monospacedDigit()
            case .numeralM, .overline:
                return .system(size: s, weight: weight, design: .monospaced)
            default:
                return .system(size: s, weight: weight)
            }
        }
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let nativeAd: CGFloat = 12
        static let card: CGFloat = 24
        static let sheet: CGFloat = 28
    }

    enum Motion {
        static var snappy: Animation { .spring(response: 0.28, dampingFraction: 0.86) }
        static var smooth: Animation { .spring(response: 0.45, dampingFraction: 0.9) }
        static var bouncy: Animation { .spring(response: 0.5, dampingFraction: 0.68) }
        static var fade: Animation { .easeOut(duration: 0.2) }
        /// `fade` under Reduce Motion.
        static func pick(_ animation: Animation, reduce: Bool) -> Animation { reduce ? fade : animation }
    }
}

// MARK: - Type

private struct MonoTextModifier: ViewModifier {
    let style: Mono.Style
    let size: CGFloat?
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        let styled = content
            .font(style.font(size: size, scale: scale))
            .tracking(style.tracking)
        if style == .display {
            styled.lineLimit(2).minimumScaleFactor(0.7)
        } else {
            styled
        }
    }
}

extension View {
    /// Applies a Mono type token, scaled with Dynamic Type. `size` overrides the token size (e.g. title 22).
    func monoText(_ style: Mono.Style, size: CGFloat? = nil) -> some View {
        modifier(MonoTextModifier(style: style, size: size))
    }

    /// Opaque raised sheet chrome.
    func monoSheet() -> some View {
        presentationBackground(Mono.C.raised)
            .presentationCornerRadius(Mono.Radius.sheet)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
    }

    /// Entrance: y 14→0 plus opacity on `smooth`, delayed 0.05 s per index; opacity only under Reduce Motion.
    func monoEntrance(_ index: Int) -> some View {
        modifier(MonoEntrance(index: index))
    }
}

private struct MonoEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion).delay(0.05 * Double(index))) {
                    shown = true
                }
            }
    }
}

// MARK: - Buttons

private struct MonoOutlinedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by `MonoPrimaryButtonStyle` so `MonoActionLabel` can invert its chip.
    var monoOutlined: Bool {
        get { self[MonoOutlinedKey.self] }
        set { self[MonoOutlinedKey.self] = newValue }
    }
}

struct MonoPrimaryButtonStyle: ButtonStyle {
    var outlined: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, outlined: outlined)
    }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        let outlined: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .environment(\.monoOutlined, outlined)
                .foregroundStyle(outlined ? Mono.C.text : Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    if outlined {
                        Capsule().strokeBorder(Mono.C.text, lineWidth: 1.5)
                    } else {
                        Capsule().fill(pressed ? Mono.C.pressedWhite : Mono.C.text)
                    }
                }
                .contentShape(Capsule())
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .opacity(outlined || isEnabled ? 1 : 0.4)
                .animation(Mono.Motion.pick(Mono.Motion.snappy, reduce: reduceMotion), value: pressed)
        }
    }
}

/// Title at the leading edge, 40 pt glyph chip on the trailing edge. Use inside `MonoPrimaryButtonStyle`.
struct MonoActionLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.monoOutlined) private var outlined

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .monoText(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 22)
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(outlined ? Color.black : Mono.C.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(outlined ? Mono.C.text : Color.black))
                .padding(.trailing, 8)
                .accessibilityHidden(true)
        }
    }
}

/// `height` 48 by default; 40 in the cut sheet, 36 for Skip; height 56 + `.frame(width: 56)` gives the Share circle.
struct MonoSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Mono.C.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(configuration.isPressed ? Mono.C.elevated : Mono.C.raised))
            .overlay(Capsule().strokeBorder(Mono.C.hairline, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Text-only action. Pass `color: Mono.C.text` for the white variant (New Video after save).
struct MonoTertiaryButtonStyle: ButtonStyle {
    var color: Color = Mono.C.text2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(color)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Controls

/// Capsule segmented control for cut intensity. Owns its `.selection` haptic.
struct MonoIntensityControl: View {
    @Binding var selection: QuickSilenceEngine.CutIntensity
    let language: AppLanguage
    /// Replaces the preset description when set (e.g. an over-cutting warning).
    let hint: String?
    /// Per-level result length shown under each title (review only).
    var sublabels: [QuickSilenceEngine.CutIntensity: String] = [:]

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(QuickSilenceEngine.CutIntensity.allCases) { intensity in
                    let selected = intensity == selection
                    Button {
                        withAnimation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion)) { selection = intensity }
                    } label: {
                        VStack(spacing: 0) {
                            Text(intensity.title(for: language))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selected ? Color.black : Mono.C.text2)
                            if let sublabel = sublabels[intensity] {
                                Text(sublabel)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(selected ? Color.black.opacity(0.6) : Mono.C.text3)
                            }
                        }
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if selected {
                                    Capsule().fill(Mono.C.text).matchedGeometryEffect(id: "thumb", in: thumb)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // Label stays the bare title: UI tests tap segments by it.
                    .accessibilityLabel(intensity.title(for: language))
                    .accessibilityValue(sublabels[intensity] ?? "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .frame(height: 44)
            .background(Capsule().fill(Mono.C.raised))
            .overlay(Capsule().strokeBorder(Mono.C.hairline, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(appText(language, "Kesim sertliği", "Cut intensity"))

            ZStack {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if hint != nil {
                        Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    }
                    Text(hint ?? selection.detail(for: language))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .monoText(.caption)
                .foregroundStyle(hint == nil ? Mono.C.text2 : Mono.C.text)
                .id(hint ?? selection.rawValue)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: 16)
            .animation(Mono.Motion.fade, value: hint ?? selection.rawValue)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Label leading, 51×31 switch trailing; the whole row toggles. Exposed to accessibility as a system Switch.
struct MonoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToggleBody(configuration: configuration)
    }

    private struct ToggleBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let isOn = configuration.isOn
            Button {
                withAnimation(Mono.Motion.pick(Mono.Motion.snappy, reduce: reduceMotion)) { configuration.$isOn.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 12) {
                    configuration.label
                    Spacer(minLength: 0)
                    ZStack(alignment: isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(isOn ? Mono.C.text : Color.clear)
                            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Mono.C.strong, lineWidth: 1.5))
                        Circle()
                            .fill(isOn ? Color.black : Mono.C.text2)
                            .frame(width: 27, height: 27)
                            .padding(2)
                    }
                    .frame(width: 51, height: 31)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
        }
    }
}

// MARK: - Indicators

struct MonoBadge: View {
    let text: String
    var filled: Bool = false
    var tint: Color = Mono.C.text

    init(_ text: String, filled: Bool = false, tint: Color = Mono.C.text) {
        self.text = text
        self.filled = filled
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .monoText(.overline)
            .lineLimit(1)
            .foregroundStyle(filled ? Color.black : Mono.C.text)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background {
                if filled {
                    Capsule().fill(tint)
                } else {
                    Capsule().strokeBorder(Mono.C.hairline, lineWidth: 1)
                }
            }
    }
}

/// One red hairline lap around a capsule border: 2.4 s every 6 s. Nothing under Reduce Motion.
struct OfferSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var head: CGFloat = 0

    var body: some View {
        if !reduceMotion {
            Segment(head: head)
                .stroke(Mono.C.offer, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    while !Task.isCancelled {
                        var reset = Transaction(); reset.disablesAnimations = true
                        withTransaction(reset) { head = 0 }
                        try? await Task.sleep(for: .milliseconds(50))
                        withAnimation(.easeInOut(duration: 2.4)) { head = 1 }
                        try? await Task.sleep(for: .seconds(6))
                    }
                }
        }
    }

    private struct Segment: Shape {
        var head: CGFloat
        var animatableData: CGFloat { get { head } set { head = newValue } }
        func path(in rect: CGRect) -> Path {
            Capsule().path(in: rect.insetBy(dx: 0.5, dy: 0.5))
                .trimmedPath(from: max(0, head * 1.15 - 0.15), to: min(1, head * 1.15))
        }
    }
}

struct MonoNotice: View {
    let text: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .monoText(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 12, weight: .bold)).underline()
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Mono.C.text)
        .padding(.horizontal, 10)
        // The 44 pt action button already supplies the vertical room.
        .padding(.vertical, actionTitle != nil && action != nil ? 0 : 10)
        .background(RoundedRectangle(cornerRadius: Mono.Radius.chip, style: .continuous).fill(Mono.C.raised))
    }
}

/// 2 pt ring; overlay the percent label yourself.
struct MonoProgressRing: View {
    let progress: Double
    var size: CGFloat = 132
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Mono.C.hairline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Mono.C.text, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Animates once on appear (check draw, scale, one ring pulse); fade only under Reduce Motion.
struct MonoCheckSeal: View {
    var size: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    @State private var pulse: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Mono.C.text, lineWidth: 1.5)
                .scaleEffect(1 + 1.2 * pulse)
                .opacity(0.6 * (1 - pulse))
            Circle().fill(Color.black.opacity(0.6))
            Circle().strokeBorder(Mono.C.text, lineWidth: 1.5)
            CheckShape()
                .trim(from: 0, to: drawn)
                .stroke(Mono.C.text, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .opacity(opacity)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                drawn = 1
                scale = 1
                pulse = 1
                withAnimation(Mono.Motion.fade) { opacity = 1 }
            } else {
                opacity = 1
                withAnimation(.easeOut(duration: 0.35)) { drawn = 1 }
                withAnimation(Mono.Motion.bouncy) { scale = 1 }
                withAnimation(.easeOut(duration: 0.7)) { pulse = 1 }
            }
        }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.1))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return p
        }
    }
}

// MARK: - Signal

/// Brand signal: hero loop (`.demo`), processing scan (`.scanning`), failed (`.flat`).
/// Keep one instance across phases so `progress`/`amplitude` animate between modes.
struct SignalField: View, Animatable {
    enum Mode: Equatable {
        case demo
        case scanning(progress: Double)
        case flat
    }

    private enum Kind { case demo, scanning, flat }

    private let kind: Kind
    private var progress: Double
    private var amplitude: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    init(mode: Mode) {
        switch mode {
        case .demo: (kind, progress, amplitude) = (.demo, 0, 1)
        case .scanning(let p): (kind, progress, amplitude) = (.scanning, min(max(p, 0), 1), 1)
        case .flat: (kind, progress, amplitude) = (.flat, 0, 0)
        }
    }

    init(_ mode: Mode) { self.init(mode: mode) }

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, amplitude) }
        set { (progress, amplitude) = (newValue.first, newValue.second) }
    }

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { ctx, size in draw(&ctx, size: size, t: nil) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: kind == .flat && amplitude == 0)) { timeline in
                    Canvas { ctx, size in
                        draw(&ctx, size: size, t: timeline.date.timeIntervalSince(start))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static let slots = 48

    private static func isSilence(_ i: Int) -> Bool { (11...16).contains(i) || (30...34).contains(i) }

    private static func demoEnvelope(_ i: Int) -> Double {
        if isSilence(i) { return 0.05 }
        let x = Double(i)
        return 0.28 + 0.72 * abs(sin(x * 1.31) * 0.6 + sin(x * 0.47 + 1.3) * 0.4)
    }

    private static func scanEnvelope(_ i: Int) -> Double {
        let x = Double(i)
        return 0.2 + 0.8 * abs(sin(x * 0.9) * 0.5 + sin(x * 0.31) * 0.5)
    }

    private static func easeInOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// `t == nil` renders the static Reduce Motion frame.
    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double?) {
        let w = size.width, h = size.height
        let slot = w / CGFloat(Self.slots)
        let midY = h / 2

        func bar(x: CGFloat, width: CGFloat, height: CGFloat, opacity: Double) {
            guard width > 0.1, height > 0.1, opacity > 0 else { return }
            let rect = CGRect(x: x - width / 2, y: midY - height / 2, width: width, height: height)
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(width, height) / 2), with: .color(.white.opacity(opacity)))
        }
        func line(x: CGFloat, width: CGFloat, opacity: Double) {
            guard opacity > 0 else { return }
            ctx.fill(Path(CGRect(x: x - width / 2, y: 0, width: width, height: h)), with: .color(.white.opacity(opacity)))
        }

        // Flat baseline fades in as amplitude falls.
        if amplitude < 1 {
            let r = CGRect(x: 0, y: midY - 1.5, width: w, height: 3)
            ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(.white.opacity(0.35 * (1 - amplitude))))
        }

        switch kind {
        case .demo:
            // 6.4 s loop: sweep 0–2.0, playhead fade 2.0–2.4, collapse 2.4–3.2, hold, expand 5.4–6.4.
            let phase = t.map { $0.truncatingRemainder(dividingBy: 6.4) } ?? 4.0
            let c: Double
            switch phase {
            case ..<2.4: c = 0
            case ..<3.2: c = Self.easeInOut((phase - 2.4) / 0.8)
            case ..<5.4: c = 1
            default: c = 1 - Self.easeInOut(phase - 5.4)
            }
            let sweepX = phase < 2.0 ? w * CGFloat(phase / 2.0) : w + 1
            // Passed-state brightness eases back to unplayed while the row expands.
            let passedWeight = phase >= 5.4 ? c : 1

            let widths = (0..<Self.slots).map { Self.isSilence($0) ? slot * CGFloat(1 - c) : slot }
            var x = (w - widths.reduce(0, +)) / 2
            var joins: [CGFloat] = []
            for i in 0..<Self.slots {
                let silent = Self.isSilence(i)
                let center = x + widths[i] / 2
                let breathe = silent ? 1 : t.map { 0.85 + 0.15 * sin($0 * 2.4 + Double(i) * 0.55) } ?? 1
                let height = max(2, CGFloat(Self.demoEnvelope(i) * breathe) * h) * CGFloat(amplitude)
                let passed = CGFloat(i) * slot + slot / 2 <= sweepX
                let target = silent ? 0.22 : 1.0
                let opacity = passed ? 0.45 + (target - 0.45) * passedWeight : 0.45
                bar(x: center, width: widths[i] * 0.5, height: height, opacity: opacity)
                if silent && !Self.isSilence(i - 1) { joins.append(x) }
                x += widths[i]
            }
            if c > 0 { for j in joins { line(x: j, width: 1, opacity: 0.5 * c) } }
            if t != nil, phase < 2.4 {
                line(x: min(sweepX, w), width: 1.5, opacity: phase < 2.0 ? 1 : 1 - (phase - 2.0) / 0.4)
            }

        case .scanning, .flat:
            for i in 0..<Self.slots {
                let breathe = t.map { 0.85 + 0.15 * sin($0 * 4.8 + Double(i) * 0.55) } ?? 1
                let height = CGFloat(Self.scanEnvelope(i) * breathe) * h * CGFloat(amplitude)
                let lit = kind == .scanning && (Double(i) + 0.5) / Double(Self.slots) <= progress
                bar(x: CGFloat(i) * slot + slot / 2, width: slot * 0.5, height: height, opacity: lit ? 1 : (kind == .flat ? 0.35 : 0.2))
            }
            if kind == .scanning { line(x: w * CGFloat(progress), width: 1.5, opacity: 1) }
        }
    }
}

#if DEBUG
#Preview("Mono components") { MonoKitPreview() }

private struct MonoKitPreview: View {
    @State private var intensity = QuickSilenceEngine.CutIntensity.balanced
    @State private var cut = true

    var body: some View {
    let plan = QuickSilenceEngine.CutPlan(duration: 60, cuts: [
        .init(id: 0, range: 8...12, isRestored: false),
        .init(id: 1, range: 30...33, isRestored: true),
        .init(id: 2, range: 44...50, isRestored: false),
    ])
    let bars = MonoWave.bars(from: (0..<600).map { Float(abs(sin(Double($0) * 0.07))) })
    ScrollView {
        VStack(alignment: .leading, spacing: Mono.Space.l) {
            SignalField(mode: .demo).frame(height: 96)
            SignalField(mode: .scanning(progress: 0.4)).frame(height: 64)
            SignalField(mode: .flat).frame(height: 64)
            Text("CutSense").monoText(.overline).foregroundStyle(Mono.C.text3)
            Text("Cut Silence").monoText(.display)
            Text("37%").monoText(.numeralL)
            Text("0:42").monoText(.numeralM)
            WaveformTimeline(bars: bars, plan: plan, playhead: 20, compacted: false, onScrub: { _ in })
                .frame(height: 44)
            MonoIntensityControl(selection: $intensity, language: .en, hint: nil)
            MonoIntensityControl(selection: $intensity, language: .de, hint: "Most of this video would be removed.")
            Button {} label: { MonoActionLabel("Choose Video", systemImage: "plus") }
                .buttonStyle(MonoPrimaryButtonStyle())
            Button {} label: { MonoActionLabel("Saved to Photos", systemImage: "checkmark") }
                .buttonStyle(MonoPrimaryButtonStyle(outlined: true))
            HStack {
                Button("Review cuts") {}.buttonStyle(MonoSecondaryButtonStyle())
                Button {} label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(MonoSecondaryButtonStyle(height: 56)).frame(width: 56)
            }
            Button("New Video") {}.buttonStyle(MonoTertiaryButtonStyle())
            Toggle(isOn: $cut) { Text(cut ? "Cut" : "Keep").monoText(.label) }.toggleStyle(MonoToggleStyle())
            HStack { MonoBadge("PRO", filled: true); MonoBadge("Ad"); MonoBadge("\u{2212}50%", filled: true, tint: Mono.C.offer) }
            MonoNotice(text: "Photos access is off.", systemImage: "exclamationmark.triangle", actionTitle: "Open Settings", action: {})
            HStack(spacing: Mono.Space.l) {
                MonoProgressRing(progress: 0.6, size: 96).overlay(Text("60%").monoText(.numeralM))
                MonoCheckSeal()
            }
        }
        .foregroundStyle(Mono.C.text)
        .padding(Mono.Space.l)
    }
    .background(Mono.C.bg)
    .preferredColorScheme(.dark)
    }
}
#endif
