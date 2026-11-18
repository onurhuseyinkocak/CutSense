import SwiftUI

struct LanguageSwitcher: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageRaw = language.rawValue
                } label: {
                    Text(language.shortTitle)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .frame(width: 44, height: 34)
                        .background(isSelected(language) ? Color.white : Color.white.opacity(0.08))
                        .foregroundStyle(isSelected(language) ? Color.black : Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.title)
                .accessibilityIdentifier("language_\(language.rawValue)")
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12)))
    }

    private func isSelected(_ language: AppLanguage) -> Bool {
        AppLanguage.value(from: languageRaw) == language
    }
}
