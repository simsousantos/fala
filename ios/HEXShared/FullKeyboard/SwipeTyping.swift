import QuartzCore
import UIKit

/// Settings › Keyboard › Swipe typing: slide from a letter through the letters of a word and lift,
/// and the word goes in, as with Apple's QuickPath and Gboard's glide typing. English and
/// Spanish, and with Settings › Experiments › Swipe typing in more languages on every layout
/// with a typing model (French (France), Polish, and German while its model is chosen); every
/// other layout keeps a drag as a slide to another key.
///
/// A touch on a letter key becomes a swipe once it travels more than a key's pitch from
/// where it went down: the key no longer types, a light trail follows the finger, and the
/// strip shows what the path reads as so far. Lifting the finger types the best reading
/// (`FullKeyboardEngine.typeSwipedWord`, which spaces and capitalises it) and offers the
/// next three in the strip. Taps, holds for accents, and slides of a key or less keep
/// working as before, and so do delete, the space bar's trackpad, 123 and the Hex key, which
/// no swipe starts on.
@MainActor
final class SwipeTyping {
    private(set) var decoder: SwipeDecoder
    /// Fala: the bilingual keyboard's other language (English beside Portuguese): a swipe is
    /// read with both models and their readings merged by cost, the partner's
    /// `partnerCost` nats dearer so a word both languages have reads as the keyboard's own.
    private(set) var partner: SwipeDecoder?
    nonisolated static let partnerCost = 1.0
    private unowned let engine: FullKeyboardEngine
    /// The light trail behind the finger; the key plane holds it above its keys.
    let trail = SwipeTrailView()

    /// A touch's points so far and when each came (`UITouch.timestamp`): the decoder reads
    /// where the finger paused from the times.
    struct Stroke {
        var points: [CGPoint] = []
        var times: [TimeInterval] = []

        mutating func add(_ point: CGPoint, at time: TimeInterval) {
            points.append(point)
            times.append(time)
        }
    }

    /// Letter touches that may still become swipes: their strokes so far.
    private var pending: [Int: Stroke] = [:]
    /// The swipe under way.
    private var active: (id: Int, stroke: Stroke)?
    /// Bumped by every swipe's start and end, so a reading of an older one is dropped.
    private var generation = 0
    private var previewInFlight = false
    private var lastPreviewAt: TimeInterval = 0
    /// Decodes while the finger moves, for the strip, off the main thread.
    private static let previewQueue = DispatchQueue(label: "com.simsousantos.fala.swipe-preview", qos: .userInitiated)
    static let previewInterval: TimeInterval = 0.07
    /// Your own words (`AutocorrectEngine.ownWords`) as the decoder has them.
    private var ownWordsRevision: Int?

    /// How long the last swipe's decode took, for Record typing logs and probes.
    private(set) var lastDecodeTime: TimeInterval?
    /// Nats more a rare reading the dictionary knows only with a capital costs, unless it is
    /// one of your own words: the model's lowercase list holds names and abbreviations ("gs",
    /// "ut", "kent") that a loose swipe of a common word could read as, and they would go in
    /// capitalised mid-sentence. Common ones ("john", "york", "english") cost nothing more.
    var nameCost = 4.0
    /// The model's cost (-ln p) past which such a word counts as rare: about its 2,500th word.
    static let commonNameCost = 10.0

    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    init(engine: FullKeyboardEngine, model: TypingDecoderModel) {
        self.engine = engine
        decoder = SwipeDecoder(model: model)
        syncWords()
    }

    var model: TypingDecoderModel { decoder.model }

    func setPartner(_ model: TypingDecoderModel?) {
        guard partner?.model !== model else { return }
        partner = model.map { SwipeDecoder(model: $0) }
        ownWordsRevision = nil
    }

    /// A reading and whether the partner's model gave it.
    nonisolated struct Reading: Sendable {
        var candidate: SwipeDecoder.Candidate
        var fromPartner: Bool
    }

