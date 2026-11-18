#error("RECON GAP: lines 1-4 of CaptionPreviewPlayer.swift unrecoverable")
struct CaptionPreviewPlayer: View {
#error("RECON GAP: lines 6-11 of CaptionPreviewPlayer.swift unrecoverable")
    var onEditCaption: ((CaptionSegment) -> Void)?
#error("RECON GAP: lines 13-15 of CaptionPreviewPlayer.swift unrecoverable")
    @State private var isLoading = true
#error("RECON GAP: lines 17-40 of CaptionPreviewPlayer.swift unrecoverable")
            } else if isLoading {
#error("RECON GAP: lines 42-160 of CaptionPreviewPlayer.swift unrecoverable")
                            onEditCaption?(caption)
#error("RECON GAP: lines 162-177 of CaptionPreviewPlayer.swift unrecoverable")
        let theme = template.captionTheme
#error("RECON GAP: lines 179-263 of CaptionPreviewPlayer.swift unrecoverable")
    private func styledBackground(_ style: CaptionStyle, theme: TemplateConfig.CaptionTheme) -> some View {
#error("RECON GAP: lines 265-293 of CaptionPreviewPlayer.swift unrecoverable")
    private func styleFont(_ style: CaptionStyle, weight: Font.Weight, size: CGFloat) -> Font {
#error("RECON GAP: lines 295-382 of CaptionPreviewPlayer.swift unrecoverable")
                                .fill(colorForRole(caption.role, theme: template.captionTheme))
#error("RECON GAP: lines 384-498 of CaptionPreviewPlayer.swift unrecoverable")
            // Skip back 2s
#error("RECON GAP: lines 500-508 of CaptionPreviewPlayer.swift unrecoverable")
            .accessibilityLabel("Skip back 2 seconds")
#error("RECON GAP: lines 510-518 of CaptionPreviewPlayer.swift unrecoverable")
            // Skip forward 2s
#error("RECON GAP: lines 520-528 of CaptionPreviewPlayer.swift unrecoverable")
            .accessibilityLabel("Skip forward 2 seconds")
#error("RECON GAP: lines 530-618 of CaptionPreviewPlayer.swift unrecoverable")
            isLoading = false
#error("RECON GAP: lines 620-633 of CaptionPreviewPlayer.swift unrecoverable")
            isLoading = false
#error("RECON GAP: lines 635-758 of CaptionPreviewPlayer.swift unrecoverable")
private struct CaptionPlayerView: UIViewRepresentable {
#error("RECON GAP: lines 760-772 of CaptionPreviewPlayer.swift unrecoverable")
class CaptionPlayerUIView: UIView {
#error("RECON GAP: lines 774-790 of CaptionPreviewPlayer.swift unrecoverable")
    required init?(coder: NSCoder) { fatalError() }
#error("RECON GAP: end of CaptionPreviewPlayer.swift unknown (file may continue past line 791)")
