import Foundation
import os

/// Pollinations.ai LLM chat completion API integration.
/// Uses the provided API key for authenticated requests.
/// Routes to cloud LLM when local Apple Intelligence is unavailable.
struct PollinationsLLMService: Sendable {

    private static let logger = Logger(subsystem: "CutSense", category: "PollinationsLLM")

    // MARK: - Configuration

    struct Config: Sendable {
        let apiKey: String
        let baseURL: String
        let model: String
        let maxTokens: Int
        let temperature: Double
        let timeoutSeconds: TimeInterval
        let maxRetries: Int

        static let `default` = Config(
            apiKey: PollinationsLLMService.apiKeyFromInfoPlist(),
            baseURL: "https://text.pollinations.ai",
            model: "openai",
            maxTokens: 1024,
            temperature: 0.7,
            timeoutSeconds: 30,
            maxRetries: 2
        )
    }

    private let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    /// Read Pollinations API key from Info.plist (populated by Secrets.xcconfig)
    /// SECURITY NOTE: The key is compiled into Info.plist via xcconfig. For production,
    /// move this to a backend proxy (Supabase Edge Function) to avoid exposing the key.
    static func apiKeyFromInfoPlist() -> String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "POLLINATIONS_API_KEY") as? String,
              !key.isEmpty else {
            Self.logger.error("POLLINATIONS_API_KEY not found in Info.plist — AI features disabled")
            return ""
        }
        return key
    }



    // MARK: - Chat Completion

    struct ChatMessage: Sendable, Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Sendable, Codable {
        let model: String
        let messages: [ChatMessage]
        let max_tokens: Int
        let temperature: Double
        let json_mode: Bool?
    }

    struct ChatResponse: Sendable, Codable {
        let id: String?
        let choices: [Choice]?
        let usage: Usage?

        struct Choice: Sendable, Codable {
            let message: ChatMessage?
            let finish_reason: String?
        }

        struct Usage: Sendable, Codable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let total_tokens: Int?
        }
    }

    /// Send a chat completion request to Pollinations.
    /// - Returns: The assistant's response text, or nil on failure.
    func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        jsonMode: Bool = false,
        temperature: Double? = nil
    ) async -> String? {
        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userMessage)
        ]
        return await chatCompletion(messages: messages, jsonMode: jsonMode, temperature: temperature)
    }

    /// Log API key prefix for debugging (first 8 chars only)
    private var keyPrefix: String {
        String(config.apiKey.prefix(8)) + "..."
    }

    /// Send a multi-message chat completion request.
    func chatCompletion(
        messages: [ChatMessage],
        jsonMode: Bool = false,
        temperature: Double? = nil
    ) async -> String? {
        guard !config.apiKey.isEmpty else {
            Self.logger.error("Pollinations API key is empty — cannot make requests")
            return nil
        }

        Self.logger.info("Pollinations request using key: \(self.keyPrefix)")
        let request = ChatRequest(
            model: config.model,
            messages: messages,
            max_tokens: config.maxTokens,
            temperature: temperature ?? config.temperature,
            json_mode: jsonMode ? true : nil
        )

        for attempt in 0...config.maxRetries {
            if attempt > 0 {
                let backoff = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: backoff)
            }
            guard !Task.isCancelled else {
                Self.logger.info("Pollinations request cancelled")
                return nil
            }
            if let result = await executeRequest(request) {
                return result
            }
        }

        Self.logger.error("Pollinations LLM failed after \(self.config.maxRetries + 1) attempts")
        return nil
    }

    // MARK: - Structured Output

    /// Request structured JSON output from the LLM.
    func structuredCompletion<T: Decodable>(
        systemPrompt: String,
        userMessage: String,
        responseType: T.Type
    ) async -> T? {
        guard let text = await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            jsonMode: true
        ) else {
            return nil
        }

        guard let data = text.data(using: .utf8) else {
            Self.logger.error("Failed to convert response to data")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("Failed to decode response: \(error.localizedDescription)")
            // Try to extract JSON from markdown code blocks
            if let extracted = extractJSON(from: text),
               let extractedData = extracted.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(T.self, from: extractedData) {
                return decoded
            }
            return nil
        }
    }

    // MARK: - Private

    private func executeRequest(_ request: ChatRequest) async -> String? {
        guard let url = URL(string: "\(config.baseURL)/v1/chat/completions") else {
            Self.logger.error("Invalid URL")
            return nil
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = config.timeoutSeconds
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            Self.logger.error("Failed to encode request: \(error.localizedDescription)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                Self.logger.error("Invalid response type")
                return nil
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                Self.logger.error("HTTP \(httpResponse.statusCode): \(body.prefix(200))")
                return nil
            }

            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = chatResponse.choices?.first?.message?.content else {
                Self.logger.error("No content in response")
                return nil
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Self.logger.error("Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func extractJSON(from text: String) -> String? {
        // Try to extract JSON from ```json ... ``` blocks
        let patterns = [
            #"```json\s*\n([\s\S]*?)\n\s*```"#,
            #"```\s*\n([\s\S]*?)\n\s*```"#,
            #"\{[\s\S]*\}"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..<text.endIndex, in: text)
                  ) else {
                continue
            }

            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            let range = match.range(at: captureIndex)
            if let swiftRange = Range(range, in: text) {
                return String(text[swiftRange])
            }
        }

        return nil
    }
}