    /// Both models' readings of a path, best first, each word once. The two decode side by
    /// side on two cores, so reading both takes about as long as reading one (the models are
    /// memory-mapped and read-only, and each decoder works on its own copy).
    nonisolated static func decode(
        _ decoder: SwipeDecoder, partner: SwipeDecoder?, _ points: [CGPoint], times: [TimeInterval],
        keys: TypingDecoder.Keys, previous: String?, limit: Int
    ) -> [Reading] {
        guard let partner else {
            return decoder.decode(points, times: times, keys: keys, previous: previous, limit: limit)
                .map { Reading(candidate: $0, fromPartner: false) }
        }
        var both: [[SwipeDecoder.Candidate]] = [[], []]
        both.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let results = buffer
            DispatchQueue.concurrentPerform(iterations: 2) { i in
                results[i] = (i == 0 ? decoder : partner).decode(points, times: times, keys: keys, previous: previous, limit: limit)
            }
        }
        var readings = both[0].map { Reading(candidate: $0, fromPartner: false) }
        for var candidate in both[1] {
            candidate.cost += partnerCost
            if let same = readings.firstIndex(where: { $0.candidate.text == candidate.text }) {
                if candidate.cost < readings[same].candidate.cost { readings[same] = Reading(candidate: candidate, fromPartner: true) }
            } else {
                readings.append(Reading(candidate: candidate, fromPartner: true))
            }
        }
        return Array(readings.enumerated()
            .sorted { $0.element.candidate.cost != $1.element.candidate.cost ? $0.element.candidate.cost < $1.element.candidate.cost : $0.offset < $1.offset }
            .map(\.element).prefix(limit))
    }

    /// How far a letter touch travels before it is a swipe: a key's width and gap.
    var threshold: CGFloat { engine.layout.swipePitch }

    var isSwiping: Bool { active != nil }

    /// Words never offered (slurs, and swear words unless Suggest swear words is on), the
    /// language's contractions, and your own words; rebuilt only when one of them changed.
    func syncWords() {
        let autocorrect = engine.autocorrect
        let revision = autocorrect.ownWordsRevision
        guard revision != ownWordsRevision else { return }
        ownWordsRevision = revision
        func sync(_ decoder: inout SwipeDecoder, ownWords: Bool) {
            let model = decoder.model
            decoder.neverSuggest = TypingDecoder.NeverSuggest(
                autocorrect.offensiveWords.blocked(allowSwearing: autocorrect.allowsSwearing), model: model
            )
            var extra = SwipeDecoder.ExtraWords()
            if model.language == KeyboardLanguage.english.rawValue {
                extra.add(AutocorrectEngine.englishContractions, cost: { SwipeDecoder.costOfContraction($0) }, model: model, contractions: true)
            }
            if ownWords { extra.add(autocorrect.ownWords, cost: SwipeDecoder.ownWordCost, model: model) }
            decoder.extraWords = extra
        }
        sync(&decoder, ownWords: true)
        if var partner {
            sync(&partner, ownWords: false)
            self.partner = partner
        }
    }

    // MARK: - Touches (from `KeyboardKeyPlaneView`)

    /// Before a touch goes down: a swipe still under way ends first, so its word goes in
    /// before the new key's letter.
    func touchWillBegin() {
        if let swipe = active { finish(swipe.id, stroke: swipe.stroke) }
    }

    /// After the engine took a touch: a letter key's may become a swipe. `time` is the
    /// touch's timestamp (now when nil).
    func began(id: Int, at point: CGPoint, time: TimeInterval? = nil) {
        guard engine.allowsSwipes, let touch = engine.touches[id], !touch.committed,
              touch.key.character?.first?.isLetter == true else { return }
        var stroke = Stroke()
        stroke.add(point, at: time ?? clock())
        pending[id] = stroke
    }

    /// True when the touch is a swipe (now or already): the plane leaves it to this.
    func moved(id: Int, to point: CGPoint, time: TimeInterval? = nil) -> Bool {
        if var swipe = active, swipe.id == id {
            swipe.stroke.add(point, at: time ?? clock())
            active = swipe
            trail.add(point)
            schedulePreview()
            return true
        }
        guard var stroke = pending[id] else { return false }
        stroke.add(point, at: time ?? clock())
        pending[id] = stroke
        guard let first = stroke.points.first, hypot(point.x - first.x, point.y - first.y) > threshold,
              let touch = engine.touches[id], !touch.committed, engine.activeAccentMenu == nil,
              engine.allowsSwipes else { return false }
        pending[id] = nil
        syncWords()
        engine.beginSwipe(touchID: id)
        active = (id, stroke)
        generation += 1
        lastPreviewAt = 0
        trail.begin(stroke.points)
        schedulePreview()
        return true
    }

    /// Whether the touch is the swipe under way.
    func owns(_ id: Int) -> Bool { active?.id == id }

    /// A touch that never became a swipe ended.
    func forget(_ id: Int) {
        pending[id] = nil
    }

    /// The swipe's finger lifted: its word goes in.
    func ended(id: Int, at point: CGPoint, time: TimeInterval? = nil) {
        guard var swipe = active, swipe.id == id else { return }
        swipe.stroke.add(point, at: time ?? clock())
        finish(id, stroke: swipe.stroke)
    }

    /// The system cancelled the swipe's touch: nothing goes in.
    func cancelled(id: Int) {
        pending[id] = nil
        guard let swipe = active, swipe.id == id else { return }
        active = nil
        generation += 1
        trail.fade()
        engine.endSwipe(typing: [], points: swipe.stroke.points.count, decodeTime: nil)
    }

    func cancelAll() {
        pending.removeAll()
        guard active != nil else { return }
        active = nil
        generation += 1
        trail.clear()
        engine.endSwipe(typing: [], points: 0, decodeTime: nil)
    }

    private func finish(_ id: Int, stroke: Stroke) {
        active = nil
        pending[id] = nil
        generation += 1
        trail.fade()
        let started = clock()
        let layout = engine.layout
        let candidates = Self.decode(
            decoder, partner: partner, stroke.points.map(layout.joinedForSwipe), times: stroke.times, keys: engine.swipeKeys,
            previous: engine.swipePreviousWord, limit: 8
        )
        let words = engine.autocorrect.readingsOfferingOwnCapitals(ranked(candidates), capsLock: engine.shift.state == .locked, model: model)
        let elapsed = clock() - started
        lastDecodeTime = elapsed
        if let letter = slidTapLetter(stroke), let start = stroke.points.first,
           words.first.map({ !Self.word($0, startsAndEndsWith: letter) }) ?? true {
            // A tap that slid: its letter goes in as a tap's would, after the space a swiped
            // word before it keeps pending and with the capital shift gives it.
            engine.endSwipe(typing: [], points: stroke.points.count, decodeTime: elapsed)
            engine.touchBegan(id: id, at: start)
            engine.touchEnded(id: id, at: start)
            return
        }
        engine.endSwipe(typing: words, points: stroke.points.count, decodeTime: elapsed)
    }

    /// How far (key pitches) a swipe may go from where it went down and still be a tap
    /// that slid, when it lifts on the key it started on.
    static let slidTapReach: CGFloat = 1.6

    /// The letter of a swipe that came back to the key it went down on without going more
    /// than `slidTapReach` pitches from it ("a" dragged a little too far and back): the
    /// decoder reads no word of one letter, so it read "as". Nil for any other swipe.
    private func slidTapLetter(_ stroke: Stroke) -> String? {
        guard let first = stroke.points.first, let last = stroke.points.last else { return nil }
        let reach = threshold * Self.slidTapReach
        guard stroke.points.allSatisfy({ hypot($0.x - first.x, $0.y - first.y) <= reach }) else { return nil }
        let layout = engine.layout
        guard let down = layout.hitTest(first), down == layout.hitTest(last),
              let letter = down.character, letter.count == 1 else { return nil }
        return letter.lowercased()
    }

    /// Whether `word` begins and ends on `letter`'s key ("lol" on l, "pop" on p): a word a
    /// swipe that comes back to its key can mean.
    static func word(_ word: String, startsAndEndsWith letter: String) -> Bool {
        func base(_ character: Character?) -> String? {
            character.map { String($0).lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.first.map(String.init) ?? "" }
        }
        return word.count > 1 && base(word.first) == letter && base(word.last) == letter
    }

    /// The readings best first once a rare name or abbreviation costs `nameCost` more.
    func ranked(_ candidates: [SwipeDecoder.Candidate]) -> [String] {
        ranked(candidates.map { Reading(candidate: $0, fromPartner: false) })
    }

    func ranked(_ readings: [Reading]) -> [String] {
        func rareName(_ text: String, partner: Bool) -> Bool {
            guard engine.swipeReadsAsName(text) else { return false }
            let model = partner ? (self.partner?.model ?? decoder.model) : decoder.model
            return model.index(of: text).map { model.unigramCost($0) > Self.commonNameCost } ?? true
        }
        return readings
            .map { ($0.candidate.text, $0.candidate.cost + (rareName($0.candidate.text, partner: $0.fromPartner) ? nameCost : 0)) }
            .enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
    }

    // MARK: - The word so far

    /// Reads the path so far off the main thread, at most every `previewInterval`, and shows
    /// its best word in the strip while the swipe is still the same one.
    private func schedulePreview() {
        guard let swipe = active, !previewInFlight, swipe.stroke.points.count >= 3 else { return }
        let now = clock()
        guard now - lastPreviewAt >= Self.previewInterval else { return }
        previewInFlight = true
        lastPreviewAt = now
        let decoder = decoder, partner = partner, keys = engine.swipeKeys, previous = engine.swipePreviousWord
        let points = swipe.stroke.points.map(engine.layout.joinedForSwipe), times = swipe.stroke.times, generation = generation
        Self.previewQueue.async { [weak self] in
            let candidates = Self.decode(decoder, partner: partner, points, times: times, keys: keys, previous: previous, limit: 3)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.previewInFlight = false
                    guard self.generation == generation, self.active != nil else { return }
                    self.engine.showSwipePreview(self.ranked(candidates))
                }
            }
        }
    }

    // MARK: - Spacing

    /// Whether a swiped word needs a space before it, as Apple's keyboard adds one: unless
    /// the text before the cursor is empty or ends in a space, a line break, an attachment
    /// (U+FFFC: a shared link's card or a picture in the text) or opening punctuation (a
    /// bracket, an opening quote, ¿ or ¡, or a mark that starts a word such as @ # /). A
    /// straight quote opens when nothing or a space comes before it. Apple's keyboard swipes
    /// "hello" right after an attachment with no space, in Messages after a link's card (which
    /// then moves the word to its own line) and in a text view after a picture mid-line (black
    /// box, iOS 27.2 simulator); Hex's space there began the word's line.
    static func needsSpace(before: String?) -> Bool {
        guard let before, let last = before.last else { return false }
        if last.isWhitespace || last.isNewline || last == "\u{FFFC}" || opening.contains(last) { return false }
        if last == "\"" || last == "'" {
            let previous = before.dropLast().last
            return !(previous == nil || previous!.isWhitespace || previous!.isNewline || opening.contains(previous!))
        }
        return true
    }

    private static let opening: Set<Character> = ["(", "[", "{", "<", "«", "‹", "“", "‘", "„", "¿", "¡", "@", "#", "/"]
}

