import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

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
            Self.logger.warning("Apple Foundation Model failed; zero-cost local fallback selected")
            return nil

        case .pollinations:
            guard DeviceCapabilityDetector.cloudFallbackEnabled else {
                Self.logger.info("Cloud AI is disabled by the zero-cost policy")
                return nil
            }
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
            // Multi-message cloud inference is disabled in the zero-cost build.
            return nil

        case .pollinations:
            guard DeviceCapabilityDetector.cloudFallbackEnabled else { return nil }
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
            return nil

        case .pollinations:
            guard DeviceCapabilityDetector.cloudFallbackEnabled else { return nil }
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

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                Self.logger.info("Apple Foundation Model is not ready")
                return nil
            }

            do {
                let session = LanguageModelSession(model: model, instructions: systemPrompt)
                let options = GenerationOptions(
                    temperature: temperature,
                    maximumResponseTokens: jsonMode ? 1_024 : 512
                )
                let response = try await session.respond(to: userMessage, options: options)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                Self.logger.error("Apple Foundation Model failed: \(error.localizedDescription)")
                return nil
            }
        }
        #endif

        Self.logger.info("Foundation Models is unavailable on this OS")
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


