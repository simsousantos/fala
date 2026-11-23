import UIKit

/// Fala: the Function keyboard's bar on top of Hex's. A ⚡ disc at the end of Apple's bar
/// opposite the Hex key opens iOS's own menu (Reescrever, Formalizar, Traduzir ›, Ajustes);
/// right after a dictation it gives way to two shortcuts (traduzir, formalizar). While an
/// action runs the strip says so ("Reescrevendo…"), and once the text is replaced the strip's
/// Desfazer chip puts the old text back.
///
/// Every disc takes its place from `KeyboardLayout.functionDiscFrame`, on the words' line, so
/// it stays put whether or not iOS draws its 17 pt band above the keyboard.

/// The text a ⚡ action replaced, so Desfazer can put it back.
struct FalaFunctionUndo {
    let inserted: String
    let original: String
}

/// A Function-style disc in the bar: the key's fill in a circle and an SF Symbol in the keys'
/// ink, a shade darker while pressed. A touch a little outside the disc still counts.
@MainActor
final class FunctionDiscButton: UIButton {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { applyLook() } } }
    var symbolName = "bolt.fill" { didSet { if symbolName != oldValue { applyLook() } } }
    /// How far past the disc a touch still lands on it.
    var hitOutset: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .circular
        applyLook()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool { didSet { applyFill() } }
    override var isEnabled: Bool { didSet { applyFill() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitOutset, dy: -hitOutset).contains(point)
    }

    private func applyLook() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(palette.textBase, renderingMode: .alwaysOriginal)
        setImage(image, for: .normal)
        setImage(image, for: .highlighted)
        applyFill()
    }

    private func applyFill() {
        backgroundColor = isHighlighted ? palette.keyPressedFill : palette.keyFill
        alpha = isEnabled ? 1 : 0.45
    }
}

/// Fala, temporary: while true, an empty field's strip shows what the keyboard can measure of
/// its place on screen, to look for a sign of the 17 pt iOS sometimes draws above it.
enum FalaDebug {
    static let showsGeometry = false
}

@MainActor
extension FullKeyboardView {
    /// The last geometry shown, so a layout pass refreshes the strip only when it changed.
    static var falaLastGeometry = ""

    /// Heights from this view up to its window, the keyboard's spot in the window, the
    /// window's frame and the screen: `Y0 W0/336 S852 A0,34 [320 336 336]`.
    func falaGeometryText() -> String {
        guard let window else { return "sem janela" }
        var chain: [String] = []
        var view: UIView? = self
        while let current = view, chain.count < 6 {
            chain.append(String(Int(current.bounds.height.rounded())))
            view = current.superview
        }
        let inWindow = convert(bounds, to: window)
        let screen = window.windowScene?.screen.bounds.height ?? 0
        let insets = window.safeAreaInsets
        return "Y\(Int(inWindow.minY)) W\(Int(window.frame.minY))/\(Int(window.frame.height)) "
            + "S\(Int(screen)) A\(Int(insets.top)),\(Int(insets.bottom)) [\(chain.joined(separator: " "))]"
    }

    /// The geometry for the strip's status: only while debugging, and only in an empty field.
    var falaGeometryStatus: String? {
        guard FalaDebug.showsGeometry, !engine.target.hasText else { return nil }
        return falaGeometryText()
    }

    /// Builds the discs once, from `init`, just above the Hex key (under the emoji panel and
    /// the key callouts).
    func setUpFunctionBar() {
        functionButton.symbolName = "bolt.fill"
        functionButton.accessibilityLabel = "Funções"
        functionButton.showsMenuAsPrimaryAction = true
        functionButton.preferredMenuElementOrder = .fixed
        functionButton.menu = makeFunctionMenu()
        // Apple Intelligence loads while the finger is still on ⚡ or the formal shortcut.
        for button in [functionButton, functionFormalButton] {
            button.addAction(UIAction { _ in FalaTextTools.prewarm() }, for: [.touchDown, .menuActionTriggered])
        }

        functionTranslateButton.symbolName = "translate"
        functionTranslateButton.accessibilityLabel = "Traduzir"
        functionTranslateButton.addAction(UIAction { [weak self] _ in
            self?.runFunction(.translate(FalaTranslateTargets.recentTarget))
        }, for: .touchUpInside)

        functionFormalButton.symbolName = "signature"
        functionFormalButton.accessibilityLabel = "Formalizar"
        functionFormalButton.addAction(UIAction { [weak self] _ in
            self?.runFunction(.formal)
        }, for: .touchUpInside)

        for button in [functionFormalButton, functionTranslateButton, functionButton] {
            button.isHidden = true
            insertSubview(button, aboveSubview: hexKey)
        }
    }