extension KeyboardLanguage {
    /// Swipe typing's default layouts, English and Spanish. Another language swipes too with a
    /// typing model when Settings › Experiments › Swipe typing in more languages is on
    /// (`FullKeyboardSettings.swipesIn`); elsewhere a drag stays a slide to another key.
    var supportsSwipeTyping: Bool { self == .english || self == .spanish }
}

/// Fala: the trail behind a swiping finger, as Apple's keyboard draws it (QuickPath, iOS 26):
/// a soft grey comet, round and about 16 pt thick at the finger, tapering to a point along the
/// last `tail` seconds of the path, all in one translucent tone (black at 22% on the light
/// keyboard, white at 26% on the dark one) so it darkens the keys and the gaps alike. It fades
/// when the finger lifts. Measured on a screen recording of the iPhone keyboard, 3 px a point.
@MainActor
final class SwipeTrailView: UIView {
    static let tail: TimeInterval = 0.32
    /// The head's thickness; the rest of the trail narrows from it to nothing.
    static let width: CGFloat = 16
    /// How the thickness falls off toward the tail: under 1 keeps it full longer near the head.
    static let taper: CGFloat = 0.75

    var palette = FullKeyboardPalette(isDark: false) {
        didSet { if palette != oldValue { setNeedsDisplay() } }
    }
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    private var points: [(point: CGPoint, at: TimeInterval)] = []
    private var link: CADisplayLink?
    private var showing = false
    /// Where the trail was last drawn: a redraw repaints only that and where it is now, not
    /// the whole key plane.
    private var drawn: CGRect = .null

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func color(_ palette: FullKeyboardPalette) -> UIColor {
        palette.isDark ? UIColor(white: 1, alpha: 0.26) : UIColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 0.22)
    }

    /// Off screen, the display link (which holds this view) stops.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { clear() }
    }

    var isShowing: Bool { showing }

    func begin(_ start: [CGPoint]) {
        layer.removeAnimation(forKey: "fade")
        layer.opacity = 1
        let now = clock()
        points = start.map { ($0, now) }
        showing = true
        if link == nil, window != nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        prune()
        invalidate()
    }

    func add(_ point: CGPoint) {
        points.append((point, clock()))
        prune()
        invalidate()
    }

    /// The finger lifted: the trail fades out where it is.
    func fade() {
        stopTicking()
        guard showing else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.link == nil else { return }
                self.clear()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    func clear() {
        stopTicking()
        points.removeAll()
        showing = false
        layer.removeAnimation(forKey: "fade")
        layer.opacity = 1
        invalidate()
    }

    private func stopTicking() {
        link?.invalidate()
        link = nil
    }

    /// While the finger rests the tail keeps shrinking toward it.
    @objc private func tick() {
        prune()
        invalidate()
    }

    /// Marks the old and the new trail's bounds for redrawing.
    private func invalidate() {
        var now = CGRect.null
        for p in points { now = now.union(CGRect(origin: p.point, size: .zero)) }
        if !now.isNull { now = now.insetBy(dx: -Self.width, dy: -Self.width) }
        let dirty = drawn.union(now)
        drawn = now
        if !dirty.isNull { setNeedsDisplay(dirty) }
    }

    /// Points older than the tail drop off behind the finger, down to its last stretch.
    private func prune() {
        if let old = points.lastIndex(where: { $0.at < clock() - Self.tail }) {
            let drop = min(old, points.count - 2)
            if drop > 0 { points.removeFirst(drop) }
        }
    }

    override func draw(_ rect: CGRect) {
        guard showing, let head = points.last, let context = UIGraphicsGetCurrentContext() else { return }
        let now = clock()
        // Each point's thickness: by its age, so the tail shrinks smoothly toward a still
        // finger, and full at the finger.
        func thickness(_ at: TimeInterval) -> CGFloat {
            let left = CGFloat(max(0, 1 - (now - at) / Self.tail))
            return Self.width * pow(left, Self.taper)
        }
        // One translucent tone for the whole trail: the overlapping pieces are drawn opaque in
        // a transparency layer, and the layer takes the tone's alpha, so no joint darkens.
        let color = Self.color(palette)
        var alpha: CGFloat = 0
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let solid = color.withAlphaComponent(1).cgColor
        context.setFillColor(solid)
        context.setStrokeColor(solid)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // The head: a full round end at the finger.
        let r = Self.width / 2
        context.fillEllipse(in: CGRect(x: head.point.x - r, y: head.point.y - r, width: 2 * r, height: 2 * r))
        // The body: each step as a quadrilateral between its two ends' thicknesses, with round
        // joints so turns stay smooth.
        for i in points.indices.dropFirst() {
            let a = points[i - 1], b = points[i]
            let wa = thickness(a.at), wb = i == points.count - 1 ? Self.width : thickness(b.at)
            guard max(wa, wb) > 0.3 else { continue }
            let dx = b.point.x - a.point.x, dy = b.point.y - a.point.y
            let length = hypot(dx, dy)
            guard length > 0.01 else { continue }
            let nx = -dy / length, ny = dx / length
            context.move(to: CGPoint(x: a.point.x + nx * wa / 2, y: a.point.y + ny * wa / 2))
            context.addLine(to: CGPoint(x: b.point.x + nx * wb / 2, y: b.point.y + ny * wb / 2))
            context.addLine(to: CGPoint(x: b.point.x - nx * wb / 2, y: b.point.y - ny * wb / 2))
            context.addLine(to: CGPoint(x: a.point.x - nx * wa / 2, y: a.point.y - ny * wa / 2))
            context.closePath()
            context.fillPath()
            if wb > 0.5 {
                context.fillEllipse(in: CGRect(x: b.point.x - wb / 2, y: b.point.y - wb / 2, width: wb, height: wb))
            }
        }
        context.endTransparencyLayer()
    }
}
