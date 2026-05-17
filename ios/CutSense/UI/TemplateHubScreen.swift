import SwiftUI

struct TemplateHubScreen: View {
    @State private var hub = TemplateHubService()
    @State private var sortOrder: TemplateSortOrder = .popular
    @State private var ratingTemplateId: UUID?
    @State private var pendingRating: Int = 0
    @State private var downloadedMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hub.isLoading && hub.templates.isEmpty {
                ProgressView()
                    .tint(.white)
            } else if hub.templates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("No community templates yet")
                        .foregroundStyle(.gray)
                    Text("Be the first to share!")
                        .font(.caption)
                        .foregroundStyle(.gray.opacity(0.7))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        sortPicker

                        if let msg = downloadedMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }

                        ForEach(hub.templates) { row in
                            HubTemplateCard(
                                row: row,
                                onDownload: { downloadTemplate(row) },
                                onRate: {
                                    ratingTemplateId = row.id
                                    pendingRating = 0
                                }
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Community Hub")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await hub.fetchTemplates(sort: sortOrder) }
        .onChange(of: sortOrder) { _, newSort in
            Task { await hub.fetchTemplates(sort: newSort) }
        }
        .alert("Rate Template", isPresented: .init(
            get: { ratingTemplateId != nil },
            set: { if !$0 { ratingTemplateId = nil } }
        )) {
            ForEach(1...5, id: \.self) { star in
                Button("\(star) Star\(star == 1 ? "" : "s")") {
                    guard let id = ratingTemplateId else { return }
                    Task { await submitRating(templateId: id, rating: star) }
                }
            }
            Button("Cancel", role: .cancel) { ratingTemplateId = nil }
        } message: {
            Text("How would you rate this template?")
        }
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortOrder) {
            ForEach(TemplateSortOrder.allCases, id: \.self) { order in
                Text(order.displayName).tag(order)
            }
        }
        .pickerStyle(.segmented)
    }

    private func downloadTemplate(_ row: SharedTemplateRow) {
        var template = row.templateData
        // Ensure imported template gets a custom_ id
        if !template.id.hasPrefix("custom_") {
            template = TemplateConfig(
                id: "custom_\(UUID().uuidString.prefix(8))",
                name: template.name,
                description: template.description,
                intensity: template.intensity,
                hookStyle: template.hookStyle,
                emphasisStyle: template.emphasisStyle,
                keywordStyle: template.keywordStyle,
                conclusionStyle: template.conclusionStyle,
                defaultStyle: template.defaultStyle,
                backgroundMusicVolume: template.backgroundMusicVolume,
                sfxVolume: template.sfxVolume,
                voiceBoostDB: template.voiceBoostDB,
                minCutDuration: template.minCutDuration,
                maxSilenceDuration: template.maxSilenceDuration,
                colorGrade: template.colorGrade,
                themeId: template.themeId
            )
        }
        CustomTemplateStore.shared.save(template)
        Task { await hub.incrementDownload(id: row.id) }
        downloadedMessage = "Downloaded \"\(row.name)\""
        Task {
            try? await Task.sleep(for: .seconds(3))
            downloadedMessage = nil
        }
    }

    private func submitRating(templateId: UUID, rating: Int) async {
        guard let userId = try? await supabase.auth.session.user.id else { return }
        let success = await hub.rate(templateId: templateId, userId: userId, rating: rating)
        if success {
            await hub.fetchTemplates(sort: sortOrder)
        }
    }
}

// MARK: - Hub Template Card

private struct HubTemplateCard: View {
    let row: SharedTemplateRow
    let onDownload: () -> Void
    let onRate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("by \(row.authorName)")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                Spacer()
                intensityBadge
            }

            if !row.description.isEmpty {
                Text(row.description)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                // Rating
                Button(action: onRate) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        if row.ratingCount > 0 {
                            Text(String(format: "%.1f", row.averageRating))
                                .foregroundStyle(.white)
                            Text("(\(row.ratingCount))")
                                .foregroundStyle(.gray)
                        } else {
                            Text("Rate")
                                .foregroundStyle(.gray)
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)

                // Downloads
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.gray)
                    Text("\(row.downloads)")
                        .foregroundStyle(.gray)
                }
                .font(.caption)

                Spacer()

                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var intensityBadge: some View {
        Text(row.templateData.intensity.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(intensityColor.opacity(0.15))
            .foregroundStyle(intensityColor)
            .clipShape(Capsule())
    }

    private var intensityColor: Color {
        switch row.templateData.intensity {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        }
    }
}
