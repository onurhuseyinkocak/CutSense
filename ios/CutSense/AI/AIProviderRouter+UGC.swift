import Foundation
import os

// MARK: - UGC AI Capabilities

extension AIProviderRouter {

    private static let logger = Logger(subsystem: "CutSense", category: "AIProviderRouter+UGC")

    // MARK: - Transcript Analysis

    struct TranscriptAnalysis: Sendable, Codable {
        let hookPhrase: String?
        let keyPoints: [String]
        let topicChanges: [TopicChange]

        struct TopicChange: Sendable, Codable {
            let startTime: Double
            let topic: String
        }
        let sentimentOverall: String
        let importantMoments: [ImportantMoment]

        struct ImportantMoment: Sendable, Codable {
            let timeRange: ClosedRange<Double>
            let reason: String
            let suggestedEmphasis: String
        }
    }

    /// Analyze a transcript using the best available AI provider.
    func analyzeTranscript(
        transcript: String,
        language: String = "tr"
    ) async -> TranscriptAnalysis? {
        let systemPrompt = """
        You are a video editing AI assistant. Analyze the following transcript and provide:
        1. A hook phrase (first 3-5 words that grab attention)
        2. Key points mentioned
        3. Topic changes with timestamps
        4. Overall sentiment
        5. Important moments worth emphasizing

        Respond in JSON format matching this structure:
        {
            "hookPhrase": "...",
            "keyPoints": ["..."],
            "topicChanges": [{"startTime": 0.0, "topic": "..."}],
            "sentimentOverall": "positive|negative|neutral|mixed",
            "importantMoments": [{"timeRange": [0.0, 5.0], "reason": "...", "suggestedEmphasis": "..."}]
        }
        """

        guard let response = await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: "Language: \(language)\n\nTranscript:\n\(transcript)",
            jsonMode: true
        ) else {
            Self.logger.warning("Transcript analysis failed — returning nil")
            return nil
        }

        guard let data = response.data(using: .utf8),
              let analysis = try? JSONDecoder().decode(TranscriptAnalysis.self, from: data) else {
            Self.logger.error("Failed to parse transcript analysis response")
            return nil
        }

        return analysis
    }

    // MARK: - Take Quality Scoring

    struct TakeQualityAssessment: Sendable, Codable {
        let overallScore: Double
        let speechClarity: Double
        let energyLevel: Double
        let completeness: Double
        let naturalFlow: Double
        let reasons: [String]
    }

    /// Score a take's quality using AI analysis.
    func assessTakeQuality(
        transcript: String,
        duration: Double,
        audioQuality: Float,
        facePresence: Float
    ) async -> TakeQualityAssessment? {
        let systemPrompt = """
        Score this video take on a 0-100 scale for each dimension:
        - speechClarity: How clear and articulate is the speech?
        - energyLevel: How engaging and energetic is the delivery?
        - completeness: Does the speaker finish their thoughts?
        - naturalFlow: Does it sound natural or forced?

        Consider these inputs:
        - Transcript text
        - Duration (seconds)
        - Audio quality (0-1)
        - Face presence score (0-1)

        Respond in JSON:
        {
            "overallScore": 75.0,
            "speechClarity": 80.0,
            "energyLevel": 70.0,
            "completeness": 85.0,
            "naturalFlow": 75.0,
            "reasons": ["Clear speech", "Good energy"]
        }
        """

        let userMessage = """
        Transcript: \(transcript)
        Duration: \(duration)s
        Audio Quality: \(audioQuality)
        Face Presence: \(facePresence)
        """

        guard let response = await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            jsonMode: true
        ) else {
            return nil
        }

        guard let data = response.data(using: .utf8),
              let assessment = try? JSONDecoder().decode(TakeQualityAssessment.self, from: data) else {
            return nil
        }

        return assessment
    }

    // MARK: - Edit Planning

    struct EditPlan: Sendable, Codable {
        let cuts: [EditCut]
        let emphasisMoments: [EmphasisMoment]
        let pacingNotes: String

        struct EditCut: Sendable, Codable {
            let timeRange: ClosedRange<Double>
            let reason: String
            let confidence: Double
        }

        struct EmphasisMoment: Sendable, Codable {
            let timeRange: ClosedRange<Double>
            let type: String
            let intensity: Double
            let reason: String
        }
    }

    /// Generate an edit plan for a video using AI analysis.
    func planEdits(
        transcript: String,
        duration: Double,
        takeGroups: [[String]], // group texts
        intensity: String = "balanced"
    ) async -> EditPlan? {
        let systemPrompt = """
        Create an editing plan for a \(duration)-second video.
        Intensity: \(intensity)

        Analyze the transcript and suggest:
        1. Cuts: segments to remove (silence, filler, repetition)
        2. Emphasis moments: points worth highlighting with zoom/punch-in
        3. Pacing notes

        Respond in JSON:
        {
            "cuts": [{"timeRange": [0.0, 2.0], "reason": "silence", "confidence": 0.9}],
            "emphasisMoments": [{"timeRange": [5.0, 8.0], "type": "punch_in", "intensity": 0.7, "reason": "key claim"}],
            "pacingNotes": "..."
        }
        """

        let flatGroups = takeGroups.map { $0.joined(separator: ", ") }.joined(separator: "\n")
        let userMessage = """
        Transcript:
        \(transcript)

        Duration: \(duration)s
        Take groups:
        \(flatGroups)
        """

        guard let response = await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            jsonMode: true
        ) else {
            return nil
        }

        guard let data = response.data(using: .utf8),
              let plan = try? JSONDecoder().decode(EditPlan.self, from: data) else {
            return nil
        }

        return plan
    }

    // MARK: - Caption Suggestion

    struct CaptionSuggestion: Sendable, Codable {
        let text: String
        let style: String
        let emphasisWords: [String]
        let timing: Double // seconds from start
    }

    /// Suggest caption enhancements for a transcript segment.
    func suggestCaptions(
        segmentText: String,
        segmentIndex: Int,
        totalSegments: Int,
        style: String = "bold_center"
    ) async -> CaptionSuggestion? {
        let systemPrompt = """
        Suggest a caption enhancement for this video segment.
        Style: \(style)
        Position: segment \(segmentIndex + 1) of \(totalSegments)

        Rules:
        - Keep text under 40 characters per line
        - Highlight 1-2 key words
        - Match the style (bold_center = center alignment, bold keywords)

        Respond in JSON:
        {
            "text": "Enhanced caption text",
            "style": "bold_center",
            "emphasisWords": ["keyword"],
            "timing": 0.0
        }
        """

        guard let response = await chatCompletion(
            systemPrompt: systemPrompt,
            userMessage: segmentText,
            jsonMode: true
        ) else {
            return nil
        }

        guard let data = response.data(using: .utf8),
              let suggestion = try? JSONDecoder().decode(CaptionSuggestion.self, from: data) else {
            return nil
        }

        return suggestion
    }
}
