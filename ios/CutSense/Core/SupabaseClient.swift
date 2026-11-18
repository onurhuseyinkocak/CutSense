import Foundation
import Supabase

enum SupabaseConfig {
    static let isConfigured: Bool = {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String else {
            return false
        }
        return URL(string: urlString) != nil && !key.isEmpty
    }()

    static let url: URL = {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let url = URL(string: urlString) else {
            // Local editing never uses this endpoint. A syntactically valid
            // inert value keeps optional cloud features from crashing launch.
            return URL(string: "http://127.0.0.1")!
        }
        return url
    }()

    static let anonKey: String = {
        (Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "local-only"
    }()
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
