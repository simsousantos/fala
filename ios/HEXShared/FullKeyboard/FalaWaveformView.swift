import UIKit

/// Fala: the Function keyboard's recording wave, matched to its screen recordings.
///
/// - Idle and at the start: a row of small grey dots across the bar.
/// - Recording: about ten columns a second come in at the trailing end (beside ✓), each a
///   rounded grey bar as tall as the voice was loud that moment (a dot when quiet). A new bar
///   grows into its height, and the whole row slides smoothly toward the leading end, fading
///   out over its last few columns there.
/// - Finishing: the bars shrink back to dots, then a small packet of short bars sweeps back
///   and forth along the dotted row while the words are transcribed.
///
/// It replaces Hex's Dot Scope in the recording bar (`HexKeyRecordingPanel`).
@MainActor
final class FalaWaveformView: UIView {
    /// The microphone's level in dBFS (about -62 when silent), as Hex's Dot Scope reads it.
    var loudnessProvider: (() -> Float)?
    /// The keys' ink; bars and dots take it at `barAlpha` and `dotAlpha`.
    var color: UIColor = .black { didSet { setNeedsDisplay() } }

    enum Mode { case idle, recording, processing }
    private(set) var mode: Mode = .idle

    // Measured on Function's bar (iPhone, 3 px per point): a column every 5.5 pt, bars 2.7 pt
    // wide, dots 2 pt, bars up to 90% of the 36 pt discs.
    static let rate: Double = 10
    static let step: CGFloat = 5.5
    static let barWidth: CGFloat = 2.7
    static let dotSize: CGFloat = 2
    static let barAlpha: CGFloat = 0.55
    static let dotAlpha: CGFloat = 0.3
    /// How long a new bar takes to grow to its height, and the bars to shrink when it ends.
    static let grow: CFTimeInterval = 0.16
    static let collapse: CFTimeInterval = 0.28
    /// The leading end's fade, in points.
    static let fadeWidth: CGFloat = 26
    /// Under this share of the height a column is a dot.
    static let quiet: CGFloat = 0.06

    private struct Column {
        let level: CGFloat
        let born: CFTimeInterval
    }

    private var columns: [Column] = []
    private var smoothed: CGFloat = 0
    private var link: CADisplayLink?
    private var lastSample: CFTimeInterval = 0
    /// When the bars started shrinking (the end of a recording).
    private var collapseStart: CFTimeInterval?
    private var processingStart: CFTimeInterval = 0
    private var now: CFTimeInterval = CACurrentMediaTime()

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

    /// Recording: a fresh dotted row, bars coming in as the voice does.
    func start() {
        columns.removeAll()
        smoothed = 0
        lastSample = 0
        collapseStart = nil
        mode = .recording
        startLink()
        setNeedsDisplay()
    }

    /// The recording ended: the bars shrink to dots and the packet sweeps until `reset()`.
    func freeze() {
        guard mode != .processing else { return }
        let time = CACurrentMediaTime()
        collapseStart = time
        processingStart = time + Self.collapse
        mode = .processing
        startLink()
    }

    /// Back to the plain dotted row, still.
    func reset() {
        mode = .idle
        stopLink()
        columns.removeAll()
        smoothed = 0
        collapseStart = nil
        setNeedsDisplay()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stopLink() } else if mode != .idle { startLink() }
    }

    private func startLink() {
        guard link == nil, window != nil || mode != .idle else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        now = link.timestamp
        if mode == .recording, now - lastSample >= 1 / Self.rate {
            lastSample = now
            let db = CGFloat(loudnessProvider?() ?? -62)
            // -52 dB and quieter is silence, -12 dB fills the bar; a quick rise, a slower fall.
            let level = min(1, max(0, (db + 52) / 40))
            smoothed = level > smoothed ? level : smoothed * 0.55 + level * 0.45
            columns.append(Column(level: smoothed, born: now))
            let keep = Int(bounds.width / Self.step) + 3
            if columns.count > keep { columns.removeFirst(columns.count - keep) }
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let maxHeight = bounds.height * 0.9
        let midY = bounds.midY
        let slots = Int(bounds.width / Self.step)

        // Each column's height, by its place from the trailing end (0 = newest).
        var heights = [CGFloat](repeating: 0, count: slots + 2)
        // How far the row has slid since the newest column came in, as a share of a step.
        var slide: CGFloat = 0
        let shrink: CGFloat
        if let collapseStart {
            let t = min(1, max(0, (now - collapseStart) / Self.collapse))
            shrink = 1 - CGFloat(t * t * (3 - 2 * t))
        } else {
            shrink = 1
        }
        if mode == .recording || (mode == .processing && shrink > 0) {
            if mode == .recording, let newest = columns.last {
                slide = CGFloat(min(1, (now - newest.born) * Self.rate))
            }
            for (place, column) in columns.reversed().enumerated() where place < heights.count {
                let age = mode == .recording ? now - column.born : Self.grow
                let g = CGFloat(min(1, age / Self.grow))
                let eased = 1 - (1 - g) * (1 - g)
                heights[place] = column.level * eased * shrink
            }
        }
        if mode == .processing, shrink == 0 {
            // A packet of short bars sweeping along the dots, one way then back, 1.4 s a pass.
            let pass = 1.4
            let phase = ((now - processingStart) / pass).truncatingRemainder(dividingBy: 2)
            let along = CGFloat(phase < 1 ? phase : 2 - phase)
            let eased = along * along * (3 - 2 * along)
            let center = CGFloat(slots - 1) * eased
            for place in 0..<heights.count {
                let distance = (CGFloat(place) - center) / 2.2
                heights[place] = 0.34 * exp(-distance * distance)
            }
        }

        for place in 0..<heights.count {
            let offset = (CGFloat(place) + 0.5 + slide) * Self.step
            guard offset < bounds.width + Self.step else { break }
            let x = rtl ? offset : bounds.width - offset
            // Fade out toward the leading end.
            let fromLead = rtl ? bounds.width - x : x
            let fade = min(1, max(0, fromLead / Self.fadeWidth))
            guard fade > 0 else { continue }
            let level = heights[place]
            if level < Self.quiet {
                color.withAlphaComponent(Self.dotAlpha * fade).setFill()
                let d = Self.dotSize
                UIBezierPath(ovalIn: CGRect(x: x - d / 2, y: midY - d / 2, width: d, height: d)).fill()
            } else {
                color.withAlphaComponent(Self.barAlpha * fade).setFill()
                let h = max(Self.barWidth * 1.6, level * maxHeight)
                let bar = CGRect(x: x - Self.barWidth / 2, y: midY - h / 2, width: Self.barWidth, height: h)
                UIBezierPath(roundedRect: bar, cornerRadius: Self.barWidth / 2).fill()
            }
        }
    }
}
