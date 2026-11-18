#error("RECON GAP: lines 1-163 of SilenceCutScreen.swift unrecoverable")
                Task { await vm.export() }
#error("RECON GAP: lines 165-168 of SilenceCutScreen.swift unrecoverable")
                    Text("Sessizlikleri Kes  ·  \(timeString(vm.finalDuration))")
#error("RECON GAP: lines 170-211 of SilenceCutScreen.swift unrecoverable")
    private var isSpeech: Bool { block.kind == .speech }
#error("RECON GAP: lines 213-219 of SilenceCutScreen.swift unrecoverable")
                Text(isSpeech ? "Konuşma" : "Sessizlik")
#error("RECON GAP: lines 221-226 of SilenceCutScreen.swift unrecoverable")
                if !isSpeech {
#error("RECON GAP: lines 228-238 of SilenceCutScreen.swift unrecoverable")
                Text(isRemoved ? "Kesildi" : "Tutuldu")
#error("RECON GAP: lines 240-257 of SilenceCutScreen.swift unrecoverable")
        .task(id: block.id) { if isSpeech { await loadThumb() } }
#error("RECON GAP: lines 259-263 of SilenceCutScreen.swift unrecoverable")
                if isSpeech, let thumbnail {
#error("RECON GAP: lines 265-266 of SilenceCutScreen.swift unrecoverable")
                    (isSpeech ? CutSenseTheme.surfaceElevated : Color.black.opacity(0.5))
                    Image(systemName: isSpeech ? "play.fill" : "speaker.slash.fill")
#error("RECON GAP: lines 269-269 of SilenceCutScreen.swift unrecoverable")
                        .foregroundStyle(isSpeech ? .white : CutSenseTheme.textTertiary)
#error("RECON GAP: end of SilenceCutScreen.swift unknown (file may continue past line 270)")
