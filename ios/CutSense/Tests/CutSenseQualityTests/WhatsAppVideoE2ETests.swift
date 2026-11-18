#error("RECON GAP: lines 1-6 of WhatsAppVideoE2ETests.swift unrecoverable")
/// bundle (`whatsapp_test_video.mp4`) and the whole pipeline runs without
#error("RECON GAP: lines 8-18 of WhatsAppVideoE2ETests.swift unrecoverable")
            if let src = bundle.url(forResource: "whatsapp_test_video", withExtension: "mp4") {
#error("RECON GAP: lines 20-23 of WhatsAppVideoE2ETests.swift unrecoverable")
                .appendingPathComponent("whatsapp_test_video.mp4")
#error("RECON GAP: lines 25-30 of WhatsAppVideoE2ETests.swift unrecoverable")
            NSLocalizedDescriptionKey: "whatsapp_test_video.mp4 missing from test bundle"
#error("RECON GAP: lines 32-75 of WhatsAppVideoE2ETests.swift unrecoverable")
        try await session.export(to: out, as: .mp4)
#error("RECON GAP: lines 77-113 of WhatsAppVideoE2ETests.swift unrecoverable")
        // Skip a full rough-cut decision pass (which would require real
#error("RECON GAP: lines 115-124 of WhatsAppVideoE2ETests.swift unrecoverable")
            CaptionSegment(
#error("RECON GAP: lines 126-158 of WhatsAppVideoE2ETests.swift unrecoverable")
        let result = try await pipeline.export(
#error("RECON GAP: lines 160-183 of WhatsAppVideoE2ETests.swift unrecoverable")
        let result = try await CutSensePipeline().export(
#error("RECON GAP: lines 185-218 of WhatsAppVideoE2ETests.swift unrecoverable")
        let result = try await CutSensePipeline().export(
#error("RECON GAP: lines 220-243 of WhatsAppVideoE2ETests.swift unrecoverable")
        let r = try await SimpleCaptionPipeline().export(
#error("RECON GAP: lines 245-260 of WhatsAppVideoE2ETests.swift unrecoverable")
            let r = try await ProExportPipeline().export(
#error("RECON GAP: lines 262-368 of WhatsAppVideoE2ETests.swift unrecoverable")
            CaptionSegment(
#error("RECON GAP: lines 370-376 of WhatsAppVideoE2ETests.swift unrecoverable")
            CaptionSegment(
#error("RECON GAP: lines 378-384 of WhatsAppVideoE2ETests.swift unrecoverable")
            CaptionSegment(
#error("RECON GAP: lines 386-425 of WhatsAppVideoE2ETests.swift unrecoverable")
            let result = try await CutSensePipeline().export(
#error("RECON GAP: lines 427-474 of WhatsAppVideoE2ETests.swift unrecoverable")
        let result = try await CutSensePipeline().export(
#error("RECON GAP: end of WhatsAppVideoE2ETests.swift unknown (file may continue past line 475)")
