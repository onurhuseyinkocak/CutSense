#error("RECON GAP: lines 1-7 of VideoOverlayCompositor.swift unrecoverable")
/// Composites video overlay effects (film burns, lens flares, etc.) onto the main video.
#error("RECON GAP: lines 9-32 of VideoOverlayCompositor.swift unrecoverable")
        let dir = resourceURL.appendingPathComponent("Resources/EditingAssets/visual_effects/\(type.directory)")
#error("RECON GAP: lines 34-47 of VideoOverlayCompositor.swift unrecoverable")
    /// Apply a video overlay effect using CIFilter blending.
#error("RECON GAP: lines 49-113 of VideoOverlayCompositor.swift unrecoverable")
    /// Apply a built-in CIFilter overlay effect based on EffectEvent type.
    /// Only handles lightLeak and filmBurn; other types use VisualEffectsEngine.
#error("RECON GAP: lines 116-117 of VideoOverlayCompositor.swift unrecoverable")
        effect: EffectEvent
#error("RECON GAP: lines 119-119 of VideoOverlayCompositor.swift unrecoverable")
        switch effect.type {
#error("RECON GAP: lines 121-121 of VideoOverlayCompositor.swift unrecoverable")
            return applyLightLeakOverlay(baseImage: baseImage, intensity: effect.intensity)
#error("RECON GAP: lines 123-123 of VideoOverlayCompositor.swift unrecoverable")
            return applyFilmBurnOverlay(baseImage: baseImage, intensity: effect.intensity)
#error("RECON GAP: end of VideoOverlayCompositor.swift unknown (file may continue past line 124)")
