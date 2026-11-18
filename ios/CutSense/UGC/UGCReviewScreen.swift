import SwiftUI
import AVKit

/// Review screen for the Auto UGC Editor.
/// Shows take groups, edit summary, and allows per-take review and override.
struct UGCReviewScreen: View {
    @ObservedObject var project: UGCEditProject
    let onBack: () -> Void
    let onExport: () -> Void
    let onReanalyze: () -> Void

    @State private var selectedTab: ReviewTab = .summary
    @State private var expandedGroupID: UUID?
    @State private var isExporting = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }

    enum ReviewTab: String, CaseIterable {
        case summary
        case groups
        case timeline
        case settings

        func title(for language: AppLanguage) -> String {
            switch self {
            case .summary: return appText(language, "Özet", "Summary")
            case .groups: return appText(language, "Çekimler", "Takes")
            case .timeline: return appText(language, "Zaman Çizgisi", "Timeline")
            case .settings: return appText(language, "Ayarlar", "Settings")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            // Tab bar
            Picker("", selection: $selectedTab) {
                ForEach(ReviewTab.allCases, id: \.self) { tab in
                    Text(tab.title(for: language)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Content
            ScrollView(showsIndicators: false) {
                switch selectedTab {
                case .summary:
                    summaryContent
                case .groups:
                    groupsContent
                case .timeline:
                    timelineContent
                case .settings:
                    settingsContent
                }
            }

            // Bottom actions
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text(appText(language, "Auto UGC Düzenleme", "Auto UGC Edit"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(appText(language, "Tüm kararları gözden geçir ve onayla", "Review and approve all decisions"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary Tab

    private var summaryContent: some View {
        VStack(spacing: 16) {
            // Video player
            if let url = project.finalCompositionURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
            }

            // Stats grid
            statsGrid
                .padding(.horizontal, 20)

            // Privacy notice
            privacyNotice
                .padding(.horizontal, 20)

            // Warning for uncertain decisions
            if project.hasUncertainDecisions {
                uncertainWarning
                    .padding(.horizontal, 20)
            }

            // Multiple speakers warning if more than 2 distinct speakers detected
            if hasMultipleSpeakers {
                multipleSpeakersWarning
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(
                    value: project.originalDurationFormatted,
                    label: appText(language, "Orijinal", "Original"),
                    icon: "clock"
                )
                statCard(
                    value: project.editedDurationFormatted,
                    label: appText(language, "Düzenlenmiş", "Edited"),
                    icon: "scissors"
                )
                statCard(
                    value: "-\(project.timeSavedFormatted)",
                    label: appText(language, "Kesildi", "Removed"),
                    icon: "arrow.down.right"
                )
            }

            HStack(spacing: 12) {
                statCardSmall(
                    value: "\(project.silenceSegmentCount)",
                    label: appText(language, "Sessizlik", "Silences"),
                    color: .blue
                )
                statCardSmall(
                    value: "\(project.takeGroupCount)",
                    label: appText(language, "Grup", "Groups"),
                    color: .green
                )
                statCardSmall(
                    value: "\(project.failedTakeCount)",
                    label: appText(language, "Hatalı", "Failed"),
                    color: .orange
                )
                statCardSmall(
                    value: "\(project.uncertainDecisionCount)",
                    label: appText(language, "Belirsiz", "Uncertain"),
                    color: .yellow
                )
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statCardSmall(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var privacyNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
            Text(appText(language, "Videonuz ve transkriptiniz bu cihazda kalır. Hiçbir veri yüklenmez.",
                         "Your video and transcript stay on this device. No data is uploaded."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var hasMultipleSpeakers: Bool {
        // Simple heuristic: if there are many groups with different canonical texts,
        // it may be a multi-speaker video. For v1, show warning if >8 groups.
        return project.takeGroups.count > 8
    }

    private var multipleSpeakersWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            Text(appText(language,
                         "Bu video birden fazla konuşmacı içeriyor olabilir. En iyi çekim seçimi tek konuşmacılı videolar için optimize edilmiştir.",
                         "This video may contain multiple speakers. Best-take selection is optimized for single-speaker footage."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var uncertainWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
            Text(appText(language, "\(project.uncertainDecisionCount) karar belirsiz. Lütfen 'Çekimler' sekmesinden kontrol edin.",
                         "\(project.uncertainDecisionCount) decision(s) need review. Please check the 'Takes' tab."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Groups Tab

    private var groupsContent: some View {
        VStack(spacing: 14) {
#error("RECON GAP: lines 261-436 of UGCReviewScreen.swift unrecoverable")
        project.editDecisions = UGCEditDecisionEngine.buildEditDecisions(
#error("RECON GAP: lines 438-442 of UGCReviewScreen.swift unrecoverable")
        project.timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: project.editDecisions)
#error("RECON GAP: lines 444-569 of UGCReviewScreen.swift unrecoverable")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsContent: some View {
        VStack(spacing: 16) {
            // Caption Style
            VStack(alignment: .leading, spacing: 8) {
                Text(appText(language, "Altyazı Stili", "Caption Style"))
                    .font(.headline)
                    .foregroundStyle(.white)

                Picker("", selection: $project.selectedCaptionStyle) {
                    Text("Tech Kinetic").tag("techKinetic")
                    Text("Karaoke").tag("karaoke")
                    Text("Hook Impact").tag("hookImpact")
                    Text("Minimal").tag("subtitleMinimal")
                    Text("Lower Third").tag("lowerThird")
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
            .padding(14)
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // SFX Toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle(appText(language, "Ses Efektleri", "Sound Effects"), isOn: $project.sfxEnabled)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .tint(.green)

                Text(appText(language, "Kesim noktalarına geçiş sesleri ekler.", "Adds transition sounds at cut points."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(appText(language, "Bilgi", "Info"))
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(appText(language,
                             "Altyazı ve ses efekti ayarları mevcut videonun üzerine uygulanır. Değişiklikler export sırasında işlenir.",
                             "Caption and sound effect settings are applied to the current video. Changes are processed during export."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
