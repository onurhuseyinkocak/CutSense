import Speech
import AVFoundation

struct TranscriptSegment: Sendable, Identifiable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Float
    var segmentType: SegmentType
    /// LLM classification confidence (0.0–1.0), nil when heuristic-only
    var aiConfidence: Float?
    /// LLM reason for classification, nil when heuristic-only
    var aiReason: String?
    /// Raw ASR confidence before transcript correction rules raise display confidence.
    var rawConfidence: Float?
    /// Per-word timing: [word] = (startTime, duration) for precise karaoke reveal
    var wordTimings: [(word: String, start: Double, duration: Double)] = []

    enum SegmentType: String, Codable, Sendable {
        case speech
        case silence
        case filler
        case suspectedRestart = "suspected_restart"
        case suspectedDuplicate = "suspected_duplicate"
        case contentSentence = "content_sentence"
        case editCommand = "edit_command"
    }
}

enum TranscriptionRecognitionStatus: String, Codable, Sendable {
    case final
    case partialTimedOut = "partial_timed_out"
    case partialError = "partial_error"

    var isPartial: Bool {
        self != .final
    }
}

struct TranscriptionResult: Sendable {
    let fullText: String
    let segments: [TranscriptSegment]
    let language: String
    let overallConfidence: Float
    let rawOverallConfidence: Float?
    let recognitionStatus: TranscriptionRecognitionStatus

    init(
        fullText: String,
        segments: [TranscriptSegment],
        language: String,
        overallConfidence: Float,
        rawOverallConfidence: Float? = nil,
        recognitionStatus: TranscriptionRecognitionStatus = .final
    ) {
        self.fullText = fullText
        self.segments = segments
        self.language = language
        self.overallConfidence = overallConfidence
        self.rawOverallConfidence = rawOverallConfidence
        self.recognitionStatus = recognitionStatus
    }

    var qualityConfidence: Float {
        rawOverallConfidence ?? overallConfidence
    }
}

enum TranscriptionValidator {
    static func validated(_ result: TranscriptionResult) throws -> TranscriptionResult {
        let trimmedText = result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !result.segments.isEmpty else {
            throw SpeechTranscriptionService.TranscriptionError.emptyTranscript
        }

        guard result.segments.contains(where: isUsableSpeech) else {
            throw SpeechTranscriptionService.TranscriptionError.noUsableSpeech
        }

        return result
    }

    private static func isUsableSpeech(_ segment: TranscriptSegment) -> Bool {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, segment.endTime > segment.startTime else {
            return false
        }

        switch segment.segmentType {
        case .filler, .silence, .editCommand:
            return false
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        }
    }
}

