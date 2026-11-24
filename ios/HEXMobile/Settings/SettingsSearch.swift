import SwiftUI

/// MyKeyboard: a setting the home screen's search finds, the page it is on, and words it is
/// also found by (Portuguese and English), so "microfone", "vibração" or "tom de pele" lead
/// to the right page.
struct SettingsSearchEntry: Identifiable, Hashable {
    let title: String
    let page: SettingsPage
    let terms: String
    var id: String { page.rawValue + "/" + title }
}

enum SettingsSearchIndex {
    private static func e(_ title: String, _ page: SettingsPage, _ terms: String = "") -> SettingsSearchEntry {
        SettingsSearchEntry(title: title, page: page, terms: terms)
    }

    static let entries: [SettingsSearchEntry] = [
        // Keyboard
        e("Keyboard", .keyboard, "teclado completo barra de ditado modo"),
        e("Auto-start", .keyboard, "iniciar automaticamente começar ditado sozinho"),
        e("Microphone", .keyboard, "microfone fone fones airpods bluetooth iphone externo headset"),
        e("Languages", .keyboard, "idiomas idioma língua português inglês bilíngue layout"),
        e("Hex key", .keyboard, "tecla hex posição botão ditado"),
        e("Number row", .keyboard, "fileira de números linha números"),
        e("Autocorrect", .keyboard, "autocorreção corretor correção ortográfica"),
        e("Spatial autocorrect", .keyboard, "autocorreção espacial toque posição"),
        e("Strength", .keyboard, "força intensidade autocorreção"),
        e("Auto-capitalization", .keyboard, "maiúscula automática capitalização"),
        e("Swipe typing", .keyboard, "deslizar swipe digitar deslizando quickpath"),
        e("Suggest swear words", .keyboard, "palavrões sugerir palavrão"),
        e("Haptics", .keyboard, "vibração háptico tátil retorno"),
        e("Key pop-ups", .keyboard, "balão tecla popup ampliar letra"),
        e("Feedback", .keyboard, "retorno som vibração"),
        e("Emoji", .keyboard, "emojis histórico sugestões figurinhas"),
        e("Tom de pele", .keyboard, "skin tone emoji cor pele"),
        e("Typing", .keyboard, "digitação treinar praticar"),
        // Dictation
        e("Microphone", .dictation, "microfone fone fones airpods bluetooth iphone externo headset"),
        e("Style", .dictation, "estilo formatação transcrição"),
        e("Clean up what I say", .dictation, "limpar limpeza vícios hesitações tipo né éé"),
        e("Formatting", .dictation, "formatação pontuação"),
        e("End with a period", .dictation, "terminar com ponto final"),
        e("Format lists", .dictation, "listas formatar tópicos"),
        e("Numbers as digits", .dictation, "números algarismos dígitos"),
        e("Spoken punctuation", .dictation, "pontuação falada vírgula ponto falado"),
        e("Lowercase", .dictation, "minúsculas letras pequenas"),
        e("Custom vocabulary", .dictation, "vocabulário palavras nomes personalizados"),
        e("Keep mic warm", .dictation, "manter microfone ligado aquecido rápido"),
        e("Live words", .dictation, "palavras ao vivo prévia tempo real"),
        e("Speech model in keyboard", .dictation, "modelo de fala parakeet baixar teclado offline"),
        // Privacy
        e("Learn how I type", .privacy, "aprender digitação personalizar"),
        e("Typing logs", .privacy, "registros logs digitação"),
        e("Record typing logs", .privacy, "gravar registros logs"),
        // Experiments
        e("Two-language dictation", .experiments, "ditado dois idiomas bilíngue"),
        e("Voice isolation", .experiments, "isolamento de voz ruído barulho"),
        e("Clean up with Apple Intelligence", .experiments, "apple intelligence limpar ia"),
        e("Multilingual model (Parakeet)", .experiments, "modelo multilíngue parakeet idiomas"),
        e("Swipe typing in more languages", .experiments, "deslizar swipe outros idiomas"),
        e("Keyboard themes", .experiments, "temas tema cores aparência"),
        e("Keyboard layout", .experiments, "layout disposição teclas dvorak"),
        e("Quick accents", .experiments, "acentos rápidos acentuação"),
        e("Emoji shortcodes", .experiments, "atalhos emoji dois pontos"),
        e("Hide word suggestions", .experiments, "esconder sugestões ocultar palavras"),
        e("Comma and period keys", .experiments, "teclas vírgula ponto"),
        e("Two-thumb selection", .experiments, "seleção dois polegares cursor"),
        e("Adaptive touch", .experiments, "toque adaptativo precisão"),
        e("Delete swiped words letter by letter", .experiments, "apagar palavra deslizada letra por letra"),
        e("Learn each language separately", .experiments, "aprender idiomas separado"),
        e("ABC under the emoji key", .experiments, "abc tecla emoji"),
        e("Join the keyboard when unfolded", .experiments, "juntar teclado dobrável"),
    ]

    /// Every word of the query, accents and case aside, in the title, the page's name or the terms.
    static func matches(_ query: String) -> [SettingsSearchEntry] {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            let hay = fold(String(localized: String.LocalizationValue(entry.title)) + " " + entry.title + " "
                + entry.page.title + " " + entry.terms)
            return words.allSatisfy { hay.contains($0) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The search field on the home screen.
struct SettingsSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HexTheme.textMuted)
            TextField("Buscar ajustes", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(HexTheme.textBase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(HexTheme.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: HexTheme.controlRadius, style: .continuous)
                .fill(HexTheme.layer01)
        )
    }
}

/// The settings a search found, each opening its page; or a line saying there are none.
struct SettingsSearchResults: View {
    let query: String
    let open: (SettingsPage) -> Void

    var body: some View {
        let found = SettingsSearchIndex.matches(query)
        SettingsCard {
            if found.isEmpty {
                Text("Nenhum ajuste encontrado")
                    .font(.system(size: 15))
                    .foregroundStyle(HexTheme.textMuted)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            } else {
                ForEach(Array(found.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { SettingsDivider(leading: 50) }
                    Button {
                        open(entry.page)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.page.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(HexTheme.textMuted)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(localized: String.LocalizationValue(entry.title)))
                                    .font(.system(size: 15))
                                    .foregroundStyle(HexTheme.textBase)
                                Text(entry.page.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(HexTheme.textMuted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HexTheme.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
