#error("RECON GAP: lines 1-12 of EnhancedCaptionEngine.swift unrecoverable")
    struct CaptionPreset: Sendable, Identifiable {
        let id: EDLCaptionStyleName
#error("RECON GAP: lines 15-48 of EnhancedCaptionEngine.swift unrecoverable")
        enum CaptionAlignment: String, Sendable {
#error("RECON GAP: lines 50-69 of EnhancedCaptionEngine.swift unrecoverable")
            case none, pop, slide, bounce, typewriter, zoom
#error("RECON GAP: lines 71-73 of EnhancedCaptionEngine.swift unrecoverable")
            case none, fade, slideUp, springBounce, zoomIn, typewriter
#error("RECON GAP: lines 75-103 of EnhancedCaptionEngine.swift unrecoverable")
    static func preset(for name: EDLCaptionStyleName) -> CaptionPreset {
#error("RECON GAP: lines 105-190 of EnhancedCaptionEngine.swift unrecoverable")
        wordAnimation: .zoom,
        entryAnimation: .zoomIn,
#error("RECON GAP: lines 193-231 of EnhancedCaptionEngine.swift unrecoverable")
    // MARK: - Editorial
#error("RECON GAP: lines 233-235 of EnhancedCaptionEngine.swift unrecoverable")
        displayName: "Editorial",
#error("RECON GAP: lines 237-439 of EnhancedCaptionEngine.swift unrecoverable")
        entryAnimation: .zoomIn,
#error("RECON GAP: lines 441-531 of EnhancedCaptionEngine.swift unrecoverable")
        wordAnimation: .zoom,
        entryAnimation: .zoomIn,
#error("RECON GAP: lines 534-639 of EnhancedCaptionEngine.swift unrecoverable")
enum CaptionSegmentationEngine {
#error("RECON GAP: lines 641-656 of EnhancedCaptionEngine.swift unrecoverable")
        init(
#error("RECON GAP: lines 658-823 of EnhancedCaptionEngine.swift unrecoverable")
        return EDLCaptionSegment(
#error("RECON GAP: end of EnhancedCaptionEngine.swift unknown (file may continue past line 824)")
