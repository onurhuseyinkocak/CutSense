#error("RECON GAP: lines 1-80 of ColorGradingEngine.swift unrecoverable")
        let lutDir = resourceURL.appendingPathComponent("Resources/EditingAssets/color_grades")
#error("RECON GAP: lines 82-102 of ColorGradingEngine.swift unrecoverable")
            // Skip empty lines, comments, and metadata keywords
#error("RECON GAP: lines 104-132 of ColorGradingEngine.swift unrecoverable")
        let effectiveIntensity = intensity ?? grade.intensity
#error("RECON GAP: lines 134-136 of ColorGradingEngine.swift unrecoverable")
        result = applyTechnicalCorrection(result, grade: grade, intensity: effectiveIntensity)
        result = applyCreativeLook(result, definition: definition, intensity: effectiveIntensity)
#error("RECON GAP: lines 139-249 of ColorGradingEngine.swift unrecoverable")
    static func defaultGrade(for style: EditingStyle) -> ColorGrade {
#error("RECON GAP: end of ColorGradingEngine.swift unknown (file may continue past line 250)")
