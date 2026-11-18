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
                               projectId: project.id)
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
#error("RECON GAP: lines 261-588 of CreateScreen.swift unrecoverable")
        showEdit = true
#error("RECON GAP: lines 590-599 of CreateScreen.swift unrecoverable")
        showEdit = true
#error("RECON GAP: end of CreateScreen.swift unknown (file may continue past line 600)")
