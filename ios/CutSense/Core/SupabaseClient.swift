import Foundation
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://xmktbdhilgntfmqovdmb.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhta3RiZGhpbGdudGZtcW92ZG1iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4ODY3MjMsImV4cCI6MjA5NDQ2MjcyM30.zbhljhrnID6eDOrDKz1trs-C-IKsatnHprRjdhypjj4"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
