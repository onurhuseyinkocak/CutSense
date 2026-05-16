import Speech
import AVFoundation

struct TranscriptSegment: Sendable, Identifiable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Float
    var segmentType: SegmentType

    enum SegmentType: String, Sendable {
        case speech
        case silence
        case filler
        case suspectedRestart = "suspected_restart"
        case suspectedDuplicate = "suspected_duplicate"
        case contentSentence = "content_sentence"
    }
}

struct TranscriptionResult: Sendable {
    let fullText: String
    let segments: [TranscriptSegment]
    let language: String
    let overallConfidence: Float
}

actor SpeechTranscriptionService {
    enum TranscriptionError: Error, LocalizedError {
        case notAuthorized
        case noRecognizer
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition not authorized."
            case .noRecognizer: "Speech recognizer not available."
            case .recognitionFailed(let msg): "Recognition failed: \(msg)"
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(url: URL, locale: Locale = Locale(identifier: "tr-TR")) async throws -> TranscriptionResult {
        guard await requestAuthorization() else {
            throw TranscriptionError.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            // Fallback to English if Turkish not available
            guard let fallback = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), fallback.isAvailable else {
                throw TranscriptionError.noRecognizer
            }
            return try await performRecognition(recognizer: fallback, url: url, language: "en")
        }

        return try await performRecognition(recognizer: recognizer, url: url, language: locale.language.languageCode?.identifier ?? "tr")
    }

    private struct RawWord: Sendable {
        let substring: String
        let timestamp: Double
        let duration: Double
        let confidence: Float
    }

    private struct RawRecognitionData: Sendable {
        let formattedString: String
        let words: [RawWord]
    }

    private func performRecognition(recognizer: SFSpeechRecognizer, url: URL, language: String) async throws -> TranscriptionResult {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        // Extract Sendable data inside callback, before crossing actor boundary
        let rawData: RawRecognitionData = try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                } else if let result, result.isFinal {
                    let transcription = result.bestTranscription
                    let words = transcription.segments.map { seg in
                        RawWord(
                            substring: seg.substring,
                            timestamp: seg.timestamp,
                            duration: seg.duration,
                            confidence: seg.confidence
                        )
                    }
                    let data = RawRecognitionData(
                        formattedString: transcription.formattedString,
                        words: words
                    )
                    continuation.resume(returning: data)
                }
            }
        }

        let segments = buildSegments(from: rawData.words)
        let avgConfidence: Float = segments.isEmpty ? 0 : segments.reduce(Float(0)) { $0 + $1.confidence } / Float(segments.count)

        return TranscriptionResult(
            fullText: rawData.formattedString,
            segments: segments,
            language: language,
            overallConfidence: avgConfidence
        )
    }

    private func buildSegments(from words: [RawWord]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentWords: [RawWord] = []
        var chunkStart: Double?

        for word in words {
            if chunkStart == nil {
                chunkStart = word.timestamp
            }
            currentWords.append(word)

            let wordCount = currentWords.count
            let lastWord = word.substring

            let isEndOfPhrase = lastWord.hasSuffix(".") || lastWord.hasSuffix(",") ||
                                lastWord.hasSuffix("?") || lastWord.hasSuffix("!") ||
                                lastWord.hasSuffix("...") || wordCount >= 7

            if isEndOfPhrase && wordCount >= 3, let start = chunkStart {
                let text = currentWords.map(\.substring).joined(separator: " ")
                let end = word.timestamp + word.duration
                let avgConf = currentWords.reduce(Float(0)) { $0 + $1.confidence } / Float(currentWords.count)

                segments.append(TranscriptSegment(
                    startTime: start,
                    endTime: end,
                    text: text,
                    confidence: avgConf,
                    segmentType: .speech
                ))

                currentWords = []
                chunkStart = nil
            }
        }

        if !currentWords.isEmpty, let start = chunkStart {
            let lastWord = currentWords.last!
            let text = currentWords.map(\.substring).joined(separator: " ")
            segments.append(TranscriptSegment(
                startTime: start,
                endTime: lastWord.timestamp + lastWord.duration,
                text: text,
                confidence: currentWords.reduce(Float(0)) { $0 + $1.confidence } / Float(currentWords.count),
                segmentType: .speech
            ))
        }

        return segments
    }
}
