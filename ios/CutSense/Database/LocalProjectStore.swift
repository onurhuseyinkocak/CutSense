import Foundation

@MainActor
enum LocalProjectStore {
    static var testStoreURL: URL?

    private static var storeURL: URL {
        if let testStoreURL {
            return testStoreURL
        }
        let directory = URL.applicationSupportDirectory
            .appending(path: "CutSense", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "local-projects.json")
    }

    static func load(userId: UUID) -> [Project] {
        guard let data = try? Data(contentsOf: storeURL),
              let projects = try? JSONDecoder.cutSense.decode([Project].self, from: data) else {
            return []
        }
        return projects
            .filter { $0.userId == userId }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    static func upsert(_ project: Project) {
        var projects = loadAll()
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
        save(projects)
    }

    static func update(id: UUID, _ mutation: (inout Project) -> Void) {
        var projects = loadAll()
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        mutation(&projects[index])
        projects[index].updatedAt = Date()
        save(projects)
    }

    static func delete(_ project: Project) {
        deleteById(project.id)
    }

    static func deleteById(_ id: UUID) {
        var projects = loadAll()
        projects.removeAll { $0.id == id }
        save(projects)
    }

    private static func loadAll() -> [Project] {
        guard let data = try? Data(contentsOf: storeURL),
              let projects = try? JSONDecoder.cutSense.decode([Project].self, from: data) else {
            return []
        }
        return projects
    }

    private static func save(_ projects: [Project]) {
        guard let data = try? JSONEncoder.cutSense.encode(projects) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }
}

private extension JSONDecoder {
    static var cutSense: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var cutSense: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
