import Foundation
import Accelerate

enum AudioQualityGuard {
    struct QualityReport: Sendable {
        let peakDB: Float
        let averageDB: Float
        let isClipping: Bool
        let isTooQuiet: Bool
        let dynamicRange: Float
        let passed: Bool
    }

    private static let clippingThreshold: Float = -1.0 // dBFS
    private static let tooQuietThreshold: Float = -30.0 // dBFS
    private static let minDynamicRange: Float = 6.0 // dB

    static func analyze(audioAnalysis: AudioAnalysisResult) -> QualityReport {
        let audibleEnergies = audioAnalysis.segments
            .filter { $0.type != .silence }
            .map(\.energy)
            .filter { $0 > 0 }

        guard !audibleEnergies.isEmpty else {
            return makeReport(peakLinear: audioAnalysis.peakEnergy, averageLinear: audioAnalysis.averageEnergy)
        }

        let peak = max(audioAnalysis.peakEnergy, audibleEnergies.max() ?? 0)
        let squareMean = audibleEnergies.reduce(Float(0)) { $0 + $1 * $1 } / Float(audibleEnergies.count)
        return makeReport(peakLinear: peak, averageLinear: sqrt(squareMean))
    }

    static func analyze(samples: [Float]) -> QualityReport {
        guard !samples.isEmpty else {
            return QualityReport(
                peakDB: -Float.infinity,
                averageDB: -Float.infinity,
                isClipping: false,
                isTooQuiet: true,
                dynamicRange: 0,
                passed: false
            )
        }

        // Peak level
        var peak: Float = 0
        vDSP_maxv(samples, 1, &peak, vDSP_Length(samples.count))
        var negPeak: Float = 0
        var absSamples = [Float](repeating: 0, count: samples.count)
        vDSP_vabs(samples, 1, &absSamples, 1, vDSP_Length(samples.count))
        vDSP_maxv(absSamples, 1, &negPeak, vDSP_Length(samples.count))
        let truePeak = max(peak, negPeak)
        let peakDB = truePeak > 0 ? 20 * log10(truePeak) : -Float.infinity

        // RMS average level
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let averageDB = rms > 0 ? 20 * log10(rms) : -Float.infinity

        return makeReport(peakDB: peakDB, averageDB: averageDB)
    }

    private static func makeReport(peakLinear: Float, averageLinear: Float) -> QualityReport {
        let peakDB = peakLinear > 0 ? 20 * log10(peakLinear) : -Float.infinity
        let averageDB = averageLinear > 0 ? 20 * log10(averageLinear) : -Float.infinity
        return makeReport(peakDB: peakDB, averageDB: averageDB)
    }

    private static func makeReport(peakDB: Float, averageDB: Float) -> QualityReport {
        let dynamicRange = peakDB - averageDB
        let isClipping = peakDB > clippingThreshold
        let isTooQuiet = averageDB < tooQuietThreshold

        let passed = !isClipping && !isTooQuiet && dynamicRange >= minDynamicRange

        return QualityReport(
            peakDB: peakDB,
            averageDB: averageDB,
            isClipping: isClipping,
            isTooQuiet: isTooQuiet,
            dynamicRange: dynamicRange,
            passed: passed
        )
    }
}
