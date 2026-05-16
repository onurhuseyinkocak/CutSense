import CoreImage
import CoreImage.CIFilterBuiltins

enum FilterEngine {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply template color grading to a CIImage
    static func applyGrade(_ grade: TemplateConfig.ColorGrade, to image: CIImage) -> CIImage {
        var result = image

        // Color controls: saturation, brightness, contrast
        let needsColorControls = grade.saturation != 1.0 || grade.brightness != 0.0 || grade.contrast != 1.0
        if needsColorControls {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = result
            colorControls.saturation = grade.saturation
            colorControls.brightness = grade.brightness
            colorControls.contrast = grade.contrast
            if let output = colorControls.outputImage {
                result = output
            }
        }

        // Temperature/warmth shift
        if abs(grade.warmth) > 0.01 {
            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = result
            // Neutral is (6500, 0). Shift warm = higher temp, cool = lower
            let targetTemp = 6500.0 + Float(grade.warmth) * 2000.0
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: CGFloat(targetTemp), y: 0)
            if let output = tempTint.outputImage {
                result = output
            }
        }

        // Vignette
        if grade.vignetteIntensity > 0.01 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = result
            vignette.intensity = grade.vignetteIntensity
            vignette.radius = 2.0
            if let output = vignette.outputImage {
                result = output
            }
        }

        return result.cropped(to: image.extent)
    }

    /// Render a graded CIImage into a CVPixelBuffer
    static func render(_ ciImage: CIImage, to pixelBuffer: CVPixelBuffer) {
        ciContext.render(ciImage, to: pixelBuffer)
    }

    /// Convenience: grade a pixel buffer in place
    static func gradePixelBuffer(_ buffer: CVPixelBuffer, grade: TemplateConfig.ColorGrade) {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let graded = applyGrade(grade, to: ciImage)
        render(graded, to: buffer)
    }
}
