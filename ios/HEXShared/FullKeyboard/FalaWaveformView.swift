import UIKit

/// Fala: the Function keyboard's recording wave. A row of columns 5 pt apart across the bar:
/// a small dot where it was quiet, a rounded bar as tall as the voice was loud where it
/// wasn't. The newest column comes in at the trailing end and the row slides toward the
/// leading end, so a dictation reads as a dotted line that turns into bars while you speak.
/// It replaces Hex's Dot Scope in the recording bar (`HexKeyRecordingPanel`).
@MainActor
final class FalaWaveformView: UIView {
    /// The microphone's level in dBFS (about -62 when silent), as Hex's Dot Scope reads it.
    var loudnessProvider: (() -> Float)?
    /// The bars' ink; the quiet dots take it fainter.
    var color: UIColor = .white { didSet { setNeedsDisplay() } }
    /// Sampling while true; while false the row stays as it was (transcribing) or empties.
    private(set) var isLive = false

    /// Columns per second, and their spacing and size.
    static let rate: Double = 20
    static let step: CGFloat = 5
    static let barWidth: CGFloat = 3
    static let dotSize: CGFloat = 2.6
    /// Under this share of the bar's height a column is a dot.
    static let quiet: CGFloat = 0.08

    private var samples: [CGFloat] = []
    private var smoothed: CGFloat = 0
    private var link: CADisplayLink?
    private var lastSample: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Starts sampling from an empty, dotted row.
    func start() {
        guard !isLive else { return }
        isLive = true
        samples.removeAll()
        smoothed = 0
        lastSample = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        setNeedsDisplay()
    }

    /// Stops sampling and keeps the row as it is.
    func freeze() {
        isLive = false
        link?.invalidate()
        link = nil
    }

    /// Stops sampling and goes back to the plain dotted row.
    func reset() {
        freeze()
        samples.removeAll()
        smoothed = 0
        setNeedsDisplay()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { freeze() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        guard now - lastSample >= 1 / Self.rate else { return }
        lastSample = now
        let db = CGFloat(loudnessProvider?() ?? -62)
        // -50 dB and quieter is silence; -10 dB fills the bar. A quick rise, a slower fall.
        let level = min(1, max(0, (db + 50) / 40))
        smoothed = level > smoothed ? level : smoothed * 0.6 + level * 0.4
        samples.append(smoothed)
        let keep = Int(bounds.width / Self.step) + 2
        if samples.count > keep { samples.removeFirst(samples.count - keep) }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let columns = Int(bounds.width / Self.step)
        let midY = bounds.midY
        let maxHeight = bounds.height * 0.9
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let dotColor = color.withAlphaComponent(0.5)
        for column in 0..<columns {
            let index = samples.count - 1 - column
            let value = index >= 0 ? samples[index] : 0
            let offset = (CGFloat(column) + 0.5) * Self.step
            let x = rtl ? offset : bounds.width - offset
            if value < Self.quiet {
                dotColor.setFill()
                let d = Self.dotSize
                UIBezierPath(ovalIn: CGRect(x: x - d / 2, y: midY - d / 2, width: d, height: d)).fill()
            } else {
                color.setFill()
                let h = max(Self.barWidth * 2, value * maxHeight)
                let bar = CGRect(x: x - Self.barWidth / 2, y: midY - h / 2, width: Self.barWidth, height: h)
                UIBezierPath(roundedRect: bar, cornerRadius: Self.barWidth / 2).fill()
            }
        }
    }
}
