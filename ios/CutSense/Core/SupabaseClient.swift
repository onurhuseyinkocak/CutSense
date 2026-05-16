import Foundation
import Supabase

enum SupabaseConfig {
    static let url: URL = {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL not set in Info.plist — check Secrets.xcconfig")
        }
        return url
    }()

    static let anonKey: String = {
        guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY not set in Info.plist — check Secrets.xcconfig")
        }
        return key
    }()
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