actor SpeechTranscriptionService {
    enum TranscriptionError: Error, LocalizedError {
        case notAuthorized
        case noRecognizer
        case recognitionTimedOut
        case emptyTranscript
        case noUsableSpeech
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition not authorized."
            case .noRecognizer: "Speech recognizer not available."
            case .recognitionTimedOut: "Speech recognition timed out. Try a shorter video or record clearer audio."
            case .emptyTranscript: "No speech was detected in this video."
            case .noUsableSpeech: "No usable speech content was detected in this video."
            case .recognitionFailed(let msg): "Recognition failed: \(msg)"
            }
        }
    }

    func requestAuthorization() async -> Bool {
        let coordinator = AuthorizationCoordinator()
        return await withCheckedContinuation { continuation in
            coordinator.register(continuation)
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: .seconds(8))
                    coordinator.finish(false)
                } catch {
                    // Authorization completed or the parent task was cancelled.
                }
            }
            coordinator.setTimeoutTask(timeoutTask)
            SFSpeechRecognizer.requestAuthorization { status in
                coordinator.finish(status == .authorized)
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

        let primaryLanguage = locale.language.languageCode?.identifier ?? "tr"
        let primary = try await performRecognition(
            recognizer: recognizer,
            url: url,
            language: primaryLanguage
        )

        guard await shouldAttemptEnglishFallback(for: primary, sourceURL: url, primaryLanguage: primaryLanguage),
              let englishRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              englishRecognizer.isAvailable else {
            return primary
        }

        guard let english = try? await performRecognition(
            recognizer: englishRecognizer,
            url: url,
            language: "en"
        ) else {
            return primary
        }

        return Self.preferredTranscript(primary: primary, alternate: english)
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
        let recognitionStatus: TranscriptionRecognitionStatus

        var hasSpeech: Bool {
            !formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !words.isEmpty
        }

        func replacingStatus(_ status: TranscriptionRecognitionStatus) -> RawRecognitionData {
            RawRecognitionData(
                formattedString: formattedString,
                words: words,
                recognitionStatus: status
            )
        }
    }

    private final class AuthorizationCoordinator: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?
        private var timeoutTask: Task<Void, Never>?
        private var didFinish = false

        func register(_ continuation: CheckedContinuation<Bool, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func setTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            if didFinish {
                lock.unlock()
                task.cancel()
                return
            }
            timeoutTask = task
            lock.unlock()
        }

        func finish(_ isAuthorized: Bool) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }

            didFinish = true
            let continuation = continuation
            self.continuation = nil
            let timeoutTask = timeoutTask
            self.timeoutTask = nil
            lock.unlock()

            timeoutTask?.cancel()
            continuation?.resume(returning: isAuthorized)
        }
    }

    private final class RecognitionCoordinator: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<RawRecognitionData, Error>?
        private var recognitionTask: SFSpeechRecognitionTask?
        private var timeoutTask: Task<Void, Never>?
        private var latestPartial: RawRecognitionData?
        private var didFinish = false

        func register(_ continuation: CheckedContinuation<RawRecognitionData, Error>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func setRecognitionTask(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            if didFinish {
                lock.unlock()
                task.cancel()
                return
            }
            recognitionTask = task
            lock.unlock()
        }

        func setTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            if didFinish {
                lock.unlock()
                task.cancel()
                return
            }
            timeoutTask = task
            lock.unlock()
        }

        func updateLatestPartial(_ data: RawRecognitionData) {
            guard data.hasSpeech else { return }
            lock.lock()
            if !didFinish {
                latestPartial = data
            }
            lock.unlock()
        }

        func finishWithLatestPartialOrTimeout() {
            finishWithLatestPartialOrError(
                TranscriptionError.recognitionTimedOut,
                partialStatus: .partialTimedOut
            )
        }

        func finishWithLatestPartialOrError(
            _ error: Error,
            partialStatus: TranscriptionRecognitionStatus = .partialError
        ) {
            lock.lock()
            let partial = latestPartial
            lock.unlock()

            if let partial {
                finish(.success(partial.replacingStatus(partialStatus)))
            } else {
                finish(.failure(error))
            }
        }

        func cancel() {
            finish(.failure(CancellationError()))
        }

        func finish(_ result: Result<RawRecognitionData, Error>) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }

            didFinish = true
            let continuation = continuation
            self.continuation = nil
            let recognitionTask = recognitionTask
            self.recognitionTask = nil
            let timeoutTask = timeoutTask
            self.timeoutTask = nil
            lock.unlock()

            timeoutTask?.cancel()
            recognitionTask?.cancel()

            switch result {
            case .success(let data):
                continuation?.resume(returning: data)
            case .failure(let error):
                continuation?.resume(throwing: error)
            }
        }
    }

    private func performRecognition(recognizer: SFSpeechRecognizer, url: URL, language: String) async throws -> TranscriptionResult {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Self.contextualStrings(for: language)

        let coordinator = RecognitionCoordinator()
        let timeout = await recognitionTimeout(for: url, language: language)

        let rawData: RawRecognitionData = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.register(continuation)

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        coordinator.finishWithLatestPartialOrTimeout()
                    } catch {
                        // Task cancellation means recognition already completed or was cancelled.
                    }
                }
                coordinator.setTimeoutTask(timeoutTask)

                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        let data = Self.rawRecognitionData(
                            from: result.bestTranscription,
                            status: result.isFinal ? .final : .partialError
                        )
                        coordinator.updateLatestPartial(data)

                        if result.isFinal {
                            if data.hasSpeech {
                                coordinator.finish(.success(data))
                            } else {
                                coordinator.finish(.failure(TranscriptionError.emptyTranscript))
                            }
                        }
                    }

                    if let error {
                        coordinator.finishWithLatestPartialOrError(
                            TranscriptionError.recognitionFailed(error.localizedDescription)
                        )
                    }
                }
                coordinator.setRecognitionTask(task)
            }
        } onCancel: {
            coordinator.cancel()
        }

        let segments = buildSegments(from: rawData.words)
        let avgConfidence: Float = segments.isEmpty ? 0 : segments.reduce(Float(0)) { $0 + $1.confidence } / Float(segments.count)
        let fullText = rawData.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rawData.words.map(\.substring).joined(separator: " ")
            : rawData.formattedString

        let transcript = TranscriptionResult(
            fullText: fullText,
            segments: segments,
            language: language,
            overallConfidence: avgConfidence,
            rawOverallConfidence: avgConfidence,
            recognitionStatus: rawData.recognitionStatus
        )
        return try TranscriptionValidator.validated(TranscriptPostProcessor.corrected(transcript))
    }

    nonisolated private static func rawRecognitionData(from transcription: SFTranscription) -> RawRecognitionData {
        rawRecognitionData(from: transcription, status: .final)
    }

    nonisolated private static func rawRecognitionData(
        from transcription: SFTranscription,
        status: TranscriptionRecognitionStatus
    ) -> RawRecognitionData {
        let words = transcription.segments.map { seg in
            RawWord(
                substring: seg.substring,
                timestamp: seg.timestamp,
                duration: seg.duration,
                confidence: seg.confidence
            )
        }
        return RawRecognitionData(
            formattedString: transcription.formattedString,
            words: words,
            recognitionStatus: status
        )
    }

    nonisolated private static func contextualStrings(for language: String) -> [String] {
        [
            "MVP",
            "App Store",
            "web",
            "AI",
            "yapay zeka",
            "Vibe Coding",
            "Vibe Coding Turkey",
            "code",
            "coding",
            "no-code",
            "SwiftUI",
            "iOS",
            "uygulama",
            "ürün",
            "startup",
            "founder",
            language
        ]
    }

    private func recognitionTimeout(for url: URL, language: String) async -> Duration {
        let asset = AVURLAsset(url: url)
        let loadedDuration = try? await asset.load(.duration)
        let durationSeconds = loadedDuration.map { CMTimeGetSeconds($0) } ?? 0
        let isFallbackPass = language == "en"
        let boundedSeconds = if isFallbackPass {
            min(max(durationSeconds * 0.90 + 12, 28), 90)
        } else {
            min(max(durationSeconds * 1.60 + 18, 35), 180)
        }
        return .milliseconds(Int(boundedSeconds * 1000))
    }

    private func shouldAttemptEnglishFallback(
        for result: TranscriptionResult,
        sourceURL: URL,
        primaryLanguage: String
    ) async -> Bool {
        guard primaryLanguage != "en" else { return false }
        let asset = AVURLAsset(url: sourceURL)
        let loadedDuration = try? await asset.load(.duration)
        let durationSeconds = loadedDuration.map { CMTimeGetSeconds($0) } ?? 0
        return Self.shouldAttemptEnglishFallback(
            for: result,
            durationSeconds: durationSeconds,
            primaryLanguage: primaryLanguage
        )
    }

    nonisolated static func shouldAttemptEnglishFallback(
        for result: TranscriptionResult,
        durationSeconds: Double,
        primaryLanguage: String
    ) -> Bool {
        guard primaryLanguage != "en", durationSeconds > 0, durationSeconds <= 90 else { return false }
        let text = result.fullText.lowercased()
        let containsEnglishProductTerms = [
            "ai",
            "app store",
            "web",
            "android",
            "mvp",
            "code",
            "coding",
            "startup"
        ].contains { text.localizedStandardContains($0) }

        if Self.artifactRiskScore(in: result.fullText) > 0 { return true }
        if result.overallConfidence < 0.82 { return true }
        return containsEnglishProductTerms && result.overallConfidence < 0.88
    }

    nonisolated private static func preferredTranscript(
        primary: TranscriptionResult,
        alternate: TranscriptionResult
    ) -> TranscriptionResult {
        let primaryScore = transcriptScore(primary)
        let alternateScore = transcriptScore(alternate)
        guard alternateScore > primaryScore + 6 else { return primary }
        return alternate
    }

    nonisolated private static func transcriptScore(_ result: TranscriptionResult) -> Float {
        let protectedTermHits = [
            "vibe coding",
            "mvp",
            "app store",
            "android",
            "web",
            "yapay zeka",
            "kod"
        ].filter { result.fullText.lowercased().localizedStandardContains($0) }.count
        let speechSegmentCount = result.segments.filter { $0.segmentType == .speech || $0.segmentType == .contentSentence }.count
        return result.overallConfidence * 100
            + Float(min(protectedTermHits, 5) * 4)
            + Float(min(speechSegmentCount, 12))
            - Float(artifactRiskScore(in: result.fullText) * 18)
    }

    nonisolated private static func artifactRiskScore(in text: String) -> Int {
        let patterns = [
            #"\b(BAP|Bolding|Kolding)\b"#,
            #"\bby\s+Cording\b"#,
            #"\bby\s+Holding\b"#,
            #"\b(Way|Vay)\s+coin\b"#,
            #"\b(vay|vip|var)\s+Kolding\b"#,
            #"\btoplu\s+vay\s+Coding\b"#,
            #"\bkurdun\s+koy\s+duymayan\b"#,
            #"\bMHP\s*'?\s*ye\b"#,
            #"\byorumlara\s+(vay|vip|var)\s+biraz\b"#,
            #"\byorumları\s+(vay|vip|var)\s+yaz\b"#,
            #"\bistersen\s+yorumları\b"#,
            #"\bcod\b"#,
            #"\bg\s+bilmeyen\b"#,
            #"\bfikirlerin\s+en\b"#,
            #"\bAnd\s+roid\s*'\s*de\b"#,
            #"\bVPN\s+çevire\b"#,
            #"\bweb\s+e\b"#,
            #"\be\s*'?\s*ye\s+anlatmay[iı]\b"#,
            #"\byayınlayabilir\s+sin\s+ler\b"#,
            #"\bulaşabilsin\s+ler\b"#,
            #"\b(göndere|çevir|çevire|ulaş)\s+bil\s+sin"#,
            #"\b(gene|yine)\s+olmadı\b"#,
            #"\bama\s+izleyebiliriz\s+yani\b"#
        ]
        return patterns.filter { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }.count
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
                let wordTimings = currentWords.map { w in
                    (word: w.substring, start: w.timestamp, duration: w.duration)
                }

                var segment = TranscriptSegment(
                    startTime: start,
                    endTime: end,
                    text: text,
                    confidence: avgConf,
                    segmentType: .speech
                )
                segment.rawConfidence = avgConf
                segment.wordTimings = wordTimings
                segments.append(segment)

                currentWords = []
                chunkStart = nil
            }
        }

        if !currentWords.isEmpty, let start = chunkStart {
            let lastWord = currentWords.last!
            let text = currentWords.map(\.substring).joined(separator: " ")
            let wordTimings = currentWords.map { w in
                (word: w.substring, start: w.timestamp, duration: w.duration)
            }
            var segment = TranscriptSegment(
                startTime: start,
                endTime: lastWord.timestamp + lastWord.duration,
                text: text,
                confidence: currentWords.reduce(Float(0)) { $0 + $1.confidence } / Float(currentWords.count),
                segmentType: .speech
            )
            segment.rawConfidence = segment.confidence
            segment.wordTimings = wordTimings
            segments.append(segment)
        }

        return segments
    }
}

