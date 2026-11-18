#error("RECON GAP: lines 1-18 of CutSensePipeline.swift unrecoverable")
    public init() {}
#error("RECON GAP: lines 20-20 of CutSensePipeline.swift unrecoverable")
    public func export(
#error("RECON GAP: lines 22-23 of CutSensePipeline.swift unrecoverable")
        editMode: CutSenseEditMode = .automaticEdit,
        captionStyle: CaptionStyleName = .techKinetic,
#error("RECON GAP: lines 26-26 of CutSensePipeline.swift unrecoverable")
        preplannedSpeechRanges: [SpeechRange]? = nil,
#error("RECON GAP: lines 28-36 of CutSensePipeline.swift unrecoverable")
            progress(.init(stage: .transcribing, fraction: 0.28, message: "Mevcut transkript kullanılıyor…"))
#error("RECON GAP: lines 38-42 of CutSensePipeline.swift unrecoverable")
            progress(.init(stage: .transcribing, fraction: 0.08, message: "Ses analiz ediliyor…"))
#error("RECON GAP: lines 44-47 of CutSensePipeline.swift unrecoverable")
            progress(.init(
#error("RECON GAP: lines 49-55 of CutSensePipeline.swift unrecoverable")
        // ============ 2. AUTO-CUT ============
        progress(.init(
#error("RECON GAP: lines 58-63 of CutSensePipeline.swift unrecoverable")
        let speechRanges: [SpeechRange]
#error("RECON GAP: lines 65-66 of CutSensePipeline.swift unrecoverable")
                SpeechRange(
#error("RECON GAP: lines 68-74 of CutSensePipeline.swift unrecoverable")
            case .automaticEdit:
                if let preplannedSpeechRanges, !preplannedSpeechRanges.isEmpty {
                    let preplanned = preplannedSpeechRanges.map {
#error("RECON GAP: lines 78-90 of CutSensePipeline.swift unrecoverable")
                    speechRanges = AutoCutPlanner.planAutomaticEdit(
#error("RECON GAP: lines 92-96 of CutSensePipeline.swift unrecoverable")
                if let preplannedSpeechRanges, !preplannedSpeechRanges.isEmpty {
                    let preplanned = preplannedSpeechRanges.map {
#error("RECON GAP: lines 99-125 of CutSensePipeline.swift unrecoverable")
        progress(.init(stage: .composing, fraction: 0.36, message: "Sahne kurgulanıyor…"))
#error("RECON GAP: lines 127-168 of CutSensePipeline.swift unrecoverable")
            progress(.init(stage: .fetchingAssets, fraction: 0.50, message: editMode.assetPlanningMessage))
#error("RECON GAP: lines 170-170 of CutSensePipeline.swift unrecoverable")
            if editMode == .automaticEdit {
#error("RECON GAP: lines 172-177 of CutSensePipeline.swift unrecoverable")
                audioPlan = await AudioPlanBuilder.sfxOnlyPlan(
                    transcript: transcript,
                    speechRanges: speechRanges,
                    cleanDuration: cleanDuration
                )
            }
        } else {
            progress(.init(stage: .fetchingAssets, fraction: 0.50, message: editMode.assetPlanningMessage))
            brollAssets = []
            audioPlan = AudioPlan(
                musicURL: nil,
                mood: .subtle,
                bpm: 95,
                beats: [],
                sfxPlacements: [],
                duckingRanges: []
            )
        }
        print("[CutSensePipeline] broll=\(brollAssets.count) mood=\(audioPlan.mood) sfx=\(audioPlan.sfxPlacements.count) ducks=\(audioPlan.duckingRanges.count)")

        // ============ 5. B-ROLL VIDEO TRACKS ============
        var brollLayerInsts: [AVMutableVideoCompositionLayerInstruction] = []
        for asset in brollAssets where asset.kind == .video {
            let bAsset = AVURLAsset(url: asset.localURL)
            guard let srcTracks = try? await bAsset.loadTracks(withMediaType: .video),
                  let bSrc = srcTracks.first else { continue }
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let bDur = (try? await bAsset.load(.duration).seconds) ?? 0
            let pipDur = min(asset.cleanEnd - asset.cleanStart, max(bDur, 0.5))
            let srcRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: pipDur, preferredTimescale: 600)
            )
            let at = CMTime(seconds: asset.cleanStart, preferredTimescale: 600)
            do {
                try compTrack.insertTimeRange(srcRange, of: bSrc, at: at)
            } catch {
                continue
            }
            let bNat = (try? await bSrc.load(.naturalSize)) ?? CGSize(width: 1080, height: 1920)
            let bPref = (try? await bSrc.load(.preferredTransform)) ?? .identity
            let applied = bNat.applying(bPref)
            let absW = max(abs(applied.width), 1)
            let absH = max(abs(applied.height), 1)
            let scale = min(renderSize.width * 0.35 / absW, renderSize.height * 0.35 / absH)
            let scaledW = absW * scale
            let scaledH = absH * scale
            let tx = renderSize.width - scaledW - 24
            let ty = renderSize.height - scaledH - 24
            let finalT = bPref
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: tx, y: ty))
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
            li.setTransform(finalT, at: .zero)
            li.setOpacity(0, at: .zero)
            li.setOpacityRamp(
                fromStartOpacity: 0, toEndOpacity: 1,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: asset.cleanStart, preferredTimescale: 600),
                    duration: CMTime(seconds: 0.18, preferredTimescale: 600)
                )
            )
            let outStart = max(asset.cleanStart + 0.2, asset.cleanStart + pipDur - 0.18)
            li.setOpacityRamp(
                fromStartOpacity: 1, toEndOpacity: 0,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: outStart, preferredTimescale: 600),
                    duration: CMTime(seconds: 0.18, preferredTimescale: 600)
                )
            )
            brollLayerInsts.append(li)
        }

        // ============ 6. AUDIO MIX ============
        progress(.init(stage: .planningAudio, fraction: 0.72, message: "Ses miksleniyor…"))
        let mixOut = try await AudioMixBuilder.build(
            composition: composition,
            sourceVoiceTrack: mainAudio,
            plan: audioPlan,
            cleanDuration: cleanDuration
        )

        // ============ 7. CALAYER OVERLAYS (captions + image broll) ============
        progress(.init(
            stage: .composing,
            fraction: 0.80,
            message: editMode.composingMessage
        ))
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // Image B-rolls as CALayer overlays with Ken Burns motion: a
        // slow zoom + pan across the asset's visible window for a
        // cinematic feel. Each image alternates pan direction so the
        // sequence feels varied.
        for (i, asset) in brollAssets.enumerated() where asset.kind == .image {
            guard let img = UIImage(contentsOfFile: asset.localURL.path) else { continue }
            let imgSize = img.size
            let aspect = imgSize.height > 0 ? imgSize.width / imgSize.height : 1.0
            let w = renderSize.width * 0.35
            let h = w / aspect
            let baseX = renderSize.width - w - 24
            let baseY: CGFloat = 24
            let pip = CALayer()
            pip.frame = CGRect(x: baseX, y: baseY, width: w, height: h)
            pip.contents = img.cgImage
            pip.contentsGravity = .resizeAspectFill
            pip.masksToBounds = true
            pip.cornerRadius = 12
            pip.opacity = 0
            // Anchor at center for smoother scale animation.
            pip.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            pip.position = CGPoint(x: baseX + w / 2, y: baseY + h / 2)
            parentLayer.addSublayer(pip)

            let pipDur = max(0.5, asset.cleanEnd - asset.cleanStart)

            // Fade in.
            let inAt = CABasicAnimation(keyPath: "opacity")
            inAt.fromValue = 0; inAt.toValue = 1
            inAt.beginTime = AVCoreAnimationBeginTimeAtZero + asset.cleanStart
            inAt.duration = 0.22
            inAt.fillMode = .forwards; inAt.isRemovedOnCompletion = false
            pip.add(inAt, forKey: "fadeIn")

            // Ken Burns zoom (1.0 → 1.12 over the lifetime of the asset).
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = 1.0
            zoom.toValue = 1.12
            zoom.beginTime = AVCoreAnimationBeginTimeAtZero + asset.cleanStart
            zoom.duration = pipDur
            zoom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            zoom.fillMode = .forwards; zoom.isRemovedOnCompletion = false
            pip.add(zoom, forKey: "kenBurnsZoom")

            // Pan direction alternates (left↔right) per image index.
            let panOffset: CGFloat = (i % 2 == 0) ? -10 : 10
            let pan = CABasicAnimation(keyPath: "position.x")
            pan.fromValue = baseX + w / 2
            pan.toValue = baseX + w / 2 + panOffset
            pan.beginTime = AVCoreAnimationBeginTimeAtZero + asset.cleanStart
            pan.duration = pipDur
            pan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pan.fillMode = .forwards; pan.isRemovedOnCompletion = false
            pip.add(pan, forKey: "kenBurnsPan")

            // Fade out.
            let outAt = CABasicAnimation(keyPath: "opacity")
            outAt.fromValue = 1; outAt.toValue = 0
            outAt.beginTime = AVCoreAnimationBeginTimeAtZero + max(asset.cleanStart + 0.24, asset.cleanEnd - 0.22)
            outAt.duration = 0.22
            outAt.fillMode = .forwards; outAt.isRemovedOnCompletion = false
            pip.add(outAt, forKey: "fadeOut")
        }

        let captionsLayer = CALayer()
        captionsLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(captionsLayer)
        let captionSegments: [CaptionSegment]
        let captionsRendered: Int
        let visualEditDecisions: [EditDecision]
        let planningCaptionSegments: [CaptionSegment]
        if editMode.rendersCaptions || editMode.rendersVisualEffects {
            planningCaptionSegments = Self.makeCleanCaptionSegments(
                transcript: transcript,
                speechRanges: speechRanges,
                styleName: captionStyle
            )
            captionSegments = editMode.rendersCaptions ? planningCaptionSegments : []
            captionsRendered = captionSegments.count
            visualEditDecisions = editMode.rendersVisualEffects
                ? Self.makeAutomaticVisualEditDecisions(
                    captionSegments: planningCaptionSegments,
                    speechRanges: speechRanges,
                    cleanDuration: cleanDuration
#error("RECON GAP: lines 359-364 of CutSensePipeline.swift unrecoverable")
            visualEditDecisions = []
#error("RECON GAP: lines 366-380 of CutSensePipeline.swift unrecoverable")
                editDecisions: visualEditDecisions,
#error("RECON GAP: lines 382-382 of CutSensePipeline.swift unrecoverable")
                captionTheme: .neonViral,
#error("RECON GAP: lines 384-409 of CutSensePipeline.swift unrecoverable")
        progress(.init(stage: .rendering, fraction: 0.90, message: "Video render ediliyor…"))
#error("RECON GAP: lines 411-425 of CutSensePipeline.swift unrecoverable")
        try await session.export(to: outputURL, as: .mp4)
#error("RECON GAP: lines 427-427 of CutSensePipeline.swift unrecoverable")
        progress(.init(stage: .done, fraction: 1.0, message: "Hazır."))
#error("RECON GAP: lines 429-435 of CutSensePipeline.swift unrecoverable")
            visualEffectsRendered: visualEditDecisions.count,
#error("RECON GAP: lines 437-440 of CutSensePipeline.swift unrecoverable")
    private static func makeAutomaticVisualEditDecisions(
#error("RECON GAP: lines 442-442 of CutSensePipeline.swift unrecoverable")
        speechRanges: [SpeechRange],
#error("RECON GAP: lines 444-444 of CutSensePipeline.swift unrecoverable")
    ) -> [EditDecision] {
#error("RECON GAP: lines 446-446 of CutSensePipeline.swift unrecoverable")
        var decisions: [EditDecision] = []
#error("RECON GAP: lines 448-449 of CutSensePipeline.swift unrecoverable")
            decisions.append(EditDecision(
#error("RECON GAP: lines 451-457 of CutSensePipeline.swift unrecoverable")
            decisions.append(EditDecision(
#error("RECON GAP: lines 459-469 of CutSensePipeline.swift unrecoverable")
            decisions.append(EditDecision(
#error("RECON GAP: lines 471-482 of CutSensePipeline.swift unrecoverable")
            decisions.append(EditDecision(
#error("RECON GAP: lines 484-490 of CutSensePipeline.swift unrecoverable")
                decisions.append(EditDecision(
#error("RECON GAP: lines 492-504 of CutSensePipeline.swift unrecoverable")
            decisions.append(EditDecision(
#error("RECON GAP: lines 506-524 of CutSensePipeline.swift unrecoverable")
    private static func dedupeVisualDecisions(_ decisions: [EditDecision]) -> [EditDecision] {
        var output: [EditDecision] = []
#error("RECON GAP: lines 527-555 of CutSensePipeline.swift unrecoverable")
        _ ranges: [SpeechRange],
#error("RECON GAP: lines 557-573 of CutSensePipeline.swift unrecoverable")
        speechRanges: [SpeechRange],
        styleName: CaptionStyleName
#error("RECON GAP: lines 576-649 of CutSensePipeline.swift unrecoverable")
    private static func captionStyle(for styleName: CaptionStyleName) -> CaptionStyle {
#error("RECON GAP: end of CutSensePipeline.swift unknown (file may continue past line 650)")
