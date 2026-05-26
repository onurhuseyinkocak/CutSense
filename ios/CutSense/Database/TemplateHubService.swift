import Foundation
import Supabase

struct SharedTemplateRow: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let authorName: String
    let templateData: TemplateConfig
    let name: String
    let description: String
    let downloads: Int
    let ratingSum: Int
    let ratingCount: Int
    let createdAt: Date

    var averageRating: Double {
        ratingCount > 0 ? Double(ratingSum) / Double(ratingCount) : 0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case authorName = "author_name"
        case templateData = "template_data"
        case name, description, downloads
        case ratingSum = "rating_sum"
        case ratingCount = "rating_count"
        case createdAt = "created_at"
    }
}

struct SharedTemplateInsert: Codable, Sendable {
    let userId: UUID
    let authorName: String
    let templateData: TemplateConfig
    let name: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case authorName = "author_name"
        case templateData = "template_data"
        case name, description
    }
}

struct TemplateRatingInsert: Codable, Sendable {
    let userId: UUID
    let templateId: UUID
    let rating: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case templateId = "template_id"
        case rating
    }
}

struct TemplateRatingRow: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let templateId: UUID
    let rating: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case templateId = "template_id"
        case rating
    }
}

enum TemplateSortOrder: String, CaseIterable, Sendable {
    case popular
    case topRated
    case newest

    var displayName: String {
        switch self {
        case .popular: return "Popular"
        case .topRated: return "Top Rated"
        case .newest: return "Newest"
        }
    }
}

@MainActor
@Observable
final class TemplateHubService {
    var templates: [SharedTemplateRow] = []
    var isLoading = false
    var errorMessage: String?

    func fetchTemplates(sort: TemplateSortOrder = .popular) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let column: String
            let ascending: Bool
            switch sort {
            case .popular:
                column = "downloads"
                ascending = false
            case .topRated:
                column = "rating_count"
                ascending = false
            case .newest:
                column = "created_at"
                ascending = false
            }

            let rows: [SharedTemplateRow] = try await supabase
                .from("shared_templates")
                .select()
                .order(column, ascending: ascending)
                .limit(50)
                .execute()
                .value
            templates = rows
        } catch {
            #if DEBUG
            print("[TemplateHub] fetch failed: \(error)")
            #endif
            errorMessage = "Şablonlar yüklenemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    func upload(template: TemplateConfig, authorName: String, userId: UUID) async -> Bool {
        do {
            let insert = SharedTemplateInsert(
                userId: userId,
                authorName: authorName,
                templateData: template,
                name: template.name,
                description: template.description
            )
            try await supabase
                .from("shared_templates")
                .insert(insert)
                .execute()
            return true
        } catch {
            #if DEBUG
            print("[TemplateHub] upload failed: \(error)")
            #endif
            errorMessage = "Şablon yüklenemedi. Lütfen tekrar deneyin."
            return false
        }
    }

    func incrementDownload(id: UUID) async {
        // Optimistic — fire and forget
        do {
            // Read current, increment, update
            let row: SharedTemplateRow = try await supabase
                .from("shared_templates")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            try await supabase
                .from("shared_templates")
                .update(["downloads": row.downloads + 1])
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            // Non-critical
        }
    }

    func rate(templateId: UUID, userId: UUID, rating: Int) async -> Bool {
        do {
            let insert = TemplateRatingInsert(
                userId: userId,
                templateId: templateId,
                rating: max(1, min(5, rating))
            )
            // Upsert — one rating per user per template
            try await supabase
                .from("template_ratings")
                .upsert(insert, onConflict: "user_id,template_id")
                .execute()

            // Recalculate aggregate on shared_templates
            let ratings: [TemplateRatingRow] = try await supabase
                .from("template_ratings")
                .select()
                .eq("template_id", value: templateId.uuidString)
                .execute()
                .value
            let sum = ratings.reduce(0) { $0 + $1.rating }
            try await supabase
                .from("shared_templates")
                .update(["rating_sum": sum, "rating_count": ratings.count])
                .eq("id", value: templateId.uuidString)
                .execute()
            return true
        } catch {
            #if DEBUG
            print("[TemplateHub] rate failed: \(error)")
            #endif
            errorMessage = "Puanlama kaydedilemedi. Lütfen tekrar deneyin."
            return false
        }
    }

    func deleteOwn(id: UUID) async -> Bool {
        do {
            try await supabase
                .from("shared_templates")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            templates.removeAll { $0.id == id }
            return true
        } catch {
            #if DEBUG
            print("[TemplateHub] delete failed: \(error)")
            #endif
            errorMessage = "Şablon silinemedi. Lütfen tekrar deneyin."
            return false
        }
    }
}
