#error("RECON GAP: lines 1-4 of SoundDesignEngine.swift unrecoverable")
/// Places sound effects corresponding to actual visual or semantic events.
/// Automatically ducks effects under dialogue. Dialogue always has priority.
#error("RECON GAP: lines 7-18 of SoundDesignEngine.swift unrecoverable")
        init(
#error("RECON GAP: lines 20-46 of SoundDesignEngine.swift unrecoverable")
            case punchIn
            case punchOut
#error("RECON GAP: lines 49-63 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .softWhoosh, volume: 0.3, duration: 0.4, fadeIn: 0.02, fadeOut: 0.15),
#error("RECON GAP: lines 65-68 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .whoosh, volume: 0.5, duration: 0.3, fadeIn: 0.01, fadeOut: 0.1),
                SFXRule(trigger: .punchOut, category: .whoosh, volume: 0.4, duration: 0.3, fadeIn: 0.01, fadeOut: 0.1),
#error("RECON GAP: lines 71-78 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .softWhoosh, volume: 0.25, duration: 0.5, fadeIn: 0.05, fadeOut: 0.2),
#error("RECON GAP: lines 80-84 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .softWhoosh, volume: 0.2, duration: 0.4, fadeIn: 0.02, fadeOut: 0.15),
#error("RECON GAP: lines 86-89 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .softWhoosh, volume: 0.3, duration: 0.5, fadeIn: 0.05, fadeOut: 0.2),
#error("RECON GAP: lines 91-95 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .whoosh, volume: 0.4, duration: 0.3, fadeIn: 0.01, fadeOut: 0.1),
#error("RECON GAP: lines 97-102 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .softWhoosh, volume: 0.2, duration: 0.4, fadeIn: 0.02, fadeOut: 0.15),
#error("RECON GAP: lines 104-108 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .softWhoosh, volume: 0.15, duration: 0.4, fadeIn: 0.02, fadeOut: 0.15),
#error("RECON GAP: lines 110-113 of SoundDesignEngine.swift unrecoverable")
                SFXRule(trigger: .punchIn, category: .whoosh, volume: 0.6, duration: 0.3, fadeIn: 0.01, fadeOut: 0.1),
                SFXRule(trigger: .punchOut, category: .whoosh, volume: 0.5, duration: 0.3, fadeIn: 0.01, fadeOut: 0.1),
#error("RECON GAP: lines 116-162 of SoundDesignEngine.swift unrecoverable")
            case .punchIn:
                for motion in motionEvents where motion.type == .punchIn || motion.type == .microPush {
#error("RECON GAP: lines 165-169 of SoundDesignEngine.swift unrecoverable")
            case .punchOut:
                for motion in motionEvents where motion.type == .punchOut || motion.type == .microPull {
#error("RECON GAP: lines 172-266 of SoundDesignEngine.swift unrecoverable")
            #if DEBUG
#error("RECON GAP: end of SoundDesignEngine.swift unknown (file may continue past line 267)")
