#error("RECON GAP: lines 1-5 of SmartMotionEngine.swift unrecoverable")
/// Uses native transforms (never AI-generated video for zoom effects).
#error("RECON GAP: lines 7-18 of SmartMotionEngine.swift unrecoverable")
        static let punchIn = MotionPrimitive(type: .punchIn, duration: 0.5, intensity: 0.35, easeIn: 0.2, easeOut: 0.3)
        static let punchOut = MotionPrimitive(type: .punchOut, duration: 0.5, intensity: 0.35, easeIn: 0.2, easeOut: 0.3)
#error("RECON GAP: lines 21-22 of SmartMotionEngine.swift unrecoverable")
        static let kenBurns = MotionPrimitive(type: .kenBurns, duration: 5.0, intensity: 0.12, easeIn: 1.0, easeOut: 1.0)
#error("RECON GAP: lines 24-35 of SmartMotionEngine.swift unrecoverable")
        /// Maximum number of consecutive zoom-ins or zoom-outs.
#error("RECON GAP: lines 37-59 of SmartMotionEngine.swift unrecoverable")
        let lastSameType = recentMotions.last(where: { $0.type == .punchIn || $0.type == .punchOut })
#error("RECON GAP: lines 61-69 of SmartMotionEngine.swift unrecoverable")
        let allZoomIn = recentZooms.allSatisfy { $0.type == .punchIn || $0.type == .slowZoomIn }
        let allZoomOut = recentZooms.allSatisfy { $0.type == .punchOut || $0.type == .slowZoomOut }
#error("RECON GAP: lines 72-76 of SmartMotionEngine.swift unrecoverable")
            // Emphasis moments get punch-in
#error("RECON GAP: lines 78-80 of SmartMotionEngine.swift unrecoverable")
                type: .punchIn,
#error("RECON GAP: lines 82-98 of SmartMotionEngine.swift unrecoverable")
            // Medium clips get slow zoom
#error("RECON GAP: lines 100-111 of SmartMotionEngine.swift unrecoverable")
            let types: [MotionEvent.MotionType] = [.panLeft, .panRight, .kenBurns]
#error("RECON GAP: lines 113-124 of SmartMotionEngine.swift unrecoverable")
            // Very long clips get Ken Burns
#error("RECON GAP: lines 126-128 of SmartMotionEngine.swift unrecoverable")
                type: .kenBurns,
#error("RECON GAP: lines 130-131 of SmartMotionEngine.swift unrecoverable")
                reason: "Very long clip Ken Burns",
#error("RECON GAP: lines 133-160 of SmartMotionEngine.swift unrecoverable")
        case .punchIn:
#error("RECON GAP: lines 162-164 of SmartMotionEngine.swift unrecoverable")
        case .punchOut:
#error("RECON GAP: lines 166-176 of SmartMotionEngine.swift unrecoverable")
        case .kenBurns:
            // Ken Burns: slow zoom + slight pan
#error("RECON GAP: end of SmartMotionEngine.swift unknown (file may continue past line 178)")