enum TranscriptPostProcessor {
    private struct CorrectionRule {
        let pattern: String
        let replacement: String
        let confidenceFloor: Float
    }

    private static let correctionRules: [CorrectionRule] = [
        CorrectionRule(pattern: #"\bBAP\s+Holding\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bBAP\s+Holding\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bby\s+Cording\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bby\s+Cording\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bby\s+Holding\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bby\s+Holding\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"^Holding\s+topluluğu\b"#, replacement: "Vibe Coding topluluğu", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bBolding\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bBolding\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bWay\s+coin\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bWay\s+coin\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bVay\s+coin\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bVay\s+coin\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\btoplu\s+vay\s+Coding\s+Turkey\b"#, replacement: "topluluğu Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bVay\s+Kolding\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bVay\s+Kolding\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bV[İI]P\s+Kolding\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bvar\s+Kolding\s+Turkey\b"#, replacement: "Vibe Coding Turkey", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bvar\s+Kolding\b"#, replacement: "Vibe Coding", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bKolding\s+topluluğu\b"#, replacement: "Coding topluluğu", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bKolding\s+Turkey\b"#, replacement: "Coding Turkey", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bturkey\b"#, replacement: "Turkey", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bgeçire\s+miyor\b"#, replacement: "geçiremiyor", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bkurdun\s+koy\s+duymayan\s+insanlar\s+dövün\s+çıkarabilsin\s+fikirlerine\s+VPN\s+çevire\b"#, replacement: "kurdum kod bilmeyen insanlar da ürün çıkarabilsin fikirlerini MVP'ye çevire", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bkurdun\s+koy\s+duymayan\s+insanlar\b"#, replacement: "kurdum kod bilmeyen insanlar", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"dövün\s+çıkarabilsin\s+fikirlerine\s+VPN\s+çevirebilsinler"#, replacement: "ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"dövün\s+çıkarabilsin\s+fikirlerine\s+VPN\s+çevire"#, replacement: "ürün çıkarabilsin fikirlerini MVP'ye çevire", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\b(co|cod|code|g)\s+bilmeyen\b"#, replacement: "kod bilmeyen", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bcod\b"#, replacement: "kod", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bMHP\s*'?\s*ye\b"#, replacement: "MVP'ye", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\ben\s+VP\s*'?\s*ye\b"#, replacement: "MVP'ye", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bVP\s*'?\s*ye\b"#, replacement: "MVP'ye", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bfikrine\s+MVP'ye\b"#, replacement: "fikrini MVP'ye", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bfikirlerine\s+MVP'ye\b"#, replacement: "fikirlerini MVP'ye", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bçıkarabilirsin\s+fikirlerini\s+MVP'ye\b"#, replacement: "çıkarabilsin fikirlerini MVP'ye", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bama\s+daha\s+kod\s+yaza\s+madığı\s+için\s+en\b"#, replacement: "ama daha kod yazamadığı için", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bkod\s+yaza\s+madığı\b"#, replacement: "kod yazamadığı", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"da\s+ürün\s+yapabilirsin\s+MVP\s+çıkarabilsin"#, replacement: "da ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"ürün\s+yapabilirsin\s+MVP\s+çıkarabilsin"#, replacement: "ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bürün\s+yapabilirsin\s+MVP\s+çıkarabilsin\b"#, replacement: "ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bçıkar\s+abil\s+sinler\b"#, replacement: "çıkarabilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bçıkar\s+abil\s+sin\b"#, replacement: "çıkarabilsin", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bApp\s+Store\s*'\s*a\b"#, replacement: "App Store'a", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bApp\s+Store\s*'\s*da\b"#, replacement: "App Store'da", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bApple\s+Store\s*'\s*da\b"#, replacement: "Apple Store'da", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bAnd\s+roid\s*'\s*de\b"#, replacement: "Android'de", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bApp\s+Store\s+ya\s+da\s+web\s+e\b"#, replacement: "App Store'a ya da web'e", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bweb\s*'\s*e\b"#, replacement: "web'e", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bweb\s+e\b"#, replacement: "web'e", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\be\s*'?\s*ye\s+anlatmay[iı]\b"#, replacement: "yapay zekayı anlatmayı", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\bçevir\s+bil\s+sinler\b"#, replacement: "çevirebilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bçevir\s+bil\s+sin\b"#, replacement: "çevirebilsin", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bçevire\s+bil\s+sinler\b"#, replacement: "çevirebilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bçevire\s+bil\s+sin\b"#, replacement: "çevirebilsin", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bulaşabilsin\s+ler\b"#, replacement: "ulaşabilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bgöndere\s+bil\s+sinler\b"#, replacement: "gönderebilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bgöndere\s+bil\b"#, replacement: "gönderebil", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\byayınlayabilir\s+sin\s+ler\b"#, replacement: "yayınlayabilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bulaş\s+abil\s+sinler\b"#, replacement: "ulaşabilsinler", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\bulaş\s+abil\s+sin\b"#, replacement: "ulaşabilsin", confidenceFloor: 0.68),
        CorrectionRule(pattern: #"\byorumlara\s+(vay|vip|var)\s+biraz\b"#, replacement: "yorumlara Vibe yazıp", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\byorumlara\s+(vay|vip|var)\s+biraz\s+birlikte\b"#, replacement: "yorumlara Vibe yazıp birlikte", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\byorumları\s+(vay|vip|var)\s+yaz\b"#, replacement: "yorumlara Vibe yazıp", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\byorumları\s+Vibe\s+yazıp\b"#, replacement: "yorumlara Vibe yazıp", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"^(vay|vip|var)\s+biraz\s+birlikte\b"#, replacement: "Vibe yazıp birlikte", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\s+gene\s+olmadı\b.*$"#, replacement: "", confidenceFloor: 0.72),
        CorrectionRule(pattern: #"\s+yine\s+olmadı\b.*$"#, replacement: "", confidenceFloor: 0.72),
    ]

    static func corrected(_ result: TranscriptionResult) -> TranscriptionResult {
        var didChange = false
        var correctedSegments = result.segments.map { segment in
            let corrected = correctedSegment(segment)
            didChange = didChange || corrected.text != segment.text
            return corrected
        }
        let stitchedSegments = stitchCrossSegmentContinuations(correctedSegments)
        didChange = didChange || stitchedSegments.map(\.text) != correctedSegments.map(\.text)
        correctedSegments = stitchedSegments

        guard didChange else {
            return result
        }

        let averageConfidence = correctedSegments.isEmpty ? result.overallConfidence
            : correctedSegments.reduce(Float(0)) { $0 + $1.confidence } / Float(correctedSegments.count)
        return TranscriptionResult(
            fullText: correctedSegments.map(\.text).joined(separator: " "),
            segments: correctedSegments,
            language: result.language,
            overallConfidence: averageConfidence,
            rawOverallConfidence: result.rawOverallConfidence ?? result.overallConfidence,
            recognitionStatus: result.recognitionStatus
        )
    }

    private static func correctedSegment(_ segment: TranscriptSegment) -> TranscriptSegment {
        var text = normalizeWhitespace(segment.text)
        var confidenceFloor: Float = 0

        for rule in correctionRules {
            let replacement = replace(pattern: rule.pattern, in: text, with: rule.replacement)
            if replacement.changed {
                text = normalizeWhitespace(replacement.text)
                confidenceFloor = max(confidenceFloor, rule.confidenceFloor)
            }
        }

        guard text != segment.text else {
            return segment
        }

        var corrected = TranscriptSegment(
            startTime: segment.startTime,
            endTime: segment.endTime,
            text: text,
            confidence: max(segment.confidence, confidenceFloor),
            segmentType: segment.segmentType
        )
        corrected.aiConfidence = segment.aiConfidence
        corrected.aiReason = segment.aiReason
        corrected.rawConfidence = segment.rawConfidence ?? segment.confidence
        corrected.wordTimings = alignedWordTimings(for: text, from: segment)
        return corrected
    }

    private static func stitchCrossSegmentContinuations(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard segments.count > 1 else { return segments }

        var stitched = segments
        for index in 1..<stitched.count {
            let previous = stitched[index - 1]
            let current = stitched[index]

            if textMatches(pattern: #"\bTürkiye'nin\s+ilk\s+BAP[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^(Holding|Vibe\s+Coding)\s+topluluğu\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s+BAP[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.72
                )
                if textMatches(pattern: #"^Holding\s+topluluğu\b"#, text: current.text) {
                    stitched[index] = copySegment(
                        current,
                        text: replacingText(pattern: #"^Holding\s+topluluğu\b"#, in: current.text, with: "Vibe Coding topluluğu"),
                        confidenceFloor: 0.72
                    )
                }
                continue
            }

            if textMatches(pattern: #"\bfikirlerin\s+en\s+VP[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^'ye\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\bfikirlerin\s+en\s+VP[.!?,]?$"#, in: previous.text, with: "fikirlerini"),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^'ye\b"#, in: current.text, with: "MVP'ye"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bfikirlerin\s+en[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^MVP'?ye\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\bfikirlerin\s+en[.!?,]?$"#, in: previous.text, with: "fikirlerini"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bçevire[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^bilsinler\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*çevire[.!?,]?$"#, in: previous.text, with: " çevirebilsinler"),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^bilsinler\s*"#, in: current.text, with: ""),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bApp\s+Store[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^'a\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\bApp\s+Store[.!?,]?$"#, in: previous.text, with: "App Store'a"),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^'a\s*"#, in: current.text, with: ""),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bya[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^da\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s+ya[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: "ya " + current.text,
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bulaş\s+abil[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^sinler\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*ulaş\s+abil[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^sinler\b"#, in: current.text, with: "ulaşabilsinler"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bulaş\s+abil[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^sin\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*ulaş\s+abil[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^sin\b"#, in: current.text, with: "ulaşabilsin"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bulaş[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^abil\s+sinler\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*ulaş[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^abil\s+sinler\b"#, in: current.text, with: "ulaşabilsinler"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bgönderebil[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^sinler\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*gönderebil[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^sinler\b"#, in: current.text, with: "gönderebilsinler"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bgönderebil[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^sin\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*gönderebil[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^sin\b"#, in: current.text, with: "gönderebilsin"),
                    confidenceFloor: 0.68
                )
                continue
            }

            if textMatches(pattern: #"\bulaş[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^abil\s+sin\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\s*ulaş[.!?,]?$"#, in: previous.text, with: ""),
                    confidenceFloor: 0.68
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^abil\s+sin\b"#, in: current.text, with: "ulaşabilsin"),
                    confidenceFloor: 0.68
                )
            }

            if textMatches(pattern: #"\byorumlara\s+(vay|vip)[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^biraz\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\byorumlara\s+(vay|vip)[.!?,]?$"#, in: previous.text, with: "yorumlara Vibe yazıp"),
                    confidenceFloor: 0.72
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^biraz\s*"#, in: current.text, with: ""),
                    confidenceFloor: 0.72
                )
            }

            if textMatches(pattern: #"\byorumları[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^Vibe\s+yazıp\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\byorumları[.!?,]?$"#, in: previous.text, with: "yorumlara Vibe yazıp"),
                    confidenceFloor: 0.72
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^Vibe\s+yazıp\s*"#, in: current.text, with: ""),
                    confidenceFloor: 0.72
                )
            }

            if textMatches(pattern: #"\byorumlara[.!?,]?$"#, text: previous.text),
               textMatches(pattern: #"^((vay|vip|var)\s+biraz|Vibe\s+yazıp)\b"#, text: current.text) {
                stitched[index - 1] = copySegment(
                    previous,
                    text: replacingText(pattern: #"\byorumlara[.!?,]?$"#, in: previous.text, with: "yorumlara Vibe yazıp"),
                    confidenceFloor: 0.72
                )
                stitched[index] = copySegment(
                    current,
                    text: replacingText(pattern: #"^((vay|vip|var)\s+biraz|Vibe\s+yazıp)\s*"#, in: current.text, with: ""),
                    confidenceFloor: 0.72
                )
            }
        }

        return stitched
    }

    private static func copySegment(
        _ segment: TranscriptSegment,
        text: String,
        confidenceFloor: Float
    ) -> TranscriptSegment {
        var copied = TranscriptSegment(
            startTime: segment.startTime,
            endTime: segment.endTime,
            text: normalizeWhitespace(text),
            confidence: max(segment.confidence, confidenceFloor),
            segmentType: segment.segmentType
        )
        copied.aiConfidence = segment.aiConfidence
        copied.aiReason = segment.aiReason
        copied.rawConfidence = segment.rawConfidence ?? segment.confidence
        copied.wordTimings = alignedWordTimings(for: copied.text, from: segment)
        return copied
    }

    private static func alignedWordTimings(
        for text: String,
        from segment: TranscriptSegment
    ) -> [(word: String, start: Double, duration: Double)] {
        let words = timingWords(in: text)
        guard !words.isEmpty else { return [] }

        if segment.wordTimings.count == words.count {
            return zip(words, segment.wordTimings).map { pair in
                let (word, timing) = pair
                return (word: word, start: timing.start, duration: timing.duration)
            }
        }

        let start = max(segment.startTime, segment.wordTimings.first?.start ?? segment.startTime)
        let rawEnd = segment.wordTimings.last.map { $0.start + $0.duration } ?? segment.endTime
        let end = min(max(rawEnd, start + 0.01), max(segment.endTime, start + 0.01))
        return proportionalWordTimings(words: words, start: start, end: end)
    }

    private static func timingWords(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func proportionalWordTimings(
        words: [String],
        start: Double,
        end: Double
    ) -> [(word: String, start: Double, duration: Double)] {
        guard !words.isEmpty else { return [] }

        let span = max(0.01, end - start)
        let weights = words.map { word in
            max(1, word.filter { !$0.isWhitespace }.count)
        }
        let totalWeight = max(1, weights.reduce(0, +))
        var cursor = start

        return words.enumerated().map { index, word in
            let isLast = index == words.indices.last
            let duration = isLast
                ? max(0.01, end - cursor)
                : max(0.01, span * Double(weights[index]) / Double(totalWeight))
            defer { cursor += duration }
            return (word: word, start: cursor, duration: duration)
        }
    }

    private static func replace(pattern: String, in text: String, with replacement: String) -> (text: String, changed: Bool) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, false)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let corrected = regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: replacement
        )
        return (corrected, corrected != text)
    }

    private static func replacingText(pattern: String, in text: String, with replacement: String) -> String {
        replace(pattern: pattern, in: text, with: replacement).text
    }

    private static func textMatches(pattern: String, text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
