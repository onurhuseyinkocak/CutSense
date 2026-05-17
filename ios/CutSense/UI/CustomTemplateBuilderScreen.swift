import SwiftUI

struct CustomTemplateBuilderScreen: View {
    let existing: TemplateConfig?
    let onSave: (TemplateConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var intensity: TemplateIntensity
    @State private var hookStyle: CaptionStyle
    @State private var emphasisStyle: CaptionStyle
    @State private var defaultStyle: CaptionStyle

    // Color grade
    @State private var saturation: Float
    @State private var brightness: Float
    @State private var contrast: Float
    @State private var warmth: Float
    @State private var vignetteIntensity: Float

    // Audio
    @State private var bgMusicVolume: Float
    @State private var sfxVolume: Float
    @State private var voiceBoostDB: Float

    // Timing
    @State private var minCutDuration: Double
    @State private var maxSilenceDuration: Double

    // Theme
    @State private var selectedThemeIndex: Int

    private static let themeOptions: [(String, TemplateConfig.CaptionTheme)] = [
        ("Gold", .premiumGold),
        ("Neon", .neonViral),
        ("Clean", .monoClean),
        ("Cinematic", .warmCinematic),
        ("Podcast", .podcastQuote),
    ]

    private static let themeIds = ["premium_founder", "viral_caption", "clean_expert", "cinematic_storyteller", "podcast_highlights"]

    init(existing: TemplateConfig? = nil, onSave: @escaping (TemplateConfig) -> Void) {
        self.existing = existing
        self.onSave = onSave
        let t = existing
        _name = State(initialValue: t?.name ?? "My Template")
        _intensity = State(initialValue: t?.intensity ?? .medium)
        _hookStyle = State(initialValue: t?.hookStyle ?? .hookImpact)
        _emphasisStyle = State(initialValue: t?.emphasisStyle ?? .focusStatement)
        _defaultStyle = State(initialValue: t?.defaultStyle ?? .premiumLowerThird)

        let g = t?.colorGrade ?? .none
        _saturation = State(initialValue: g.saturation)
        _brightness = State(initialValue: g.brightness)
        _contrast = State(initialValue: g.contrast)
        _warmth = State(initialValue: g.warmth)
        _vignetteIntensity = State(initialValue: g.vignetteIntensity)

        _bgMusicVolume = State(initialValue: t?.backgroundMusicVolume ?? 0.08)
        _sfxVolume = State(initialValue: t?.sfxVolume ?? 0.15)
        _voiceBoostDB = State(initialValue: t?.voiceBoostDB ?? 3.0)
        _minCutDuration = State(initialValue: t?.minCutDuration ?? 0.5)
        _maxSilenceDuration = State(initialValue: t?.maxSilenceDuration ?? 0.6)

        let themeIndex: Int
        if let id = t?.id, let idx = Self.themeIds.firstIndex(of: id) {
            themeIndex = idx
        } else {
            themeIndex = 0
        }
        _selectedThemeIndex = State(initialValue: themeIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    nameSection
                    intensitySection
                    captionStyleSection
                    colorGradeSection
                    audioSection
                    timingSection
                    themeSection
                    saveButton
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(existing == nil ? "New Template" : "Edit Template")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Name")
            TextField("Template name", text: $name)
                .textFieldStyle(.roundedBorder)
                .colorScheme(.dark)
        }
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Intensity")
            Picker("Intensity", selection: $intensity) {
                ForEach(TemplateIntensity.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var captionStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Caption Styles")
            stylePicker("Hook", selection: $hookStyle)
            stylePicker("Emphasis", selection: $emphasisStyle)
            stylePicker("Default", selection: $defaultStyle)
        }
    }

    private var colorGradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Color Grade")
            gradeSlider("Saturation", value: $saturation, range: 0.5...1.5)
            gradeSlider("Brightness", value: $brightness, range: -0.2...0.2)
            gradeSlider("Contrast", value: $contrast, range: 0.8...1.3)
            gradeSlider("Warmth", value: $warmth, range: -0.3...0.3)
            gradeSlider("Vignette", value: $vignetteIntensity, range: 0...0.8)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Audio Mix")
            gradeSlider("Music Volume", value: $bgMusicVolume, range: 0...0.3)
            gradeSlider("SFX Volume", value: $sfxVolume, range: 0...0.5)
            gradeSlider("Voice Boost (dB)", value: $voiceBoostDB, range: 0...6)
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Timing")
            doubleSlider("Min Cut Duration", value: $minCutDuration, range: 0.2...1.0)
            doubleSlider("Max Silence", value: $maxSilenceDuration, range: 0.2...1.0)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Caption Theme")
            HStack(spacing: 10) {
                ForEach(0..<Self.themeOptions.count, id: \.self) { index in
                    let option = Self.themeOptions[index]
                    Button {
                        selectedThemeIndex = index
                    } label: {
                        Text(option.0)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedThemeIndex == index ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                            .foregroundStyle(selectedThemeIndex == index ? .white : .gray)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedThemeIndex == index ? Color.white : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            let template = buildTemplate()
            onSave(template)
            dismiss()
        } label: {
            Text("Save Template")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
    }

    private func stylePicker(_ label: String, selection: Binding<CaptionStyle>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(width: 70, alignment: .leading)
            Picker(label, selection: selection) {
                ForEach(CaptionStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
    }

    private func gradeSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Slider(value: value, in: range)
                .tint(.white)
        }
    }

    private func doubleSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text(String(format: "%.2fs", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Slider(value: value, in: range)
                .tint(.white)
        }
    }

    private func buildTemplate() -> TemplateConfig {
        let id = existing?.id ?? "custom_\(UUID().uuidString.prefix(8))"
        let themeId = Self.themeIds[selectedThemeIndex]

        return TemplateConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            description: "Custom template",
            intensity: intensity,
            hookStyle: hookStyle,
            emphasisStyle: emphasisStyle,
            keywordStyle: emphasisStyle,
            conclusionStyle: defaultStyle,
            defaultStyle: defaultStyle,
            backgroundMusicVolume: bgMusicVolume,
            sfxVolume: sfxVolume,
            voiceBoostDB: voiceBoostDB,
            minCutDuration: minCutDuration,
            maxSilenceDuration: maxSilenceDuration,
            colorGrade: TemplateConfig.ColorGrade(
                saturation: saturation,
                brightness: brightness,
                contrast: contrast,
                warmth: warmth,
                vignetteIntensity: vignetteIntensity
            ),
            themeId: themeId
        )
    }
}
