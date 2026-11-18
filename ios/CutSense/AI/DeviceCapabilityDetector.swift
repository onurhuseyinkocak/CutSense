import Foundation
import DeviceCheck
import os

/// Detects whether the device can run Apple Intelligence / on-device LLM locally.
/// iPhone 15 Pro Max (A17 Pro) and newer get local AI; older devices fall back to Pollinations.
enum DeviceCapabilityDetector {

    private static let logger = Logger(subsystem: "CutSense", category: "DeviceCapability")

    // MARK: - Chip Detection

    enum ChipTier: String, Sendable, CustomStringConvertible {
        /// A17 Pro and newer (iPhone 15 Pro, 15 Pro Max, 16+)
        case appleIntelligenceCapable = "a17_pro_plus"
        /// A16 Bionic (iPhone 14 Pro, 15, 15 Plus) — limited local AI
        case limitedLocal = "a16"
        /// A15 and older — no local AI, must use cloud
        case cloudOnly = "a15_or_older"

        var description: String { rawValue }
    }

    /// Whether this device has enough RAM + Neural Engine for on-device LLM inference.
    static var hasAppleIntelligence: Bool {
        chipTier == .appleIntelligenceCapable
    }

    static var chipTier: ChipTier {
        let info = ProcessInfo.processInfo
        let hwMachine = machineIdentifier()

        // iPhone 16 series (A18 / A18 Pro) — iPhone17,x identifiers
        if hwMachine.hasPrefix("iPhone17") {
            return .appleIntelligenceCapable
        }

        // iPhone 15 Pro / Pro Max (A17 Pro) — iPhone16,1 / iPhone16,2 identifiers
        if hwMachine == "iPhone16,1" || hwMachine == "iPhone16,2" {
            return .appleIntelligenceCapable
        }

        // iPhone 15 / 15 Plus (A16) — iPhone15,4 / iPhone15,5
        if hwMachine == "iPhone15,4" || hwMachine == "iPhone15,5" {
            return .limitedLocal
        }

        // iPhone 14 Pro / Pro Max (A16) — iPhone15,2 / iPhone15,3
        if hwMachine == "iPhone15,2" || hwMachine == "iPhone15,3" {
            return .limitedLocal
        }

        // Everything older (A15 and below)
        return .cloudOnly
    }

    // MARK: - Runtime Availability

    /// Whether Apple Intelligence features are actually enabled on this device
    /// (user can toggle it off in Settings > Apple Intelligence & Siri).
    static var isAppleIntelligenceEnabled: Bool {
        // On iOS 18.1+, check if the system reports AFM availability
        // For now, we use chip tier as the primary signal
        if #available(iOS 18.1, *) {
            return hasAppleIntelligence
        }
        return false
    }

    /// Whether the device has sufficient free memory for local inference
    /// without impacting user experience.
    static var hasSufficientMemory: Bool {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        // 8 GB RAM minimum for comfortable local AI inference
        let minimumBytes: UInt64 = 8 * 1024 * 1024 * 1024
        return totalMemory >= minimumBytes
    }

    /// Whether the device has a Neural Engine capable of on-device inference.
    static var hasNeuralEngine: Bool {
        return hasAppleIntelligence
    }

    // MARK: - Recommended Provider

    /// The recommended AI provider for the current device and context.
    static func recommendedProvider(
        requiresHighQuality: Bool = false,
        networkAvailable: Bool = true
    ) -> AIProvider {
        // Always try local first if the device supports it
        if isAppleIntelligenceEnabled && hasSufficientMemory {
            return .appleFoundationModel
        }

        // If local isn't available but network is, use Pollinations
        if networkAvailable {
            return .pollinations
        }

        // Offline fallback — use heuristic-only (no LLM)
        return .heuristicOnly
    }

    // MARK: - Device Info

    static var deviceModel: String {
        machineIdentifier()
    }

    static var deviceDescription: String {
        let tier = chipTier
        let model = machineIdentifier()
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        return "\(model) (\(tier), \(memoryGB)GB RAM)"
    }

    // MARK: - Private

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine
    }
}

// MARK: - AI Provider Enum

enum AIProvider: String, Sendable, CaseIterable {
    case appleFoundationModel = "apple_foundation_model"
    case pollinations = "pollinations"
    case heuristicOnly = "heuristic_only"

    var displayName: String {
        switch self {
        case .appleFoundationModel: "Apple Intelligence"
        case .pollinations: "Pollinations AI"
        case .heuristicOnly: "Heuristic (Offline)"
        }
    }

    var isLocal: Bool {
        switch self {
        case .appleFoundationModel, .heuristicOnly: true
        case .pollinations: false
        }
    }
}
