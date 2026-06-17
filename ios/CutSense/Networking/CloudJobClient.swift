import Foundation

/// Thin client for the manifest-driven cloud editing backend (Supabase edge
/// functions + Storage). The heavy work runs server-side; the app only uploads
/// the raw video, polls the job, and fetches the finished MP4.
struct CreateJobResponse: Decodable {
    let job_id: String
    let raw_key: String
    let bucket: String
    let upload_url: String
    let upload_token: String
}

struct CloudJobStatus: Decodable {
    let status: String
    let progress: Int
    let error: String?
    let raw_url: String?
    let final_url: String?
}

enum CloudJobError: LocalizedError {
    case noSession
    case badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noSession: return "Oturum bulunamadı. Lütfen giriş yapın."
        case .badResponse: return "Sunucudan geçersiz yanıt."
        case let .http(code, body): return "Sunucu hatası \(code): \(body.prefix(140))"
        }
    }
}

actor CloudJobClient {
    static let shared = CloudJobClient()

    private let base = SupabaseConfig.url
    private let anon = SupabaseConfig.anonKey

    private func jwt() async throws -> String {
        guard let token = try? await supabase.auth.session.accessToken, !token.isEmpty else {
            throw CloudJobError.noSession
        }
        return token
    }

    /// Create a queued job + a signed upload URL for the raw video.
    func createJob(ext: String = "mp4") async throws -> CreateJobResponse {
        try await callFunction("create-job", body: ["ext": ext])
    }

    /// Poll job status; `final_url` is a signed GET URL once status == "done".
    func status(jobId: String) async throws -> CloudJobStatus {
        try await callFunction("job-status", body: ["job_id": jobId])
    }

    /// Mark the job ready for the worker — call AFTER uploadRaw succeeds so the
    /// poller never claims a job whose raw object isn't uploaded yet.
    func enqueue(jobId: String) async throws {
        let token = try await jwt()
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/jobs"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(jobId)")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": "queued"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.ensureOK(resp, data)
    }

    /// PUT the (compressed) raw video to the signed upload URL from create-job.
    /// Verified against macOS URLSession (HTTP 200). NOTE: the iOS Simulator's
    /// network stack returns NSURLErrorCannotParseResponse (-1017) on body
    /// uploads — a simulator-only bug; macOS/device URLSession uploads fine.
    func uploadRaw(fileURL: URL, job: CreateJobResponse) async throws {
        guard let url = URL(string: job.upload_url) else { throw CloudJobError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: fileURL)
        try Self.ensureOK(resp, data)
    }

    /// Download the finished video to a temp file (for sharing / local playback).
    func download(_ urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else { throw CloudJobError.badResponse }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        try Self.ensureOK(resp, Data())
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("cs_final_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private func callFunction<T: Decodable>(_ name: String, body: [String: Any]) async throws -> T {
        let token = try await jwt()
        var req = URLRequest(url: base.appendingPathComponent("functions/v1/\(name)"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.ensureOK(resp, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func ensureOK(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw CloudJobError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudJobError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
