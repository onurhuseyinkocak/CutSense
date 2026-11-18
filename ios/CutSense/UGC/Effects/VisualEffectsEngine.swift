import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Visual Effects Engine

/// Procedural GPU effects — prefer these over large bundled video assets.
/// All effect parameters are editable. AI uses effects sparingly.
/// Maximum visual intensity is controlled by the chosen Editing Style.
enum VisualEffectsEngine {

    // MARK: - Helper: Blend using CIFilterNamedImage

    /// Apply a soft-light-like blend using available Core Image blend filters.
    /// Core Image doesn't have softLightBlendMode, so we simulate it with overlay blend.
    private static func blendOverlay(_ foreground: CIImage, background: CIImage) -> CIImage {
        let blend = CIFilter.overlayBlendMode()
        blend.inputImage = foreground
        blend.backgroundImage = background
        return blend.outputImage ?? background
    }

    // MARK: - Effect Definitions

    struct EffectDefinition: Sendable {
        let type: EffectEvent.EffectType
        let displayName: String
        let defaultParameters: [String: Double]
        let parameterRanges: [String: ClosedRange<Double>]

        static func definition(for type: EffectEvent.EffectType) -> EffectDefinition {
            switch type {
            case .filmGrain:
                EffectDefinition(
                    type: .filmGrain,
                    displayName: "Film Grain",
                    defaultParameters: ["intensity": 0.3, "size": 1.0, "softness": 0.5],
                    parameterRanges: ["intensity": 0...1, "size": 0.5...2.0, "softness": 0...1]
                )
            case .bloom:
                EffectDefinition(
                    type: .bloom,
                    displayName: "Bloom",
                    defaultParameters: ["radius": 10, "threshold": 0.6, "intensity": 0.4],
                    parameterRanges: ["radius": 2...30, "threshold": 0.3...0.9, "intensity": 0...1]
                )
            case .glow:
                EffectDefinition(
                    type: .glow,
                    displayName: "Glow",
                    defaultParameters: ["radius": 8, "intensity": 0.3],
                    parameterRanges: ["radius": 2...25, "intensity": 0...1]
                )
            case .vignette:
                EffectDefinition(
                    type: .vignette,
                    displayName: "Vignette",
                    defaultParameters: ["intensity": 0.4, "radius": 0.8],
                    parameterRanges: ["intensity": 0...1, "radius": 0.3...1.5]
                )
            case .chromaticAberration:
                EffectDefinition(
                    type: .chromaticAberration,
                    displayName: "Chromatic Aberration",
                    defaultParameters: ["offset": 2.0, "intensity": 0.3],
                    parameterRanges: ["offset": 0.5...8.0, "intensity": 0...1]
                )
            case .motionBlur:
                EffectDefinition(
                    type: .motionBlur,
                    displayName: "Motion Blur",
                    defaultParameters: ["angle": 0, "radius": 5, "intensity": 0.4],
                    parameterRanges: ["angle": 0...360, "radius": 1...20, "intensity": 0...1]
                )
            case .directionalBlur:
                EffectDefinition(
                    type: .directionalBlur,
                    displayName: "Directional Blur",
                    defaultParameters: ["angle": 0, "radius": 4, "intensity": 0.3],
                    parameterRanges: ["angle": 0...360, "radius": 1...15, "intensity": 0...1]
                )
            case .flash:
                EffectDefinition(
                    type: .flash,
                    displayName: "Flash",
                    defaultParameters: ["duration": 0.15, "intensity": 0.8],
                    parameterRanges: ["duration": 0.05...0.5, "intensity": 0...1]
                )
            case .cameraShake:
                EffectDefinition(
                    type: .cameraShake,
                    displayName: "Camera Shake",
                    defaultParameters: ["intensity": 0.3, "frequency": 8, "duration": 0.3],
                    parameterRanges: ["intensity": 0...1, "frequency": 2...20, "duration": 0.1...1.0]
                )
            case .lightLeak:
                EffectDefinition(
                    type: .lightLeak,
                    displayName: "Light Leak",
                    defaultParameters: ["intensity": 0.4, "warmth": 0.6],
                    parameterRanges: ["intensity": 0...1, "warmth": 0...1]
                )
            case .dust:
                EffectDefinition(
                    type: .dust,
                    displayName: "Dust",
                    defaultParameters: ["intensity": 0.2, "size": 1.0],
                    parameterRanges: ["intensity": 0...1, "size": 0.5...2.0]
                )
            case .filmBurn:
                EffectDefinition(
                    type: .filmBurn,
                    displayName: "Film Burn",
                    defaultParameters: ["intensity": 0.5, "position": 0.5],
                    parameterRanges: ["intensity": 0...1, "position": 0...1]
                )
            case .softFocus:
                EffectDefinition(
                    type: .softFocus,
                    displayName: "Soft Focus",
                    defaultParameters: ["radius": 6, "intensity": 0.3],
                    parameterRanges: ["radius": 2...15, "intensity": 0...1]
                )
            }
        }
    }

    // MARK: - Apply Effect

