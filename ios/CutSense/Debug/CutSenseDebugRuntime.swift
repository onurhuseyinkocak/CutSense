import Foundation

enum CutSenseDebugRuntime {
    static var forceProEntitlement: Bool {
        #if DEBUG
        true
        || boolValue(for: "CUTSENSE_DEBUG_FORCE_PRO")
        || UserDefaults.standard.bool(forKey: "cutsense.debug.forcePro")
        #else
        false
        #endif
    }

    static var forcePipelineExecution: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_FORCE_PIPELINE")
        || UserDefaults.standard.bool(forKey: "cutsense.debug.forcePipeline")
        #else
        false
        #endif
    }

    static var resetPipelineArtifactsOnLaunch: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_RESET_PIPELINE")
        #else
        false
        #endif
    }

    static var autorunPipelineOnLaunch: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_AUTORUN_PIPELINE")
        #else
        false
        #endif
    }

    static var useSyntheticTranscript: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_SYNTHETIC_TRANSCRIPT")
        #else
        false
        #endif
    }

    static var forceHeuristicSmartAnalysis: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_FORCE_HEURISTIC_ANALYSIS")
        || UserDefaults.standard.bool(forKey: "cutsense.debug.forceHeuristicSmartAnalysis")
        #else
        false
        #endif
    }

    static var enableFoundationModelsSmartAnalysis: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_ENABLE_FOUNDATION_MODELS")
        || UserDefaults.standard.bool(forKey: "cutsense.debug.enableFoundationModelsSmartAnalysis")
        #else
        false
        #endif
    }

    static var exportEvenWhenQualityFails: Bool {
        #if DEBUG
        boolValue(for: "CUTSENSE_DEBUG_EXPORT_ON_QUALITY_FAIL")
        #else
        false
        #endif
    }

    static var debugInputFileName: String {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUTSENSE_DEBUG_INPUT_FILE"] ?? "cutsense_debug_input.mp4"
        #else
        "cutsense_debug_input.mp4"
        #endif
    }

    static func boolValue(for environmentKey: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey] else {
            return false
        }

        switch raw.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

@MainActor
enum CutSenseDebugBootstrap {
    static func configureOnLaunch() async {
        #if DEBUG
        if CutSenseDebugRuntime.resetPipelineArtifactsOnLaunch {
            PipelineArtifactStore.deleteAll()
            PipelineDiagnostics.clear()
        }

        PipelineDiagnostics.recordAppEvent(
            "debug_bootstrap",
            metadata: [
                "forcePro": "\(CutSenseDebugRuntime.forceProEntitlement)",
                "forcePipeline": "\(CutSenseDebugRuntime.forcePipelineExecution)",
                "autorunPipeline": "\(CutSenseDebugRuntime.autorunPipelineOnLaunch)",
                "enableFoundationModelsSmartAnalysis": "\(CutSenseDebugRuntime.enableFoundationModelsSmartAnalysis)",
                "forceHeuristicSmartAnalysis": "\(CutSenseDebugRuntime.forceHeuristicSmartAnalysis)",
                "exportEvenWhenQualityFails": "\(CutSenseDebugRuntime.exportEvenWhenQualityFails)"
            ]
        )

        if CutSenseDebugRuntime.autorunPipelineOnLaunch {
            await PipelineDebugRunner.runFromLaunchEnvironment()
        }
        #endif
    }
}
