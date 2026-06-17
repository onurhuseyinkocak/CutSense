import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - CreateScreen
// Primary home tab — Mojo-style hero with create CTA, recent projects, template carousel.

struct CreateScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = ProjectsViewModel()
    @State private var importService = VideoImportService()
    @State private var selectedItem: PhotosPickerItem?

    @State private var activeProject: Project?
    @State private var activeVideoURL: URL?
    @State private var showEdit = false
    @State private var preselectedTemplate: TemplateConfig?
    @State private var isCreating = false
    @State private var deletionCandidate: Project?
    @State private var showCloud = false

    var body: some View {
        NavigationStack {
            ZStack {
                CutSenseTheme.canvas.ignoresSafeArea()
                MeshGradientBackdrop()
                    .opacity(0.85)

                ScrollView {
                    VStack(spacing: CutSenseTheme.spacingXL) {
                        topHeader
                            .padding(.top, 12)

                        heroCreateCard
                            .padding(.horizontal, 20)

                        recentProjectsSection
                            .padding(.horizontal, 20)

                        templateCarousel
                            .padding(.horizontal, 20)

                        statsRow
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }
                }

                if isCreating || importService.isImporting {
                    importingOverlay
                }

                if let msg = currentErrorMessage {
                    VStack {
                        ErrorBanner(message: msg)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onTapGesture {
                                importService.errorMessage = nil
                                viewModel.errorMessage = nil
                            }
                            .task(id: msg) {
                                // Auto-dismiss after 4 seconds so a stale
                                // error doesn't stay glued to the screen.
                                try? await Task.sleep(nanoseconds: 4_000_000_000)
                                if currentErrorMessage == msg {
                                    importService.errorMessage = nil
                                    viewModel.errorMessage = nil
                                }
                            }
                        Spacer()
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: msg)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .photosPicker(isPresented: photosBinding,
                          selection: $selectedItem,
                          matching: .videos)
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task { await handleVideoImport(newItem) }
            }
            .task {
                guard let userId = authManager.effectiveUserId else { return }
                await viewModel.loadProjects(userId: userId)
            }
            .refreshable {
                guard let userId = authManager.effectiveUserId else { return }
                await viewModel.loadProjects(userId: userId)
            }
            .navigationDestination(isPresented: $showEdit) {
                if let project = activeProject, let url = activeVideoURL {
                    EditScreen(videoURL: url,
                               projectId: project.id,
                               initialTemplate: preselectedTemplate)
                }
            }
            .sheet(isPresented: $showCloud) {
                NavigationStack { CloudEditScreen() }
            }
            .alert(item: $deletionCandidate) { project in
                Alert(
                    title: Text("Delete \(project.title)?"),
                    message: Text("This permanently removes the project."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task { await viewModel.deleteProject(project) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: Header

    private var topHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CutSense")
                    .font(CutSenseTheme.titleHero)
                    .foregroundStyle(.white)
                Text("Cinematic edits in seconds")
                    .font(CutSenseTheme.labelSmall)
                    .tracking(2)
                    .foregroundStyle(CutSenseTheme.accent)
            }
            Spacer()

            Button {
                showCloud = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                    Circle()
                        .strokeBorder(CutSenseTheme.accent.opacity(0.6), lineWidth: 1)
                        .frame(width: 40, height: 40)
                    Image(systemName: "cloud.bolt.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CutSenseTheme.accent)
                }
            }
            .accessibilityLabel("Bulut Düzenle")
            .padding(.trailing, 8)

            NavigationLink {
                AccountScreen()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                    Circle()
                        .strokeBorder(CutSenseTheme.border, lineWidth: 1)
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, 22)
    }

    // MARK: Hero Create Card

    private var heroCreateCard: some View {
        Button {
            HapticEngine.impact()
            preselectedTemplate = nil
            selectedItem = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                pickerTrigger.toggle()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(CutSenseTheme.surfaceHigh)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("NEW", systemImage: "sparkle")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(CutSenseTheme.surfaceElevated))

                        Spacer()
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create new video")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text("Pick a clip — we cut, caption, and color-grade it.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CutSenseTheme.textSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        capabilityChip(icon: "scissors", label: "Auto-cut")
                        capabilityChip(icon: "text.bubble.fill", label: "Captions")
                        capabilityChip(icon: "paintbrush.fill", label: "Grade")
                    }
                }
                .padding(22)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .pressableScale()
    }

    private func capabilityChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
            Text(label)
                .font(.system(size: 11, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(CutSenseTheme.surfaceElevated))
    }

    // MARK: Recent Projects

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your projects")
                    .font(CutSenseTheme.titleM)
                    .foregroundStyle(.white)
                if !viewModel.projects.isEmpty {
                    Text("\(viewModel.projects.count)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(CutSenseTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CutSenseTheme.accent.opacity(0.15)))
                }
                Spacer()
            }

            if viewModel.projects.isEmpty {
                emptyProjects
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.projects) { project in
                            ProjectCard(project: project) {
                                resumeProject(project)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deletionCandidate = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var emptyProjects: some View {
        GlassCard(corner: 22, padding: 22) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(CutSenseTheme.accent)
                    Text("Start with a template")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Pick a vibe and we'll edit your clip the moment you pick it.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(CutSenseTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    ForEach(emptyStateTemplates, id: \.id) { template in
                        emptyStateTile(template)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyStateTemplates: [TemplateConfig] {
        // Calm template first so accidental taps land on a forgiving look;
        // viral_caption (high intensity) stays in the line-up but isn't the
        // default eye-catch.
        let ids = ["premium_founder", "viral_caption", "podcast_highlights"]
        return ids.compactMap { id in TemplateConfig.all.first { $0.id == id } }
    }

    private func emptyStateTile(_ template: TemplateConfig) -> some View {
        Button {
            preselectedTemplate = template
            selectedItem = nil
            pickerTrigger.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: emptyTileIcon(for: template.id))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(template.name)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(emptyTileGradient(for: template.id))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func emptyTileIcon(for id: String) -> String {
        switch id {
        case "viral_caption":      return "flame.fill"
        case "premium_founder":    return "crown.fill"
        case "podcast_highlights": return "waveform"
        default:                    return "sparkles"
        }
    }

    private func emptyTileGradient(for id: String) -> LinearGradient {
        LinearGradient(
            colors: [CutSenseTheme.surfaceHigh, CutSenseTheme.surface, Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Template Carousel

    private var templateCarousel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Try a template")
                    .font(CutSenseTheme.titleM)
                    .foregroundStyle(.white)
                Spacer()
                NavigationLink {
                    TemplatesTabScreen()
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "arrow.right")
                    }
                    .font(CutSenseTheme.label)
                    .foregroundStyle(CutSenseTheme.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(TemplateConfig.all.prefix(8), id: \.id) { template in
                        TemplatePreviewCard(template: template) {
                            preselectedTemplate = template
                            selectedItem = nil
                            pickerTrigger.toggle()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(icon: "scissors", value: "AI", label: "Auto-cut")
            statTile(icon: "text.alignleft", value: "10+", label: "Caption styles")
            statTile(icon: "square.grid.3x3.fill", value: "16", label: "Templates")
        }
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CutSenseTheme.accent)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CutSenseTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassSurface(corner: 18)
    }

    // MARK: Overlay

    private var importingOverlay: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                Color.black.opacity(0.78).ignoresSafeArea()

                VStack(spacing: 22) {
                    HeroOrb(size: 110)
                        .padding(.bottom, 4)

                    VStack(spacing: 6) {
                        Text("Hazırlanıyor")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(importingMessage)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                        HStack(spacing: 10) {
                            Text(elapsedString)
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                            if importService.downloadProgress >= 0 {
                                Text(String(format: "%d%%", Int(importService.downloadProgress * 100)))
                                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(CutSenseTheme.accent)
                            }
                        }
                        .padding(.top, 2)
                    }

                    // Real progress bar when iCloud is reporting %; falls
                    // back to indeterminate spinner otherwise.
                    if importService.downloadProgress >= 0 {
                        ProgressView(value: importService.downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(CutSenseTheme.accent)
                            .frame(width: 220)
                            .padding(.top, 4)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.regular)
                            .padding(.top, 2)
                    }

                    Button(role: .cancel) {
                        importService.cancelImport()
                    } label: {
                        Text("İptal")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(minWidth: 110)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(.white.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                            )
                    }
                    .padding(.top, 6)
                }
                .padding(.vertical, 36)
                .padding(.horizontal, 44)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
            }
            .transition(.opacity)
        }
    }

    private var elapsedString: String {
        let total = importService.elapsedSeconds
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var importingMessage: String {
        if importService.downloadProgress >= 0, importService.downloadProgress < 1 {
            return "Video iCloud'dan indiriliyor"
        }
        let secs = importService.elapsedSeconds
        if secs < 6 {
            return "Videon hazırlanıyor"
        } else if secs < 25 {
            return "Büyük dosyayı taşıyoruz, birkaç saniye"
        } else {
            return "Video iCloud'dan indiriliyor; büyük dosyalarda 1-2 dakika sürebilir"
        }
    }

    // MARK: Plumbing

    @State private var pickerTrigger: Bool = false
    private var photosBinding: Binding<Bool> {
        Binding(
            get: { pickerTrigger },
            set: { newVal in
                pickerTrigger = newVal
            }
        )
    }

    private var currentErrorMessage: String? {
        importService.errorMessage ?? viewModel.errorMessage
    }

    private func handleVideoImport(_ item: PhotosPickerItem) async {
        isCreating = true
        defer {
            isCreating = false
            selectedItem = nil
        }
        await importService.importVideo(from: item)
        guard let videoURL = importService.importedVideoURL else { return }
        guard let metadata = importService.metadata else {
            viewModel.errorMessage = "Video bilgileri okunamadı. Lütfen farklı bir dosya deneyin."
            return
        }
        guard let userId = authManager.effectiveUserId else { return }

        let title = "Video \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        guard var project = await viewModel.createProject(userId: userId, title: title) else { return }

        if let template = preselectedTemplate {
            project.selectedTemplate = template.id
        }

        let pipeline = PipelineRepository()
        try? await pipeline.updateProjectImportMetadata(
            projectId: project.id,
            path: videoURL.path,
            metadata: metadata
        )

        project.status = .imported
        project.localProjectPath = VideoStorage.persistentToken(for: videoURL)
        project.sourceFileName = videoURL.lastPathComponent
        project.originalDuration = metadata.duration
        viewModel.replaceProject(project)

        activeProject = project
        activeVideoURL = videoURL
        showEdit = true
    }

    private func resumeProject(_ project: Project) {
        guard let token = project.localProjectPath,
              let url = VideoStorage.resolve(token) else {
            viewModel.errorMessage = "Video bu cihazda bulunamadı. Yeniden içe aktar."
            return
        }
        activeProject = project
        activeVideoURL = url
        showEdit = true
    }
}

// MARK: - Project Card

private struct ProjectCard: View {
    let project: Project
    var onTap: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            HapticEngine.select()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        CutSenseTheme.canvasGradient
                        Image(systemName: "film")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(CutSenseTheme.textTertiary)
                    }

                    // Status pill bottom-right
                    VStack {
                        HStack {
                            Spacer()
                            statusPill
                                .padding(8)
                        }
                        Spacer()
                    }
                }
                .frame(width: 170, height: 226)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let duration = project.originalDuration {
                            Label(formatDuration(duration), systemImage: "clock")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(CutSenseTheme.textTertiary)
                                .labelStyle(.titleAndIcon)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(width: 170, alignment: .leading)
                .background(Color.white.opacity(0.04))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CutSenseTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .pressableScale()
        .task {
            await loadThumbnail()
        }
    }

    private var statusPill: some View {
        let (label, color) = statusInfo
        return Text(label)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .overlay(Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1))
            )
    }

    private var statusInfo: (String, Color) {
        switch project.status {
        case .exported: return ("DONE", CutSenseTheme.accent)
        case .exporting, .analyzing: return ("WORKING", CutSenseTheme.accentWarm)
        case .failed: return ("FAILED", CutSenseTheme.error)
        case .roughCutReady, .reviewed, .styling: return ("EDIT", CutSenseTheme.accentSecondary)
        case .imported, .draft: return ("READY", Color.white.opacity(0.85))
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func loadThumbnail() async {
        guard let token = project.localProjectPath,
              let url = VideoStorage.resolve(token) else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 480)
        do {
            let cgImage = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
            await MainActor.run {
                thumbnail = UIImage(cgImage: cgImage)
            }
        } catch {
            // silent — placeholder shown
        }
    }
}

// MARK: - Template Preview Card

private struct TemplatePreviewCard: View {
    let template: TemplateConfig
    var onTap: () -> Void

    var body: some View {
        // No `Button` wrapper — Button intercepts horizontal pan and the
        // ScrollView couldn't recognize a swipe that started over a tile.
        // onTapGesture defers to scroll, so swiping across cards now scrolls
        // and a clean tap still triggers selection.
        ZStack(alignment: .bottomLeading) {
            gradientFor(template)

            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 4, height: 4)
                    .offset(x: CGFloat([-40, 30, -10, 50, -50, 20][i]),
                            y: CGFloat([-60, -70, 40, -20, 60, 70][i]))
            }

            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: iconFor(template))
                        .font(.system(size: 9, weight: .black))
                    Text(categoryLabel(template))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(CutSenseTheme.surfaceElevated))

                Text(template.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(12)
        }
        .frame(width: 140, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            HapticEngine.select()
            onTap()
        }
    }

    private func gradientFor(_ t: TemplateConfig) -> LinearGradient {
        LinearGradient(
            colors: [CutSenseTheme.surfaceHigh, CutSenseTheme.surface, Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func iconFor(_ t: TemplateConfig) -> String {
        switch t.category {
        case .professional: "briefcase.fill"
        case .social: "flame.fill"
        case .lifestyle: "sparkles"
        case .creative: "paintpalette.fill"
        }
    }

    private func categoryLabel(_ t: TemplateConfig) -> String {
        switch t.category {
        case .professional: "PRO"
        case .social: "VIRAL"
        case .lifestyle: "VIBE"
        case .creative: "ART"
        }
    }
}
