import SwiftUI
import AVKit

/// A timeline-first mobile editor. The editing surface owns the screen; controls
/// are contextual and the inspector only appears after a user selects a track.
@MainActor
struct UGCStudioView: View {
    @ObservedObject var project: UGCEditProject
    let onBack: () -> Void
    let onRender: () -> Void
    let onExport: () -> Void
    let onReanalyze: () -> Void

    private enum Tool: String, CaseIterable { case clip, text, audio, effects }
    @State private var tool: Tool = .clip
    @State private var selectedDecisionID: UUID?
    @State private var selectedCaptionID: UUID?
    @State private var playhead = 0.0
    @State private var player: AVPlayer?
    @State private var previewTime = 0.0
    @State private var observer: Any?
    @State private var undoStack: [[UGCEditDecision]] = []
    @State private var redoStack: [[UGCEditDecision]] = []
    @State private var captionUndoStack: [[CaptionSegment]] = []
    @State private var captionRedoStack: [[CaptionSegment]] = []
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }
    private var clips: [UGCEditableClip] { UGCEditDecisionEngine.editableClips(from: project.editDecisions) }
    private var duration: Double { max(clips.last?.cleanEnd ?? 0, 1) }
    private var selectedDecisionIndex: Int? { selectedDecisionID.flatMap { id in project.editDecisions.firstIndex { $0.id == id } } }
    private var selectedCaptionIndex: Int? { selectedCaptionID.flatMap { id in project.captions.firstIndex { $0.id == id } } }
    private var activeCaption: CaptionSegment? { project.captions.first { $0.isVisible && previewTime >= $0.startTime && previewTime < $0.endTime } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if project.sourceLikelyHasBurnedCaptions {
                Text(appText(language, "Kaynak videoda altyazı algılandı. Çift altyazıyı önlemek için yeni altyazı eklenmedi.", "Source captions detected. New captions were not burned in to prevent duplicates."))
                    .font(.caption).foregroundStyle(.black).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8).background(.mint)
            }
            preview
            transport
            // One editing surface: timeline selection changes this single
            // inspector. There is deliberately no second mode/tool bar below
            // it, which previously made clip/text/audio controls compete.
            editorTimeline
            contextualPanel
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .onAppear { configurePlayer() }
        .onChange(of: project.finalCompositionURL) { _, _ in configurePlayer() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
            Text(appText(language, "Yeni proje", "New project")).font(.headline.weight(.semibold))
            Spacer()
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty && captionUndoStack.isEmpty)
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty && captionRedoStack.isEmpty)
            Text("1080P").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 5).background(.white.opacity(0.14)).clipShape(Capsule())
            Button(action: onExport) { Text(appText(language, "Dışa aktar", "Export")).font(.caption.weight(.bold)).foregroundStyle(.black).padding(.horizontal, 11).padding(.vertical, 8).background(.mint).clipShape(Capsule()) }
                .accessibilityIdentifier("studioExportButton")
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            if let player { VideoPlayer(player: player) } else { Color.black }
            // `finalCompositionURL` is an already-rendered export. Drawing a
            // second SwiftUI caption over it caused the unacceptable double-caption
            // state on device. Live caption preview is shown only from a source
            // composition, never on this final rendered player.
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(width: 230, height: 409)
        .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14)))
        .padding(.horizontal, 16)
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Text(time(playhead)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
            Button { if player?.timeControlStatus == .playing { player?.pause() } else { player?.play() } } label: { Image(systemName: player?.timeControlStatus == .playing ? "pause.fill" : "play.fill").font(.title3) }
            Text(time(duration)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Button(action: onRender) { Label(appText(language, "Uygula", "Apply"), systemImage: "checkmark") }.font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.12)).clipShape(Capsule())
        }.padding(.horizontal, 20).padding(.vertical, 9)
    }

    private var editorTimeline: some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                    timeRuler
                    filmStrip
                    audioLane
                    captionLayer
                    }.padding(.leading, 16).padding(.trailing, 16)
                    TimelinePlayhead(offset: CGFloat(playhead * 48 + 54))
                        .allowsHitTesting(false)
                }
            }
            Slider(value: $playhead, in: 0...duration, onEditingChanged: { if !$0 { seek(playhead) } })
                .tint(.mint).padding(.horizontal, 17)
        }.frame(height: 168).padding(.top, 4)
    }

    private var timeRuler: some View {
        HStack(spacing: 0) { ForEach(0...Int(duration.rounded(.up)), id: \.self) { second in Text(second % 2 == 0 ? "\(second)s" : "").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.38)).frame(width: 48, alignment: .leading) } }
    }

    private var filmStrip: some View {
        HStack(spacing: 3) {
            Text("VIDEO").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.45)).frame(width: 38, alignment: .leading)
            ForEach(clips) { clip in
                Button { selectedDecisionID = clip.decisionID; tool = .clip; seek(clip.cleanStart) } label: {
                    TimelineFilmCell(url: project.sourceVideoURL, time: clip.sourceStart, width: max(64, CGFloat(clip.duration) * 48), selected: selectedDecisionID == clip.decisionID)
                }.buttonStyle(.plain)
            }
        }
    }

    private var audioLane: some View {
        return HStack(spacing: 3) {
            Text("SFX").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.45)).frame(width: 38, alignment: .leading)
            if project.sfxEnabled {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == 0 ? .orange.opacity(0.85) : .orange.opacity(0.55))
                        .frame(width: max(64, CGFloat(clip.duration) * 48), height: 17)
                        .overlay(alignment: .leading) { Image(systemName: index == 0 ? "arrow.up.right" : "waveform").font(.system(size: 8, weight: .bold)).padding(.leading, 4).foregroundStyle(.black.opacity(0.75)) }
                }
            } else {
                Text(appText(language, "Ses efektleri kapalı", "Sound effects off")).font(.caption2).foregroundStyle(.white.opacity(0.35)).frame(height: 17)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tool = .audio }
    }

    private var captionLayer: some View {
        HStack(spacing: 3) {
            Text("TEXT").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.45)).frame(width: 38, alignment: .leading)
            ForEach(project.captions) { caption in Button { selectedCaptionID = caption.id; tool = .text; seek(caption.startTime) } label: { Text(caption.text).lineLimit(1).font(.caption2.weight(.medium)).foregroundStyle(.black).frame(width: max(55, CGFloat(caption.endTime - caption.startTime) * 48), height: 20).padding(.horizontal, 4).background(caption.isVisible ? .mint : .gray).clipShape(RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(selectedCaptionID == caption.id ? .white : .clear, lineWidth: 2)) }.buttonStyle(.plain) }
        }
    }

    @ViewBuilder private var contextualPanel: some View {
        switch tool {
        case .clip: clipPanel
        case .text: textPanel
        case .audio: audioPanel
        case .effects: effectsPanel
        }
    }

    private var clipPanel: some View {
        HStack(spacing: 10) {
            if let index = selectedDecisionIndex {
                let clip = project.editDecisions[index]
                VStack(spacing: 6) {
                    HStack {
                        Text("\(time(clip.startTime)) – \(time(clip.endTime))").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65)); Spacer()
                        if clip.action == .remove {
                            action(appText(language, "Geri getir", "Restore"), "arrow.counterclockwise") { setAction(index, .keep) }
                        } else {
                            action(appText(language, "Böl", "Split"), "scissors") { split(index) }
                            action(appText(language, "Sil", "Remove"), "trash") { setAction(index, .remove) }
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Baş").font(.caption2.weight(.bold)).frame(width: 25, alignment: .leading)
                        Slider(value: Binding(get: { clip.startTime }, set: { trim(index, start: $0, end: clip.endTime) }), in: 0...max(0, clip.endTime - 0.25)).tint(.mint).disabled(clip.action == .remove)
                        Text("Son").font(.caption2.weight(.bold)).frame(width: 25, alignment: .leading)
                        Slider(value: Binding(get: { clip.endTime }, set: { trim(index, start: clip.startTime, end: $0) }), in: min(clip.startTime + 0.25, clip.endTime)...max(clip.startTime + 0.25, project.originalDuration)).tint(.mint).disabled(clip.action == .remove)
                    }
                }
            } else { Text(appText(language, "Düzenlemek için film şeridinden bir klip seç.", "Select a clip in the film strip to edit.")).font(.caption).foregroundStyle(.white.opacity(0.55)); Spacer() }
        }.padding(.horizontal, 18).frame(height: selectedDecisionIndex == nil ? 54 : 82)
    }

    private var textPanel: some View {
        Group {
            if let index = selectedCaptionIndex {
                let caption = project.captions[index]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        TextField("Caption", text: Binding(get: { project.captions[index].text }, set: { newValue in
                            updateCaption(index) { caption in caption.text = newValue }
                        }))
                            .textFieldStyle(.plain).frame(width: 184).padding(10).background(.white.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                        Toggle("", isOn: Binding(get: { project.captions[index].isVisible }, set: { newValue in
                            updateCaption(index) { caption in caption.isVisible = newValue }
                        }))
                            .labelsHidden().tint(.mint)
                        inspectorSlider("Boyut", value: Binding(get: { caption.fontScale }, set: { newValue in
                            updateCaption(index) { segment in segment.fontScale = newValue }
                        }), range: 0.65...1.75)
                        inspectorSlider("Yükseklik", value: Binding(get: { caption.verticalPosition }, set: { newValue in
                            updateCaption(index) { segment in segment.verticalPosition = newValue }
                        }), range: 0.18...0.82)
                    }.padding(.horizontal, 16)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        effectButton(appText(language, "Hareket yok", "No motion"), behavior: .none, selected: caption.sceneBehavior, index: index)
                        effectButton(appText(language, "Yumuşak yakınlaş", "Gentle push"), behavior: .subtleZoom, selected: caption.sceneBehavior, index: index)
                        effectButton(appText(language, "Darbe", "Punch"), behavior: .punchIn, selected: caption.sceneBehavior, index: index)
                        effectButton(appText(language, "Geçiş", "Transition"), behavior: .transitionWhoosh, selected: caption.sceneBehavior, index: index)
                    }.padding(.horizontal, 16)
                }
                HStack(spacing: 9) {
                    Text(appText(language, "Başlangıç", "Start")).font(.caption2).foregroundStyle(.white.opacity(0.62))
                    Slider(value: Binding(get: { caption.startTime }, set: { value in
                        updateCaption(index) { segment in
                            segment.startTime = min(value, segment.endTime - 0.15)
                        }
                    }), in: 0...max(0, caption.endTime - 0.15)).tint(.mint)
                    Text(appText(language, "Bitiş", "End")).font(.caption2).foregroundStyle(.white.opacity(0.62))
                    Slider(value: Binding(get: { caption.endTime }, set: { value in
                        updateCaption(index) { segment in
                            segment.endTime = max(value, segment.startTime + 0.15)
                        }
                    }), in: min(duration, caption.startTime + 0.15)...duration).tint(.mint)
                }.padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(CaptionStyle.allCases, id: \.rawValue) { style in
                            Button(style.displayName) { updateCaption(index) { $0.style = style } }
                                .font(.caption.weight(.semibold)).foregroundStyle(caption.style == style ? .black : .white)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(caption.style == style ? .mint : .white.opacity(0.12)).clipShape(Capsule())
                        }
                    }.padding(.horizontal, 16)
                }
            } else {
                VStack(spacing: 6) {
                    Text(appText(language, "Zaman çizgisinden bir metin parçası seç.", "Select text from the timeline.")).font(.caption).foregroundStyle(.white.opacity(0.55))
                    Button(appText(language, "Yeni altyazı ekle", "Add caption")) { addCaption() }.font(.caption.weight(.bold)).foregroundStyle(.mint)
                }
            }
        }.frame(height: selectedCaptionIndex == nil ? 62 : 190)
    }

    private var audioPanel: some View { HStack { Toggle(appText(language, "Ses efektleri", "Sound effects"), isOn: $project.sfxEnabled).tint(.mint); Spacer() }.padding(.horizontal, 18).frame(height: 54) }
    private var effectsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(appText(language, "Altyazıları videoya işle", "Burn captions into video"), isOn: $project.captionsEnabled).tint(.mint)
            if let index = selectedCaptionIndex {
                let caption = project.captions[index]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        effectButton("Yok", behavior: .none, selected: caption.sceneBehavior, index: index)
                        effectButton("Yumuşak zoom", behavior: .subtleZoom, selected: caption.sceneBehavior, index: index)
                        effectButton("Darbe", behavior: .punchIn, selected: caption.sceneBehavior, index: index)
                        effectButton("Geçiş", behavior: .transitionWhoosh, selected: caption.sceneBehavior, index: index)
                        effectButton("Odak", behavior: .focusBlur, selected: caption.sceneBehavior, index: index)
                    }
                }
            } else {
                Text(appText(language, "Hareket eklemek için zaman çizgisinden bir altyazı seç.", "Select a caption from the timeline to add motion."))
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }.padding(.horizontal, 18).frame(height: 88, alignment: .leading)
    }

    private func action(_ title: String, _ icon: String, _ handler: @escaping () -> Void) -> some View { Button(action: handler) { Label(title, systemImage: icon).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.12)).clipShape(Capsule()) } }

    private func configurePlayer() { if let observer, let player { player.removeTimeObserver(observer) }; guard let url = project.finalCompositionURL else { return }; let p = AVPlayer(url: url); player = p; observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.08, preferredTimescale: 600), queue: .main) { value in Task { @MainActor in previewTime = value.seconds; playhead = value.seconds } } }
    private func seek(_ seconds: Double) { previewTime = seconds; playhead = seconds; player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private func setAction(_ index: Int, _ action: UGCEditDecision.EditAction) { undoStack.append(project.editDecisions); redoStack.removeAll(); let old = project.editDecisions[index]; project.editDecisions[index] = UGCEditDecision(id: old.id, takeID: old.takeID, groupID: old.groupID, startTime: old.startTime, endTime: old.endTime, action: action, reasonCode: action == .keep ? .manuallyRestored : .manuallyRemoved, reasonDescription: "User edit"); project.timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: project.editDecisions) }
    private func split(_ index: Int) { let old = project.editDecisions[index]; guard old.endTime - old.startTime > 0.6 else { return }; let cut = UGCEditDecisionEngine.sourceTime(forCleanTime: playhead, clips: clips).flatMap { $0 > old.startTime + 0.2 && $0 < old.endTime - 0.2 ? $0 : nil } ?? (old.startTime + old.endTime) / 2; undoStack.append(project.editDecisions); let l = UGCEditDecision(id: UUID(), takeID: old.takeID, groupID: old.groupID, startTime: old.startTime, endTime: cut, action: .keep, reasonCode: .keptByUser, reasonDescription: "Split"); let r = UGCEditDecision(id: UUID(), takeID: old.takeID, groupID: old.groupID, startTime: cut, endTime: old.endTime, action: .keep, reasonCode: .keptByUser, reasonDescription: "Split"); project.editDecisions.replaceSubrange(index...index, with: [l,r]); selectedDecisionID = r.id; project.timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: project.editDecisions) }
    private func trim(_ index: Int, start: Double, end: Double) { guard end - start >= 0.25 else { return }; let old = project.editDecisions[index]; project.editDecisions[index] = UGCEditDecision(id: old.id, takeID: old.takeID, groupID: old.groupID, startTime: start, endTime: end, action: old.action, reasonCode: .keptByUser, reasonDescription: "Trim"); project.timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: project.editDecisions) }
    private func inspectorSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { HStack(spacing: 5) { Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6)); Slider(value: value, in: range).tint(.mint).frame(width: 72) } }
    private func effectButton(_ title: String, behavior: CaptionSceneBehavior, selected: CaptionSceneBehavior, index: Int) -> some View {
        Button(title) { updateCaption(index) { caption in caption.sceneBehavior = behavior } }
            .font(.caption.weight(.semibold)).foregroundStyle(selected == behavior ? .black : .white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected == behavior ? .mint : .white.opacity(0.12)).clipShape(Capsule())
    }
    private func updateCaption(_ index: Int, _ mutation: @escaping (inout CaptionSegment) -> Void) { captionUndoStack.append(project.captions); captionRedoStack.removeAll(); mutation(&project.captions[index]) }
    private func addCaption() { captionUndoStack.append(project.captions); let start = min(playhead, max(0, duration - 1)); let caption = CaptionSegment(startTime: start, endTime: min(duration, start + 1.5), text: appText(language, "Yeni altyazı", "New caption"), role: .regular, style: .boldCenterViral); project.captions.append(caption); selectedCaptionID = caption.id }
    private func undo() { if let prior = captionUndoStack.popLast() { captionRedoStack.append(project.captions); project.captions = prior; return }; guard let prior = undoStack.popLast() else { return }; redoStack.append(project.editDecisions); project.editDecisions = prior; project.timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: prior) }
    private func redo() { if let next = captionRedoStack.popLast() { captionUndoStack.append(project.captions); project.captions = next; return }; guard let next = redoStack.popLast() else { return }; undoStack.append(project.editDecisions); project.editDecisions = next; project.timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: next) }
}

private struct TimelineFilmCell: View {
    let url: URL?; let time: Double; let width: CGFloat; let selected: Bool
    @State private var image: UIImage?
    var body: some View { Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.gray.opacity(0.35) } }.frame(width: width, height: 48).clipped().overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? .mint : .white.opacity(0.16), lineWidth: selected ? 2 : 1)).clipShape(RoundedRectangle(cornerRadius: 4)).task(id: "\(url?.absoluteString ?? "")-\(time)") { await load() } }
    @MainActor private func load() async { guard let url else { return }; let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 720, height: 1280); generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero; if let result = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) { image = UIImage(cgImage: result.image) } }
}

private struct TimelinePlayhead: View {
    let offset: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(width: 2, height: 112)
        }
        .offset(x: offset, y: 11)
    }
}
