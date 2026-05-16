import Foundation

struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var email: String?
    var displayName: String?
    var avatarUrl: String?
    var createdAt: Date?
    var updatedAt: Date?
    var lastLoginAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastLoginAt = "last_login_at"
    }
}

struct Project: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var title: String
    var originalDuration: Double?
    var finalDuration: Double?
    var status: ProjectStatus
    var selectedTemplate: String?
    var sourceLocalIdentifier: String?
    var sourceFileName: String?
    var localProjectPath: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case userId = "user_id"
        case originalDuration = "original_duration"
        case finalDuration = "final_duration"
        case selectedTemplate = "selected_template"
        case sourceLocalIdentifier = "source_local_identifier"
        case sourceFileName = "source_file_name"
        case localProjectPath = "local_project_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum ProjectStatus: String, Codable, Sendable {
    case draft
    case imported
    case analyzing
    case roughCutReady = "rough_cut_ready"
    case reviewed
    case styling
    case exporting
    case exported
    case failed
}

struct CreateProjectRequest: Codable, Sendable {
    let userId: UUID
    let title: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case title
        case status
    }
}
