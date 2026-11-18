import Foundation
import os

/// Routes AI requests between Apple Foundation Models (local) and Pollinations (cloud).
///
/// Routing logic:
/// - iPhone 15 Pro Max (A17 Pro) and newer → Apple Intelligence (local)
/// - Older devices → Pollinations API (cloud)
/// - Offline → heuristic fallback (no LLM)
///
/// Every AI call in the app goes through this router. The router handles:
/// - Device capability detection
/// - Provider selection
/// - Automatic fallback if one provider fails
/// - Structured output parsing
/// - Network state awareness
struct AIProviderRouter: Sendable {

    private static let logger = Logger(subsystem: "CutSense", category: "AIProviderRouter")


    // MARK: - Configuration

    private let pollinations: PollinationsLLMService
    private let forceProvider: AIProvider?

    init(
        pollinationsConfig: PollinationsLLMService.Config = .default,
        forceProvider: AIProvider? = nil
    ) {
        self.pollinations = PollinationsLLMService(config: pollinationsConfig)
        self.forceProvider = forceProvider
    }

    // MARK: - Provider Selection

    /// Determine which provider to use for a given request.
    func selectProvider(
        requiresHighQuality: Bool = false,
        networkAvailable: Bool = true
    ) -> AIProvider {
        if let forced = forceProvider {
            return forced
        }
        return DeviceCapabilityDetector.recommendedProvider(
            requiresHighQuality: requiresHighQuality,
            networkAvailable: networkAvailable
        )
    }

    // MARK: - Chat Completion

    /// Send a chat completion request, routing to the best available provider.
    /// Automatically falls back if the primary provider fails.
    func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        jsonMode: Bool = false,
        temperature: Double? = nil,
        requiresHighQuality: Bool = false,
        networkAvailable: Bool = true
    ) async -> String? {
        let primary = selectProvider(
            requiresHighQuality: requiresHighQuality,
            networkAvailable: networkAvailable
        )

        Self.logger.info("Routing to \(primary.displayName)")

        // Try primary provider
        switch primary {
        case .appleFoundationModel:
            if let result = await appleFoundationModelCompletion(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                jsonMode: jsonMode,
                temperature: temperature
            ) {
                return result
            }
            // Fallback to Pollinations
            Self.logger.warning("Apple Foundation Model failed, falling back to Pollinations")
            return await pollinations.chatCompletion(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                jsonMode: jsonMode,
                temperature: temperature
            )

        case .pollinations:
            return await pollinations.chatCompletion(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                jsonMode: jsonMode,
                temperature: temperature
            )

        case .heuristicOnly:
            Self.logger.info("Heuristic-only mode — no LLM available")
            return nil
        }
    }

    /// Multi-message chat completion with automatic routing.
    func chatCompletion(
        messages: [PollinationsLLMService.ChatMessage],
        jsonMode: Bool = false,
        temperature: Double? = nil,
        networkAvailable: Bool = true
    ) async -> String? {
        let primary = selectProvider(networkAvailable: networkAvailable)

        switch primary {
        case .appleFoundationModel:
            // Apple Foundation Models only supports single-message completion currently
            return await pollinations.chatCompletion(messages: messages, jsonMode: jsonMode, temperature: temperature)

        case .pollinations:
            return await pollinations.chatCompletion(messages: messages, jsonMode: jsonMode, temperature: temperature)

        case .heuristicOnly:
            return nil
        }
    }

    // MARK: - Structured Output

    /// Request structured JSON output from the best available provider.
    func structuredCompletion<T: Decodable>(
        systemPrompt: String,
        userMessage: String,
        responseType: T.Type,
        networkAvailable: Bool = true
    ) async -> T? {
        let primary = selectProvider(networkAvailable: networkAvailable)

        switch primary {
        case .appleFoundationModel:
            // Try local first
            if let result = await appleFoundationModelStructured(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                responseType: responseType
            ) {
                return result
            }
            // Fallback to Pollinations
            return await pollinations.structuredCompletion(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                responseType: responseType
            )

        case .pollinations:
            return await pollinations.structuredCompletion(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                responseType: responseType
            )

        case .heuristicOnly:
            return nil
        }
    }

    // MARK: - Apple Foundation Models (Local)

    private func appleFoundationModelCompletion(
        systemPrompt: String,
        userMessage: String,
        jsonMode: Bool,
        temperature: Double?
    ) async -> String? {
        guard DeviceCapabilityDetector.isAppleIntelligenceEnabled else {
            Self.logger.info("Apple Intelligence not available on this device")
            return nil
        }

        // TODO: Apple Foundation Models on-device inference.
        // Apple has not yet published a public API for on-device LLM inference.
        // When it ships (likely tied to an Apple Intelligence system-model API),
        // integrate it HERE. Until then, returning nil routes to Pollinations,
        // which keeps AI features working on every device without a hard dependency.
        Self.logger.info("Apple Foundation Models API not yet public — falling back to Pollinations")
        return nil
    }

    private func appleFoundationModelStructured<T: Decodable>(
        systemPrompt: String,
        userMessage: String,
        responseType: T.Type
    ) async -> T? {
        guard let text = await appleFoundationModelCompletion(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            jsonMode: true,
            temperature: 0.7
        ) else {
            return nil
        }

        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

}


