import UIKit

/// MyKeyboard: Function's ":" emoji, a scrolling row of emoji in the bar between ⚡ and the
/// Hex key instead of the strip's three slots.
///
/// - A lone ":" after a space (or at the field's start) offers the emoji the sentence before
///   it points at (`EmojiSuggester`: its last words, newest first, and phrases), then the ones
///   you use most, then everyday ones.
/// - ":name" narrows to the emoji named so, in Portuguese and English (":dog", ":cach",
///   ":coração"), your use breaking ties (`EmojiShortcode`).
/// - A tap puts the emoji in place of the whole ":" or ":name"; a space, or any character a
///   name can't hold, closes the row.
///
/// Needs Settings › Experiments › Emoji shortcodes on, as the strip's own shortcodes do.
extension FullKeyboardView {
    /// How many emoji the row holds; about nine show at once, the rest scroll.
    static let falaEmojiRowLimit = 30

    /// The ":" token before the cursor and its emoji, or nil when the row has nothing to show.
    func falaEmojiPick() -> (token: String, entries: [Int])? {
        guard emojiShortcodesEnabled, engine.showsEmoji, !routedTarget.isSearching,
              emojiPanel == nil, !showsRecording, allowsEmojiShortcodes,
              let before = engine.typingContext ?? engine.textBefore else { return nil }
        // Only a ":" or ":name" at the end wakes the emoji index; other keystrokes stop here.
        let token = EmojiShortcode.token(before: before)
        guard token != nil || before.hasSuffix(":"), let library = loadEmojiLibrary() else { return nil }
        let usage = emojiUsageScores(makeEmojiUsage(), library: library)
        if let token {
            let entries = EmojiShortcode.matches(token: token, library: library, usage: usage, limit: Self.falaEmojiRowLimit)
            return entries.isEmpty ? nil : (token.text, entries)
        }
        guard before.hasSuffix(":") else { return nil }
        let head = String(before.dropLast())
        guard head.isEmpty || head.last?.isWhitespace == true else { return nil }
        // The sentence the ":" closes: its words, the newest counting most.
        let context = EmojiContext(before: head, stopwords: library.stopwords)
        let entries = EmojiSuggester.suggestions(context: context, library: library, usage: usage, limit: Self.falaEmojiRowLimit)
        return entries.isEmpty ? nil : (":", entries)
    }

    /// Shows, fills or hides the row; true while it shows, so the strip leaves its slots empty.
    @discardableResult
    func refreshFalaEmojiRow() -> Bool {
        let pick = stripView.isHidden ? nil : falaEmojiPick()
        guard let pick, let library = emojiLibrary else {
            falaEmojiToken = nil
            falaEmojiEntries = []
            falaEmojiRow?.isHidden = true
            return false
        }
        let row = falaEmojiRow ?? makeFalaEmojiRow()
        row.palette = palette
        if pick.entries != falaEmojiEntries {
            let usage = makeEmojiUsage()
            row.setItems(pick.entries.map { (emojiText($0, library: library, usage: usage), library.name(of: $0)) })
        }
        falaEmojiToken = pick.token
        falaEmojiEntries = pick.entries
        layoutFalaEmojiRow()
        row.isHidden = false
        bringSubviewToFront(row)
        return true
    }

    /// Function's row: the bar's whole width, behind ⚡ and the Hex key, centred on their line;
    /// the emoji start just past ⚡ and end just before the Hex key, one every 39 pt, and fade
    /// out under the two discs as they scroll.
    func layoutFalaEmojiRow() {
        guard let row = falaEmojiRow else { return }
        let layout = engine.layout
        let lift = stripView.frame.minY - layout.stripFrame.minY
        let bar = layout.stripBarFrame
        guard let disc = layout.functionDiscFrame else {
            row.frame = stripView.frame
            row.edgeInsets = (0, 0)
            row.edgeFade = 0
            return
        }
        let height: CGFloat = 44
        row.frame = CGRect(x: bar.minX, y: disc.midY + lift - height / 2, width: bar.width, height: height)
        // ⚡ and the Hex key sit as far in from either end, so one inset serves both.
        let inset = layout.hexOnLeading ? bar.maxX - disc.minX : disc.maxX - bar.minX
        row.edgeInsets = (inset + 2, inset + 2)
        row.edgeFade = 10
    }

    private func makeFalaEmojiRow() -> EmojiRowView {
        let row = EmojiRowView()
        row.fontSize = 25
        row.itemPitch = 39
        row.palette = palette
        row.onPick = { [weak self] index in self?.pickFalaEmoji(at: index) }
        insertSubview(row, aboveSubview: stripView)
        falaEmojiRow = row
        return row
    }

    private func pickFalaEmoji(at index: Int) {
        guard index < falaEmojiEntries.count, let token = falaEmojiToken,
              let library = emojiLibrary else { return }
        let entry = falaEmojiEntries[index]
        let usage = makeEmojiUsage()
        let emoji = emojiText(entry, library: library, usage: usage)
        keyFeedback()
        let typed = EmojiShortcode.Token(name: String(token.dropFirst()), text: token)
        if engine.replaceEmojiShortcode(emoji, token: typed) {
            usage.record(library.entries[entry].emoji)
        }
        refreshStrip()
    }
}
