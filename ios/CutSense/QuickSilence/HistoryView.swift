import SwiftUI
import UIKit

/// Saved-to-Photos edits: totals, a bar strip of recent cut shares, and one row per save.
struct HistoryView: View {
    let language: AppLanguage

    @State private var store = HistoryStore.shared
    @State private var shownSeconds: Double = 0
    @State private var shownCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Mono.C.bg.ignoresSafeArea())
        .tint(Mono.C.text)
        .navigationTitle(t("Geçmiş", "History"))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sensoryFeedback(.impact(weight: .light), trigger: store.entries.count)
        .onAppear(perform: syncTotals)
        .onChange(of: store.entries.count) { syncTotals() }
    }

    private var list: some View {
        List {
            Section {
                summary
                    .listRowInsets(EdgeInsets(top: Mono.Space.xs, leading: Mono.Space.xs, bottom: Mono.Space.m, trailing: Mono.Space.xs))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                    if index < 8 {
                        row(entry).monoEntrance(index)
                    } else {
                        row(entry)
                    }
                }
                .listRowBackground(Mono.C.raised)
                .listRowSeparatorTint(Mono.C.hairline)
            } footer: {
                Text(t("Yalnızca küçük bir önizleme ve sayılar saklanır. Videoların galeride kalır.",
                       "Only a small preview and the numbers are kept. Your videos stay in Photos."))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text3)
                    .padding(.top, Mono.Space.xxs)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Mono.Space.l) {
            HStack(alignment: .top, spacing: Mono.Space.l) {
                stat(timeString(shownSeconds), value: shownSeconds, caption: t("Kesilen sessizlik", "Silence cut"))
                stat("\(shownCount)", value: Double(shownCount), caption: t("Video", "Videos"))
            }
            .accessibilityElement(children: .combine)
            HistoryBars(percents: store.entries.map(\.removedPercent))
        }
    }

    private func stat(_ text: String, value: Double, caption: String) -> some View {
        VStack(alignment: .leading, spacing: Mono.Space.xxs) {
            Text(text)
                .monoText(.numeralXL)
                .foregroundStyle(Mono.C.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: value))
            Text(caption)
                .monoText(.overline)
                .foregroundStyle(Mono.C.text3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        Button {
            if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: Mono.Space.s) {
                thumbnail(entry)
                VStack(alignment: .leading, spacing: Mono.Space.xxs) {
                    Text("\(timeString(entry.originalDuration)) → \(timeString(entry.outputDuration))")
                        .monoText(.numeralM)
                        .foregroundStyle(Mono.C.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(([dateText(entry), levelText(entry)] + [entry.resolution].compactMap { $0 }).joined(separator: " · "))
                        .monoText(.caption)
                        .foregroundStyle(Mono.C.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8) // DE on 16e: keeps the resolution visible
                }
                Spacer(minLength: 0)
                MonoBadge((entry.removedPercent > 0 ? "−" : "") + percentText(entry.removedPercent))
            }
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(entry))
        .accessibilityHint(t("Galeriyi açar", "Opens Photos"))
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                withAnimation { store.delete(id: entry.id) }
            } label: {
                Label(t("Sil", "Delete"), systemImage: "trash")
            }
            .tint(Mono.C.elevated)
        }
    }

    @ViewBuilder
    private func thumbnail(_ entry: HistoryEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: Mono.Radius.chip, style: .continuous)
        Group {
            if entry.hasThumbnail, let image = UIImage(contentsOfFile: store.thumbnailURL(for: entry.id).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Mono.C.elevated
                    Image(systemName: "film")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Mono.C.text3)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Mono.C.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: Mono.Space.m) {
            HistoryBars(percents: [])
                .frame(maxWidth: 240)
                .padding(.bottom, Mono.Space.s)
            Text(t("Henüz düzenleme yok", "No edits yet"))
                .monoText(.title)
                .foregroundStyle(Mono.C.text)
                .multilineTextAlignment(.center)
            Text(t("Galeriye kaydettiğin videolar burada görünür.", "Videos you save to Photos appear here."))
                .monoText(.body)
                .foregroundStyle(Mono.C.text2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Mono.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .monoEntrance(0)
    }

    // MARK: - Text

    private func dateText(_ entry: HistoryEntry) -> String {
        entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()
            .locale(Locale(identifier: language == .pt ? "pt-BR" : language.rawValue)))
    }

    private func levelText(_ entry: HistoryEntry) -> String {
        if entry.isCustom { return t("Özel", "Custom") }
        return QuickSilenceEngine.CutIntensity(rawValue: entry.intensity)?.title(for: language) ?? entry.intensity
    }

    /// "%45" in Turkish, "45%" elsewhere (shared key with the review stats).
    private func percentText(_ percent: Int) -> String {
        String(format: t("%%%d", "%d%%"), percent)
    }

    private func accessibilityLabel(_ entry: HistoryEntry) -> String {
        let change = String(format: t("%@ → %@, %@ kesildi", "From %@ to %@, %@ removed"),
                            timeString(entry.originalDuration), timeString(entry.outputDuration), percentText(entry.removedPercent))
        return [dateText(entry), change, levelText(entry)].joined(separator: ", ")
    }

    private func syncTotals() {
        let seconds = store.removedSeconds
        let count = store.entries.count
        if reduceMotion {
            shownSeconds = seconds
            shownCount = count
        } else {
            withAnimation(Mono.Motion.smooth) {
                shownSeconds = seconds
                shownCount = count
            }
        }
    }
}

/// 32 slots, oldest left; each filled slot is that save's cut share. Decorative.
private struct HistoryBars: View {
    /// Newest first, as stored.
    let percents: [Int]

    private static let slots = 32
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let recent = Array(percents.prefix(Self.slots).reversed())
        let offset = Self.slots - recent.count
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<Self.slots, id: \.self) { slot in
                let percent = slot >= offset ? recent[slot - offset] : nil
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(percent == nil ? Mono.C.hairline : Mono.C.text)
                    .frame(height: 44 * max(0.08, Double(percent ?? 0) / 100))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                    .animation(reduceMotion ? nil : Mono.Motion.smooth.delay(0.012 * Double(slot)), value: grown)
            }
        }
        .frame(height: 44, alignment: .bottom)
        .accessibilityHidden(true)
        .onAppear { grown = true }
    }
}