    /// The ⚡ menu. Rebuilt after every translation, so the language last used leads.
    func makeFunctionMenu() -> UIMenu {
        let rewrite = UIAction(title: "Reescrever", image: UIImage(systemName: "wand.and.stars")) { [weak self] _ in
            self?.runFunction(.rewrite)
        }
        let formal = UIAction(title: "Formalizar", image: UIImage(systemName: "signature")) { [weak self] _ in
            self?.runFunction(.formal)
        }
        let recent = FalaTranslateTargets.recentTarget
        let codes = [recent] + FalaTranslateTargets.all.map(\.code).filter { $0 != recent }
        let languages = codes.map { code in
            UIAction(title: FalaTranslateTargets.name(of: code)) { [weak self] _ in
                self?.runFunction(.translate(code))
            }
        }
        let translate = UIMenu(title: "Traduzir", image: UIImage(systemName: "translate"), children: languages)
        let settings = UIAction(title: "Ajustes", image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.model.onOpenURL?(KeyboardParakeetNotice.opensHex)
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [rewrite, formal, translate]),
            UIMenu(options: .displayInline, children: [settings]),
        ])
    }

    /// Places the discs (from `layoutSubviews`): ⚡ in its cell; after a dictation, traduzir
    /// in ⚡'s spot and formalizar beside it, toward the bar's middle.
    func layoutFunctionBar(_ layout: KeyboardLayout, lift: CGFloat) {
        if let disc = layout.functionDiscFrame?.offsetBy(dx: 0, dy: lift) {
            let step = disc.width + 8
            functionButton.frame = disc
            functionTranslateButton.frame = disc
            functionFormalButton.frame = disc.offsetBy(dx: layout.hexOnLeading ? -step : step, dy: 0)
        }
        if FalaDebug.showsGeometry {
            let geometry = falaGeometryText()
            if geometry != Self.falaLastGeometry {
                Self.falaLastGeometry = geometry
                DispatchQueue.main.async { [weak self] in self?.refreshStrip() }
            }
        }
        updateFunctionBarVisibility()
    }

    /// Shown only where the strip is (not while recording, in the emoji panel or a two-thumb
    /// selection) and only in Apple's bar with the Hex key in it.
    func updateFunctionBarVisibility() {
        // The discs follow light and dark (and a theme) with the keys.
        for button in [functionButton, functionTranslateButton, functionFormalButton] {
            button.palette = palette
        }
        let available = engine.layout.functionDiscFrame != nil && !showsRecording && !stripView.isHidden
        let afterDictation = lastDictation != nil && functionUndo == nil && !functionIsBusy
        functionButton.isHidden = !available || afterDictation
        functionTranslateButton.isHidden = !available || !afterDictation
        functionFormalButton.isHidden = !available || !afterDictation
        functionButton.isEnabled = !functionIsBusy
    }

    // MARK: Running an action

    /// Runs an action on the selection, or on the whole text the field shows when nothing is
    /// selected, and replaces it with the result.
    func runFunction(_ action: FalaTextAction) {
        guard !functionIsBusy else { return }
        engine.commitHangulComposition()
        let target = engine.target
        let selected = target.selectedText ?? ""
        let usesSelection = !selected.isEmpty
        let before = target.documentContextBeforeInput ?? ""
        let after = target.documentContextAfterInput ?? ""
        let original = usesSelection ? selected : before + after
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFunctionMessage("Escreva ou dite algo primeiro")
            return
        }
        if case .translate(let code) = action {
            FalaTranslateTargets.recentTarget = code
            functionButton.menu = makeFunctionMenu()
        }
        keyFeedback()
        hideUndo()
        clearFunctionUndo()
        functionIsBusy = true
        setFunctionStatus(action.busyLabel, for: nil)
        Task { @MainActor [weak self] in
            let outcome = await FalaTextTools.perform(action, on: original)
            guard let self else { return }
            self.functionIsBusy = false
            switch outcome {
            case .done(let text):
                self.setFunctionStatus(nil, for: nil)
                self.replaceFunctionText(original: original, with: text, usesSelection: usesSelection, afterCount: after.count)
            case .failed(let message):
                self.showFunctionMessage(message)
            }
        }
    }

    /// Puts the result in place of what the action read, if the field still holds it.
    private func replaceFunctionText(original: String, with text: String, usesSelection: Bool, afterCount: Int) {
        let target = engine.target
        if usesSelection {
            guard target.selectedText == original else {
                showFunctionMessage("O texto mudou, tente de novo")
                return
            }
            target.insertText(text)
        } else {
            let now = (target.documentContextBeforeInput ?? "") + (target.documentContextAfterInput ?? "")
            guard now == original else {
                showFunctionMessage("O texto mudou, tente de novo")
                return
            }
            // To the end of what the field showed, then back over all of it. Moves stay inside
            // the text the host showed, as Undo dictation's do, so it doesn't drop them.
            if afterCount > 0 { target.adjustTextPosition(byCharacterOffset: afterCount) }
            for _ in 0..<original.count { target.deleteBackward() }
            target.insertText(text)
        }
        functionUndo = FalaFunctionUndo(inserted: text, original: original)
        didEditFunctionText()
        functionUndoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clearFunctionUndo() }
        functionUndoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
        refreshStrip()
    }

    /// The strip's Desfazer after an action: the new text out, the old text back.
    func undoFunction() {
        guard let undo = functionUndo else { return }
        let target = engine.target
        let before = target.documentContextBeforeInput ?? ""
        clearFunctionUndo()
        guard before.hasSuffix(undo.inserted) || (!before.isEmpty && undo.inserted.hasSuffix(before)) else {
            showFunctionMessage("Não deu para desfazer aqui")
            return
        }
        keyFeedback()
        for _ in 0..<undo.inserted.count { target.deleteBackward() }
        target.insertText(undo.original)
        didEditFunctionText()
        refreshStrip()
    }

    func clearFunctionUndo() {
        functionUndoWork?.cancel()
        functionUndoWork = nil
        if functionUndo != nil {
            functionUndo = nil
            refreshStrip()
        }
    }

    /// The keys' own bookkeeping after the text changed under them, as after a dictation.
    private func didEditFunctionText() {
        engine.forgetTextAroundKeys()
        engine.textDidChange()
        onTextEdit?()
    }

    /// A short message in the strip for a few seconds.
    func showFunctionMessage(_ message: String) {
        setFunctionStatus(message, for: 4)
    }

    /// The strip's status while an action runs, or a message; `seconds` clears it after.
    private func setFunctionStatus(_ text: String?, for seconds: TimeInterval?) {
        functionStatusWork?.cancel()
        functionStatusWork = nil
        functionStatus = text
        if let seconds, text != nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.functionStatus = nil
                self.refreshStrip()
            }
            functionStatusWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        refreshStrip()
    }
}
