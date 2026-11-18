import Foundation
import Speech

// MARK: - Enhanced Transcription Pipeline

/// Multi-stage verification pipeline for maximum caption accuracy.
/// Uses Apple Speech framework as primary, with 6 verification passes.
/// Supports Turkish, English, and multilingual speech.
enum EnhancedTranscriptionService {

    // MARK: - Configuration

    struct TranscriptionConfig: Sendable {
        let locale: Locale
        let language: String
        let customVocabulary: [String]
        let enableSecondPass: Bool
        let lowConfidenceThreshold: Float

        init(
            locale: Locale = Locale(identifier: "en-US"),
            language: String = "en",
            customVocabulary: [String] = [],
            enableSecondPass: Bool = true,
            lowConfidenceThreshold: Float = 0.6
        ) {
            self.locale = locale
            self.language = language
            self.customVocabulary = customVocabulary
            self.enableSecondPass = enableSecondPass
            self.lowConfidenceThreshold = lowConfidenceThreshold
        }
    }

    // MARK: - Result

    struct TranscriptionPipelineResult: Sendable {
        let words: [TranscriptWord]
        let fullText: String
        let language: String
        let averageConfidence: Float
        let lowConfidenceCount: Int
        let passCount: Int
        let corrections: [TranscriptCorrection]

        struct TranscriptCorrection: Sendable {
            let wordID: UUID
            let originalText: String
            let correctedText: String
            let reason: CorrectionReason
            let alternatives: [String]

            enum CorrectionReason: String, Sendable {
                case punctuation
                case capitalization
                case numberFormatting
                case lowConfidenceReplacement
                case semanticConsistency
            }
        }
    }

    // MARK: - Main Pipeline

    /// Run the full 6-pass transcription pipeline.
    static func transcribe(
        url: URL,
        config: TranscriptionConfig
    ) async throws -> TranscriptionPipelineResult {
        // PASS 1: Apple Speech transcription
        let pass1 = try await pass1_appleSpeechTranscription(url: url, config: config)

        // PASS 2: Language-aware normalization
        let pass2 = pass2_languageNormalization(words: pass1, config: config)

        // PASS 3: Punctuation and casing
        let pass3 = pass3_punctuationAndCasing(words: pass2, config: config)

        // PASS 4: Low-confidence detection
        let pass4 = pass4_lowConfidenceDetection(words: pass3, config: config)

        // PASS 5: Optional second recognition pass for suspicious regions
        let pass5: [TranscriptWord]
        if config.enableSecondPass {
            pass5 = try await pass5_secondRecognitionPass(
                words: pass4, url: url, config: config
            )
        } else {
            pass5 = pass4
        }

        // PASS 6: Semantic consistency check
        let (pass6, corrections) = pass6_semanticConsistency(words: pass5, config: config)

        let fullText = pass6.map(\.text).joined(separator: " ")
        let avgConfidence = pass6.isEmpty ? 0 : pass6.reduce(0) { $0 + $1.confidence } / Float(pass6.count)
        let lowCount = pass6.filter(\.isLowConfidence).count

        return TranscriptionPipelineResult(
            words: pass6,
            fullText: fullText,
            language: config.language,
            averageConfidence: avgConfidence,
            lowConfidenceCount: lowCount,
            passCount: 6,
            corrections: corrections
        )
    }

    // MARK: - PASS 1: Apple Speech Transcription

    private static func pass1_appleSpeechTranscription(
        url: URL,
        config: TranscriptionConfig
    ) async throws -> [TranscriptWord] {
        let recognizer = SFSpeechRecognizer(locale: config.locale)
        guard let recognizer else {
            throw TranscriptionError.recognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        // customWords is only available on newer iOS versions for SFSpeechURLRecognitionRequest
        // On older versions, custom vocabulary is not supported for URL-based recognition

        // Extract the data we need inside the closure to avoid Sendable issues
        struct ExtractedResult: Sendable {
            let fullText: String
            let segmentTexts: [(text: String, start: Double, end: Double)]
            let wordSegments: [(substring: String, timestamp: Double, duration: Double, confidence: Float)]
            let bestText: String
        }

        let extracted: ExtractedResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ExtractedResult, Error>) in
            let lock = NSLock()
            var hasResumed = false
            let task = recognizer.recognitionTask(with: request) { localResult, error in
                lock.lock()
                guard !hasResumed else { lock.unlock(); return }
                if let error {
                    hasResumed = true
                    lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                guard let localResult, localResult.isFinal else { lock.unlock(); return }
                hasResumed = true
                lock.unlock()
                // Extract all needed data before crossing the actor boundary
                let best = localResult.bestTranscription
                let segTexts = best.segments.map { seg in
                    (text: seg.substring, start: seg.timestamp, end: seg.timestamp + seg.duration)
                }
                let wordSegs: [(substring: String, timestamp: Double, duration: Double, confidence: Float)] = best.segments.map { seg in
                    (substring: seg.substring, timestamp: seg.timestamp, duration: seg.duration, confidence: Float(seg.confidence))
#error("RECON GAP: lines 161-173 of EnhancedTranscriptionService.swift unrecoverable")
            throw TranscriptionError.emptyTranscript
#error("RECON GAP: lines 175-402 of EnhancedTranscriptionService.swift unrecoverable")
    // MARK: - Errors
#error("RECON GAP: lines 404-404 of EnhancedTranscriptionService.swift unrecoverable")
    enum TranscriptionError: LocalizedError {
#error("RECON GAP: lines 406-408 of EnhancedTranscriptionService.swift unrecoverable")
        case authorizationDenied
#error("RECON GAP: lines 410-410 of EnhancedTranscriptionService.swift unrecoverable")
        var errorDescription: String? {
#error("RECON GAP: lines 412-412 of EnhancedTranscriptionService.swift unrecoverable")
            case .recognizerUnavailable: return "Speech recognizer unavailable for this locale."
#error("RECON GAP: lines 414-415 of EnhancedTranscriptionService.swift unrecoverable")
            case .authorizationDenied: return "Speech recognition authorization denied."
#error("RECON GAP: end of EnhancedTranscriptionService.swift unknown (file may continue past line 416)")
