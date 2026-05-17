import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let cutsenseTemplate = UTType(exportedAs: "com.cutsense.template")
}

/// Wrapper for sharing — single template or pack
struct TemplatePack: Codable {
    let version: Int
    let templates: [TemplateConfig]

    init(templates: [TemplateConfig]) {
        self.version = 1
        self.templates = templates
    }
}

@MainActor
@Observable
final class CustomTemplateStore {
    static let shared = CustomTemplateStore()

    private(set) var templates: [TemplateConfig] = []
    private let key = "custom_templates_v1"

    private init() {
        load()
    }

    func save(_ template: TemplateConfig) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        persist()
    }

    func delete(_ id: String) {
        templates.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Export

    /// Export templates as a shareable .cutsensetemplate file URL
    func exportFile(_ templates: [TemplateConfig]) -> URL? {
        let pack = TemplatePack(templates: templates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(pack) else { return nil }

        let name: String
        if templates.count == 1, let first = templates.first {
            let safe = first.name.replacingOccurrences(of: " ", with: "_")
            name = "\(safe).cutsensetemplate"
        } else {
            name = "CutSense_Pack_\(templates.count).cutsensetemplate"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Import

    /// Import templates from a .cutsensetemplate file. Returns imported count.
    @discardableResult
    func importFile(at url: URL) -> Int {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return 0 }
        return importData(data)
    }

    /// Import from raw JSON data. Returns imported count.
    @discardableResult
    func importData(_ data: Data) -> Int {
        // Try pack format first
        if let pack = try? JSONDecoder().decode(TemplatePack.self, from: data) {
            return importTemplates(pack.templates)
        }
        // Try single template
        if let single = try? JSONDecoder().decode(TemplateConfig.self, from: data) {
            return importTemplates([single])
        }
        // Try bare array
        if let array = try? JSONDecoder().decode([TemplateConfig].self, from: data) {
            return importTemplates(array)
        }
        return 0
    }

    private func importTemplates(_ incoming: [TemplateConfig]) -> Int {
        var count = 0
        for var template in incoming {
            // Give imported templates a fresh custom_ id to avoid collisions with presets
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
            // Skip exact duplicates by name
            if templates.contains(where: { $0.name == template.name && $0.id == template.id }) {
                continue
            }
            templates.append(template)
            count += 1
        }
        if count > 0 { persist() }
        return count
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TemplateConfig].self, from: data) else {
            return
        }
        templates = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