    static func applyEffect(
        _ image: CIImage,
        effect: EffectEvent
    ) -> CIImage {
        switch effect.type {
        case .filmGrain:
            return applyFilmGrain(image, params: effect.parameters, intensity: effect.intensity)
        case .bloom:
            return applyBloom(image, params: effect.parameters, intensity: effect.intensity)
        case .glow:
            return applyGlow(image, params: effect.parameters, intensity: effect.intensity)
        case .vignette:
            return applyVignette(image, params: effect.parameters, intensity: effect.intensity)
        case .chromaticAberration:
            return applyChromaticAberration(image, params: effect.parameters, intensity: effect.intensity)
        case .motionBlur, .directionalBlur:
            return applyDirectionalBlur(image, params: effect.parameters, intensity: effect.intensity)
        case .flash:
            return applyFlash(image, params: effect.parameters, intensity: effect.intensity)
        case .cameraShake:
            return image  // Camera shake is handled by transform, not CIFilter
        case .lightLeak:
            return applyLightLeak(image, params: effect.parameters, intensity: effect.intensity)
        case .dust:
            return applyDust(image, params: effect.parameters, intensity: effect.intensity)
        case .filmBurn:
            return applyFilmBurn(image, params: effect.parameters, intensity: effect.intensity)
        case .softFocus:
            return applySoftFocus(image, params: effect.parameters, intensity: effect.intensity)
        }
    }

    // MARK: - Individual Effect Implementations

    private static func applyFilmGrain(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        let filter = CIFilter.randomGenerator()
        guard let noise = filter.outputImage else { return image }

        // Color-adjust the noise to be gray
        let colorFilter = CIFilter.colorMatrix()
        colorFilter.inputImage = noise
        colorFilter.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        colorFilter.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        colorFilter.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        guard let grayNoise = colorFilter.outputImage else { return image }

        // Scale the noise
        let scale = params["size"] ?? 1.0
        let scaledNoise = grayNoise.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Blend with original using overlay blend
        let blended = blendOverlay(scaledNoise.cropped(to: image.extent), background: image)

        // Adjust opacity
        let opacityFilter = CIFilter.colorMatrix()
        opacityFilter.inputImage = blended
        let alpha = Float(intensity * (params["intensity"] ?? 0.3))
        opacityFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))
        return opacityFilter.outputImage ?? blended
    }

    private static func applyBloom(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        let filter = CIFilter.bloom()
        filter.inputImage = image
        filter.radius = Float(params["radius"] ?? 10)
        filter.intensity = Float(intensity * (params["intensity"] ?? 0.4))
        return filter.outputImage ?? image
    }

    private static func applyGlow(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        let filter = CIFilter.bloom()
        filter.inputImage = image
        filter.radius = Float(params["radius"] ?? 8)
        filter.intensity = Float(intensity * (params["intensity"] ?? 0.3) * 0.5)
        guard let bloomed = filter.outputImage else { return image }

        let blend = CIFilter.screenBlendMode()
        blend.inputImage = bloomed
        blend.backgroundImage = image
        return blend.outputImage ?? image
    }

    private static func applyVignette(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        let filter = CIFilter.vignette()
        filter.inputImage = image
        filter.intensity = Float(intensity * (params["intensity"] ?? 0.4) * 2)
        filter.radius = Float(params["radius"] ?? 0.8)
        return filter.outputImage ?? image
    }

    private static func applyChromaticAberration(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        let offset = (params["offset"] ?? 2.0) * intensity
        let redShift = image.transformed(by: CGAffineTransform(translationX: offset, y: 0))
        let blueShift = image.transformed(by: CGAffineTransform(translationX: -offset, y: 0))

        let redFilter = CIFilter.maskToAlpha()
        redFilter.inputImage = redShift
        guard let redChannel = redFilter.outputImage else { return image }

        let blueFilter = CIFilter.maskToAlpha()
        blueFilter.inputImage = blueShift
        guard let blueChannel = blueFilter.outputImage else { return image }

        let addFilter = CIFilter.additionCompositing()
        addFilter.inputImage = redChannel
        addFilter.backgroundImage = blueChannel
        guard let aberrated = addFilter.outputImage else { return image }

        return blendOverlay(aberrated, background: image)
    }

    private static func applyDirectionalBlur(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        let filter = CIFilter.motionBlur()
        filter.inputImage = image
        filter.angle = Float(params["angle"] ?? 0)
        filter.radius = Float((params["radius"] ?? 5) * intensity)
        return filter.outputImage ?? image
    }

    private static func applyFlash(_ image: CIImage, params: [String: Double], intensity: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIExposureAdjust") else { return image }
#error("RECON GAP: lines 251-310 of VisualEffectsEngine.swift unrecoverable")
    static func defaultEffects(for style: EditingStyle) -> [EffectEvent.EffectType] {
#error("RECON GAP: lines 312-325 of VisualEffectsEngine.swift unrecoverable")
    static func maxIntensity(for style: EditingStyle) -> Double {
#error("RECON GAP: end of VisualEffectsEngine.swift unknown (file may continue past line 326)")
