import SwiftUI
import AVKit
import PhotosUI

/// Thin cloud-editing flow: pick a talking-head video → compress → upload →
/// the server cuts silences/bad-takes, burns captions → before/after + share.
/// The on-device editor (EditScreen) is untouched; this is an additive path.
struct CloudEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = CloudEditModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var importService = VideoImportService()

    var body: some View {
        ZStack {
            CutSenseTheme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("Bulut Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await importService.importVideo(from: item)
                if let url = importService.importedVideoURL {
                    await model.start(sourceURL: url)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            idleView
        case .preparing, .uploading, .processing:
            progressView
        case let .done(raw, final, localFinal):
            ResultView(rawURL: raw, finalURL: final, localFinal: localFinal) {
                model.reset()
            }
        case let .failed(message):
            failedView(message)
        }
    }

    private var idleView: some View {
        VStack(spacing: CutSenseTheme.spacingLG) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(CutSenseTheme.accent)
            Text("Ham konuşma videonu yükle")
                .font(CutSenseTheme.titleL)
                .foregroundStyle(CutSenseTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Sessizlikler ve bozuk çekimler kesilir, altyazılar eklenir, 9:16 Reels formatında geri gelir.")
                .font(CutSenseTheme.bodyReg)
                .foregroundStyle(CutSenseTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CutSenseTheme.spacingLG)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Text("Video Seç")
                    .font(CutSenseTheme.bodyEmph)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CutSenseTheme.accent, in: RoundedRectangle(cornerRadius: CutSenseTheme.radiusLG))
            }
            .padding(.horizontal, CutSenseTheme.spacingLG)
            Text("Beta · işlem birkaç dakika sürebilir")
                .font(CutSenseTheme.label)
                .foregroundStyle(CutSenseTheme.textMuted)
                .padding(.bottom, CutSenseTheme.spacingLG)
        }
    }

    private var progressView: some View {
        VStack(spacing: CutSenseTheme.spacingLG) {
            Spacer()
            GlassCard {
                VStack(spacing: CutSenseTheme.spacingMD) {
                    ProgressView(value: model.fraction)
                        .tint(CutSenseTheme.accent)
                    Text(model.phaseLabel)
                        .font(CutSenseTheme.bodyEmph)
                        .foregroundStyle(CutSenseTheme.textPrimary)
                    Text("\(Int(model.fraction * 100))%")
                        .font(CutSenseTheme.label)
                        .foregroundStyle(CutSenseTheme.textSecondary)
                }
            }
            .padding(.horizontal, CutSenseTheme.spacingLG)
            Spacer()
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: CutSenseTheme.spacingMD) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(CutSenseTheme.error)
            Text("İşlem başarısız")
                .font(CutSenseTheme.titleL)
                .foregroundStyle(CutSenseTheme.textPrimary)
            Text(message)
                .font(CutSenseTheme.bodyReg)
                .foregroundStyle(CutSenseTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CutSenseTheme.spacingLG)
            Button("Tekrar dene") { model.reset() }
                .font(CutSenseTheme.bodyEmph)
                .foregroundStyle(CutSenseTheme.accent)
                .padding(.top, CutSenseTheme.spacingSM)
            Spacer()
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class CloudEditModel {
    enum Phase {
        case idle
        case preparing
        case uploading
        case processing(stage: String, progress: Int)
        case done(raw: URL, final: URL, localFinal: URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var fraction: Double {
        switch phase {
        case .preparing: return 0.05
        case .uploading: return 0.12
        case let .processing(_, p): return max(0.12, Double(p) / 100.0)
        case .done: return 1
        default: return 0
        }
    }

    var phaseLabel: String {
        switch phase {
        case .preparing: return "Video hazırlanıyor…"
        case .uploading: return "Yükleniyor…"
        case let .processing(stage, _): return Self.stageLabel(stage)
        default: return ""
        }
    }

    func reset() { phase = .idle }

    func start(sourceURL: URL) async {
        do {
            phase = .preparing
            let compressed = try await VideoCompressor.compress(sourceURL)

            phase = .uploading
            let job = try await CloudJobClient.shared.createJob()
            try await CloudJobClient.shared.uploadRaw(fileURL: compressed, job: job)
            try await CloudJobClient.shared.enqueue(jobId: job.job_id)

            phase = .processing(stage: "queued", progress: 0)
            while true {
                try await Task.sleep(for: .seconds(2))
                let s = try await CloudJobClient.shared.status(jobId: job.job_id)
                if s.status == "done" {
                    guard let rawStr = s.raw_url, let finalStr = s.final_url,
                          let raw = URL(string: rawStr), let final = URL(string: finalStr) else {
                        phase = .failed("Sonuç bağlantısı alınamadı.")
                        return
                    }
                    let localFinal = try await CloudJobClient.shared.download(finalStr)
                    phase = .done(raw: raw, final: final, localFinal: localFinal)
                    return
                }
                if s.status == "failed" {
                    phase = .failed(s.error ?? "Sunucu işlemi başarısız oldu.")
                    return
                }
                phase = .processing(stage: s.status, progress: s.progress)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    static func stageLabel(_ s: String) -> String {
        switch s {
        case "queued": return "Sırada bekliyor…"
        case "normalizing": return "Hazırlanıyor…"
        case "transcribing": return "Konuşma çözümleniyor…"
        case "analyzing": return "Bozuk çekimler bulunuyor…"
        case "planning": return "Kesim planı çıkarılıyor…"
        case "rendering_clean": return "Kesiliyor…"
        case "captioning": return "Altyazılar hazırlanıyor…"
        case "rendering_final": return "Altyazılar işleniyor…"
        case "qa": return "Kalite kontrol…"
        case "uploading": return "Sonuç yükleniyor…"
        default: return "İşleniyor…"
        }
    }
}

// MARK: - Result (before / after)

private struct ResultView: View {
    let rawURL: URL
    let finalURL: URL
    let localFinal: URL
    let onDone: () -> Void

    @State private var rawPlayer: AVPlayer?
    @State private var finalPlayer: AVPlayer?

    var body: some View {
        VStack(spacing: CutSenseTheme.spacingMD) {
            HStack(spacing: CutSenseTheme.spacingMD) {
                labeledPlayer("Önce", player: rawPlayer)
                labeledPlayer("Sonra", player: finalPlayer)
            }
            .padding(.horizontal, CutSenseTheme.spacingMD)
            .padding(.top, CutSenseTheme.spacingMD)

            ShareLink(item: localFinal) {
                Text("Paylaş / Kaydet")
                    .font(CutSenseTheme.bodyEmph)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CutSenseTheme.accent, in: RoundedRectangle(cornerRadius: CutSenseTheme.radiusLG))
            }
            .padding(.horizontal, CutSenseTheme.spacingLG)

            Button("Yeni video", action: onDone)
                .font(CutSenseTheme.bodyEmph)
                .foregroundStyle(CutSenseTheme.textSecondary)
                .padding(.bottom, CutSenseTheme.spacingLG)
        }
        .onAppear {
            rawPlayer = AVPlayer(url: rawURL)
            finalPlayer = AVPlayer(url: finalURL)
            finalPlayer?.play()
        }
        .onDisappear {
            rawPlayer?.pause()
            finalPlayer?.pause()
        }
    }

    private func labeledPlayer(_ title: String, player: AVPlayer?) -> some View {
        VStack(spacing: CutSenseTheme.spacingSM) {
            Text(title)
                .font(CutSenseTheme.label)
                .foregroundStyle(CutSenseTheme.textSecondary)
            VideoPlayer(player: player)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CutSenseTheme.radiusSM))
        }
    }
}
