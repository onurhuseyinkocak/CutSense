import SwiftUI

struct TemplateHubScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var hub = TemplateHubService()
    @State private var sortOrder: TemplateSortOrder = .popular
    @State private var searchText = ""
    let onSelect: (TemplateConfig) -> Void

    private var filteredTemplates: [SharedTemplateRow] {
        guard !searchText.isEmpty else { return hub.templates }
        return hub.templates.filter { row in
            row.name.localizedCaseInsensitiveContains(searchText) ||
            row.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var templatesByCategory: [(category: TemplateCategory, templates: [SharedTemplateRow])] {
        let grouped = Dictionary(grouping: filteredTemplates, by: \.templateData.category)
        return TemplateCategory.allCases
            .compactMap { cat in
                grouped[cat].map { (cat, $0) }
            }
            .sorted { a, b in
                let order: [TemplateCategory] = [.professional, .social, .creative, .lifestyle]
                return (order.firstIndex(of: a.category) ?? 999) < (order.firstIndex(of: b.category) ?? 999)
            }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if hub.isLoading && hub.templates.isEmpty {
                    ProgressView().tint(.white)
                } else if hub.templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
        }
        .navigationTitle("Template Hub")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(TemplateSortOrder.allCases, id: \.self) { order in
                        Button {
                            HapticEngine.select()
                            sortOrder = order
                            Task { await hub.fetchTemplates(sort: order) }
                        } label: {
                            HStack {
                                Text(order.displayName)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            await hub.fetchTemplates(sort: sortOrder)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 40))
                .foregroundStyle(.gray)
            Text("No community templates yet")
                .foregroundStyle(.gray)
            Text("Templates shared by the community will appear here.")
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.gray)
                    TextField("Search templates...", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Material.ultraThin)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 12)

                // Categories
                if templatesByCategory.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.gray)
                        Text("No templates found")
                            .foregroundStyle(.gray)
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.6))
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(templatesByCategory, id: \.category) { category, templates in
                            CategorySection(
                                category: category,
                                templates: templates,
                                onSelect: { template in
                                    var config = template.templateData
                                    config.themeId = template.templateData.id
                                    onSelect(config)
                                    Task { await hub.incrementDownload(id: template.id) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
        .refreshable {
            await hub.fetchTemplates(sort: sortOrder)
        }
    }
}

private struct CategorySection: View {
    let category: TemplateCategory
    let templates: [SharedTemplateRow]
    let onSelect: (SharedTemplateRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(templates.count)")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(templates) { template in
                        TemplateCard(
                            template: template,
                            onSelect: { onSelect(template) }
                        )
                        .frame(width: 160)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct TemplateCard: View {
    let template: SharedTemplateRow
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Color palette preview
            HStack(spacing: 6) {
                ForEach([
                    template.templateData.captionTheme.karaokeHighlight.uiColor,
                    template.templateData.captionTheme.hookBgColor.uiColor,
                    template.templateData.captionTheme.defaultTextColor.uiColor,
                    UIColor.black.withAlphaComponent(0.3)
                ], id: \.self) { color in
                    Circle()
                        .fill(Color(uiColor: color))
                        .frame(height: 8)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            // Template info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if template.templateData.intensity == .high {
                        Text("Pro")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.8))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption2)
                        Text("\(template.downloads)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.gray)

                    if template.ratingCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text(String(format: "%.1f", template.averageRating))
                                .font(.caption2)
                        }
                        .foregroundStyle(.yellow)
                    }

                    Spacer()
                }
            }

            // Use button
            Button {
                HapticEngine.select()
                onSelect()
            } label: {
                Text("Use")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.white.opacity(isHovered ? 0.15 : 0.08),
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
