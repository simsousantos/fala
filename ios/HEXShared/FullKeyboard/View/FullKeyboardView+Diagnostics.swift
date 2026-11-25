import UIKit

/// MyKeyboard, temporary (`FalaDebug.showsGeometry`): what the keyboard can measure of its
/// place on screen, in small type over the top of the keyboard, to look for a sign of the
/// ~16 pt band iOS sometimes draws above it. Each line is one moment after the keyboard came
/// on screen (0.05, 0.3, 0.8 and 2 s), so a height iOS changes after the fact shows too:
///
///     0.05s v253 top599 win0/253 ws0,34 sa0,34 scr852 | 253 253 269 269 852
///     ^time ^view ^top on screen ^window y/height ^window/view safe areas ^screen | heights up the chain
///
/// and a last line with the class names up the chain, shortened.
extension FullKeyboardView {
    func falaDiagnosticsLine(_ elapsed: Double) -> String {
        guard let window else { return String(format: "%.2fs sem janela", elapsed) }
        let screenSpace = window.windowScene?.screen.coordinateSpace
        let top = screenSpace.map { convert(CGPoint.zero, to: $0).y } ?? convert(CGPoint.zero, to: nil).y
        let screen = window.windowScene?.screen.bounds.height ?? 0
        var heights: [String] = []
        var view: UIView? = superview
        while let current = view, heights.count < 8 {
            heights.append(String(Int(current.bounds.height.rounded())))
            view = current.superview
        }
        let w = window.safeAreaInsets, s = safeAreaInsets
        return String(format: "%.2fs v%d top%d win%d/%d ws%d,%d sa%d,%d scr%d | %@",
                      elapsed, Int(bounds.height.rounded()), Int(top.rounded()),
                      Int(window.frame.minY.rounded()), Int(window.frame.height.rounded()),
                      Int(w.top), Int(w.bottom), Int(s.top), Int(s.bottom), Int(screen),
                      heights.joined(separator: " "))
    }

    func falaDiagnosticsChain() -> String {
        var names: [String] = []
        var view: UIView? = superview
        while let current = view, names.count < 8 {
            let name = String(describing: type(of: current))
                .replacingOccurrences(of: "UI", with: "")
                .replacingOccurrences(of: "View", with: "V")
                .replacingOccurrences(of: "Keyboard", with: "Kb")
                .replacingOccurrences(of: "Input", with: "In")
            names.append(String(name.prefix(14)))
            view = current.superview
        }
        return names.joined(separator: ">")
    }

    /// From `layoutSubviews`: on the first layout in a new window, starts the timeline.
    func refreshFalaDiagnostics() {
        guard FalaDebug.showsGeometry else { return }
        let label = falaDebugLabel ?? {
            let label = UILabel()
            label.numberOfLines = 0
            label.font = .monospacedSystemFont(ofSize: 7.5, weight: .medium)
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
            label.isUserInteractionEnabled = false
            addSubview(label)
            falaDebugLabel = label
            return label
        }()
        bringSubviewToFront(label)
        showFalaDiagnostics()
    }

    /// From the controller's `viewWillAppear` (`will`) and `viewDidAppear` (`did`): each
    /// presentation starts a new timeline, measured then and at 0.05, 0.3, 0.8 and 2 s.
    func markFalaDiagnostics(_ event: String) {
        guard FalaDebug.showsGeometry else { return }
        if event == "will" {
            falaDebugWindow += 1
            falaDebugStart = CACurrentMediaTime()
            falaDebugLines = []
            let run = falaDebugWindow
            for delay in [0.05, 0.3, 0.8, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.falaDebugWindow == run else { return }
                    self.falaDebugLines.append(self.falaDiagnosticsLine(CACurrentMediaTime() - self.falaDebugStart))
                    self.refreshFalaDiagnostics()
                }
            }
        }
        falaDebugLines.append(event + " " + falaDiagnosticsLine(CACurrentMediaTime() - falaDebugStart))
        refreshFalaDiagnostics()
    }

    private func showFalaDiagnostics() {
        guard let label = falaDebugLabel else { return }
        label.text = (falaDebugLines + [falaDiagnosticsChain()]).joined(separator: "\n")
        let size = label.sizeThatFits(CGSize(width: bounds.width - 8, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: 4, y: 2, width: bounds.width - 8, height: size.height)
    }
}
