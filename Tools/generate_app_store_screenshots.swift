import AppKit
import Foundation

struct LocaleCopy {
    let code: String
    let hero: String
    let subhero: String
    let screenshots: [ScreenshotCopy]
    let tabs: (home: String, today: String, settings: String)
    let deckTitle: String
    let deckSubtitle: String
    let newDeck: String
    let settings: String
    let aiTitle: String
    let aiSubtitle: String
    let cardQuestion: String
    let cardAnswer: String
}

struct ScreenshotCopy {
    let title: String
    let subtitle: String
    let scene: Scene
}

enum Scene {
    case overview
    case decks
    case study
    case ai
    case audio
}

struct Canvas {
    let size: CGSize
    let isPad: Bool
}

let outputRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("AppStoreScreenshots")

let iphone = Canvas(size: CGSize(width: 1284, height: 2778), isPad: false)
let ipad = Canvas(size: CGSize(width: 2048, height: 2732), isPad: true)

let locales = [
    LocaleCopy(
        code: "de",
        hero: "Teresa Flashcards",
        subhero: "Lerne mit Teresa",
        screenshots: [
            ScreenshotCopy(title: "Lerne mit Teresa", subtitle: "Deine Karten. Dein Tempo. Jeden Tag ein bisschen weiter.", scene: .overview),
            ScreenshotCopy(title: "Stapel für jedes Thema", subtitle: "Schule, Uni, Sprachen oder Beruf: Alles bleibt sauber sortiert.", scene: .decks),
            ScreenshotCopy(title: "Karten lernen statt Listen pauken", subtitle: "Tippen, umdrehen, bewerten. Teresa merkt sich den nächsten Termin.", scene: .study),
            ScreenshotCopy(title: "KI hilft, wenn du willst", subtitle: "Optionale KI-Karten, Beispiele, Merksätze und Mini-Quiz per Abo.", scene: .ai),
            ScreenshotCopy(title: "Sprache & Audio", subtitle: "Lass Fragen und Antworten schnell vorlesen, passend zur Stapel-Sprache.", scene: .audio)
        ],
        tabs: ("Home", "Heute", "Einstellungen"),
        deckTitle: "Deine Stapel",
        deckSubtitle: "Heute warten 12 Karten",
        newDeck: "Neuer Stapel",
        settings: "Einstellungen",
        aiTitle: "KI-Funktionen",
        aiSubtitle: "Karten erzeugen und Antworten leichter verstehen",
        cardQuestion: "Was bedeutet photosynthesis?",
        cardAnswer: "Photosynthesis means Pflanzen wandeln Licht in Energie um."
    ),
    LocaleCopy(
        code: "en",
        hero: "Teresa Flashcards",
        subhero: "Learn with Teresa",
        screenshots: [
            ScreenshotCopy(title: "Learn with Teresa", subtitle: "Your cards. Your pace. A little progress every day.", scene: .overview),
            ScreenshotCopy(title: "Decks for every topic", subtitle: "School, university, languages, or work: keep everything tidy.", scene: .decks),
            ScreenshotCopy(title: "Study cards, not long lists", subtitle: "Tap, flip, rate. Teresa remembers when to review next.", scene: .study),
            ScreenshotCopy(title: "AI when you want it", subtitle: "Optional AI cards, examples, memory aids, and mini quizzes.", scene: .ai),
            ScreenshotCopy(title: "Language & audio", subtitle: "Read questions and answers aloud, matched to each deck language.", scene: .audio)
        ],
        tabs: ("Home", "Today", "Settings"),
        deckTitle: "Your Decks",
        deckSubtitle: "12 cards due today",
        newDeck: "New Deck",
        settings: "Settings",
        aiTitle: "AI Features",
        aiSubtitle: "Create cards and make answers easier",
        cardQuestion: "Was bedeutet photosynthesis?",
        cardAnswer: "Photosynthesis means Pflanzen wandeln Licht in Energie um."
    )
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

let blue = color(42, 148, 255)
let purple = color(145, 88, 235)
let orange = color(255, 143, 46)
let mint = color(38, 190, 145)
let ink = color(19, 23, 35)
let muted = color(111, 119, 135)
let soft = color(245, 248, 255)

func paragraph(_ alignment: NSTextAlignment = .left, lineHeight: CGFloat? = nil) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    if let lineHeight {
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
    }
    return style
}

func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink, alignment: NSTextAlignment = .left, lineHeight: CGFloat? = nil) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font(size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph(alignment, lineHeight: lineHeight)
    ]
    NSString(string: text).draw(in: rect, withAttributes: attributes)
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func circle(_ rect: CGRect, fill: NSColor) {
    let path = NSBezierPath(ovalIn: rect)
    fill.setFill()
    path.fill()
}

func gradient(_ rect: CGRect, start: NSColor, end: NSColor, angle: CGFloat = 90) {
    NSGradient(starting: start, ending: end)?.draw(in: rect, angle: angle)
}

func drawAppIcon(in rect: CGRect) {
    roundedRect(rect, radius: rect.width * 0.22, fill: blue)
    gradient(rect.insetBy(dx: 3, dy: 3), start: color(72, 198, 255), end: color(42, 126, 245), angle: -35)
    let card = CGRect(x: rect.midX - rect.width * 0.21, y: rect.midY - rect.height * 0.18, width: rect.width * 0.46, height: rect.height * 0.48)
    roundedRect(card, radius: rect.width * 0.08, fill: .white)
    let card2 = card.offsetBy(dx: rect.width * 0.11, dy: -rect.height * 0.08)
    roundedRect(card2, radius: rect.width * 0.08, fill: color(255, 108, 82))
    roundedRect(card, radius: rect.width * 0.08, fill: .white)
    drawSymbol("✦", in: CGRect(x: card.midX - rect.width * 0.12, y: card.midY - rect.width * 0.13, width: rect.width * 0.24, height: rect.width * 0.24), size: rect.width * 0.24, color: color(255, 181, 55))
}

func drawSymbol(_ symbol: String, in rect: CGRect, size: CGFloat, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .bold),
        .foregroundColor: color,
        .paragraphStyle: paragraph(.center)
    ]
    NSString(string: symbol).draw(in: rect, withAttributes: attributes)
}

func drawBackground(canvas: Canvas) {
    let rect = CGRect(origin: .zero, size: canvas.size)
    gradient(rect, start: color(36, 142, 255), end: color(174, 63, 220), angle: -35)

    for index in 0..<9 {
        let y = CGFloat(index) * canvas.size.height / 8 - canvas.size.height * 0.12
        let stripe = NSBezierPath()
        stripe.move(to: CGPoint(x: -canvas.size.width * 0.15, y: y))
        stripe.line(to: CGPoint(x: canvas.size.width * 1.15, y: y + canvas.size.height * 0.22))
        color(255, 255, 255, index % 2 == 0 ? 0.08 : 0.045).setStroke()
        stripe.lineWidth = canvas.isPad ? 42 : 30
        stripe.stroke()
    }

    roundedRect(CGRect(x: canvas.size.width * 0.06, y: canvas.size.height * 0.07, width: canvas.size.width * 0.88, height: canvas.size.height * 0.84), radius: canvas.isPad ? 78 : 58, fill: color(255, 255, 255, 0.10), stroke: color(255, 255, 255, 0.18), lineWidth: 2)
}

func drawHeader(copy: LocaleCopy, screenshot: ScreenshotCopy, canvas: Canvas) {
    let margin: CGFloat = canvas.isPad ? 126 : 78
    let iconSize: CGFloat = canvas.isPad ? 82 : 66
    drawAppIcon(in: CGRect(x: margin, y: canvas.size.height - margin - iconSize, width: iconSize, height: iconSize))
    drawText(copy.hero, in: CGRect(x: margin + iconSize + 22, y: canvas.size.height - margin - iconSize + 4, width: canvas.size.width - margin * 2 - iconSize - 22, height: 44), size: canvas.isPad ? 34 : 29, weight: .bold, color: .white)
    drawText(copy.subhero, in: CGRect(x: margin + iconSize + 22, y: canvas.size.height - margin - iconSize + 45, width: canvas.size.width - margin * 2 - iconSize - 22, height: 34), size: canvas.isPad ? 23 : 20, weight: .medium, color: color(255, 255, 255, 0.78))

    drawText(screenshot.title, in: CGRect(x: margin, y: canvas.size.height - (canvas.isPad ? 360 : 390), width: canvas.size.width - margin * 2, height: canvas.isPad ? 120 : 150), size: canvas.isPad ? 78 : 72, weight: .heavy, color: .white, lineHeight: canvas.isPad ? 86 : 80)
    drawText(screenshot.subtitle, in: CGRect(x: margin, y: canvas.size.height - (canvas.isPad ? 465 : 535), width: canvas.size.width - margin * 2, height: canvas.isPad ? 84 : 120), size: canvas.isPad ? 32 : 32, weight: .medium, color: color(255, 255, 255, 0.82), lineHeight: canvas.isPad ? 40 : 40)
}

func drawDeviceFrame(in rect: CGRect, canvas: Canvas, scene: Scene, copy: LocaleCopy) {
    roundedRect(rect, radius: canvas.isPad ? 54 : 64, fill: color(14, 18, 28), stroke: color(255, 255, 255, 0.45), lineWidth: 2)
    let screen = rect.insetBy(dx: canvas.isPad ? 20 : 16, dy: canvas.isPad ? 20 : 16)
    roundedRect(screen, radius: canvas.isPad ? 38 : 50, fill: .black)
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: canvas.isPad ? 38 : 50, yRadius: canvas.isPad ? 38 : 50).addClip()
    drawMockApp(in: screen, scene: scene, copy: copy, isPad: canvas.isPad)
    NSGraphicsContext.current?.restoreGraphicsState()
}

func drawMockApp(in screen: CGRect, scene: Scene, copy: LocaleCopy, isPad: Bool) {
    switch scene {
    case .overview:
        drawOverviewScene(in: screen, copy: copy, isPad: isPad)
    case .decks, .study, .ai, .audio:
        drawAppChrome(in: screen, copy: copy, isPad: isPad)
        if scene == .decks {
        drawDecksScene(in: screen, copy: copy, isPad: isPad)
        } else if scene == .study {
            drawStudyScene(in: screen, copy: copy, isPad: isPad)
        } else if scene == .ai {
            drawAIScene(in: screen, copy: copy, isPad: isPad)
        } else {
            drawAudioScene(in: screen, copy: copy, isPad: isPad)
        }
    }
}

func drawAppChrome(in screen: CGRect, copy: LocaleCopy, isPad: Bool) {
    roundedRect(screen, radius: 0, fill: .black)
    let margin = screen.width * 0.075
    let top = screen.maxY - screen.height * 0.085
    circle(CGRect(x: screen.minX + margin, y: top - 34, width: 58, height: 58), fill: color(255, 255, 255, 0.10))
    drawSymbol("⚙", in: CGRect(x: screen.minX + margin + 7, y: top - 26, width: 44, height: 44), size: 30, color: .white)
    drawText(copy.hero, in: CGRect(x: screen.minX + margin, y: top - 138, width: screen.width - margin * 2, height: 72), size: isPad ? 47 : 42, weight: .heavy, color: .white)
}

func drawOverviewScene(in screen: CGRect, copy: LocaleCopy, isPad: Bool) {
    gradient(screen, start: color(78, 145, 232), end: color(177, 64, 214), angle: -20)
    let margin = screen.width * 0.075
    drawText(copy.hero, in: CGRect(x: screen.minX + margin, y: screen.maxY - screen.height * 0.26, width: screen.width - margin * 2, height: 130), size: isPad ? 54 : 48, weight: .heavy, color: .white, alignment: .center, lineHeight: isPad ? 62 : 56)
    drawText(copy.subhero, in: CGRect(x: screen.minX + margin, y: screen.maxY - screen.height * 0.33, width: screen.width - margin * 2, height: 48), size: isPad ? 31 : 27, weight: .semibold, color: color(255, 255, 255, 0.78), alignment: .center)
    let card = CGRect(x: screen.midX - screen.width * 0.30, y: screen.midY - screen.height * 0.15, width: screen.width * 0.60, height: screen.height * 0.31)
    let path = NSBezierPath(roundedRect: card, xRadius: 38, yRadius: 38)
    NSGraphicsContext.current?.saveGraphicsState()
    var transform = AffineTransform(translationByX: card.midX, byY: card.midY)
    transform.rotate(byDegrees: -2.0)
    transform.translate(x: -card.midX, y: -card.midY)
    path.transform(using: transform)
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    drawSymbol("✦", in: CGRect(x: card.midX - 46, y: card.maxY - 136, width: 92, height: 92), size: 74, color: purple)
    drawText("Bereit?", in: CGRect(x: card.minX + 38, y: card.midY - 20, width: card.width - 76, height: 64), size: isPad ? 44 : 39, weight: .heavy, color: .black, alignment: .center)
    drawText("Tippen. Umdrehen. Lernen.", in: CGRect(x: card.minX + 38, y: card.midY - 72, width: card.width - 76, height: 42), size: isPad ? 22 : 19, weight: .bold, color: color(77, 77, 82), alignment: .center)
    drawText(copy.code == "de" ? "Deine Karten. Dein Tempo." : "Your cards. Your pace.", in: CGRect(x: screen.minX + margin, y: screen.minY + screen.height * 0.18, width: screen.width - margin * 2, height: 48), size: isPad ? 28 : 24, weight: .semibold, color: color(255, 255, 255, 0.76), alignment: .center)
}

func drawDecksScene(in screen: CGRect, copy: LocaleCopy, isPad: Bool) {
    let margin = screen.width * 0.075
    drawDeckGrid(in: CGRect(x: screen.minX + margin, y: screen.minY + screen.height * 0.14, width: screen.width - margin * 2, height: screen.height * 0.58), copy: copy, isPad: isPad)
}

func drawDeckGrid(in rect: CGRect, copy: LocaleCopy, isPad: Bool) {
    let gap: CGFloat = isPad ? 20 : 16
    let columns = isPad ? 3 : 2
    let rows = isPad ? 2 : 3
    let tileW = (rect.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
    let tileH = (rect.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
    let decks = [("Englisch", "24", blue), ("Mathe", "12", orange), ("Musik", "8", mint), ("SAP BTP", "15", purple), ("Optionen", "10", color(238, 88, 124)), (copy.newDeck, "+", muted)]
    for index in 0..<min(decks.count, columns * rows) {
        let row = index / columns
        let col = index % columns
        let tile = CGRect(x: rect.minX + CGFloat(col) * (tileW + gap), y: rect.maxY - CGFloat(row + 1) * tileH - CGFloat(row) * gap, width: tileW, height: tileH)
        let deck = decks[index]
        roundedRect(tile, radius: 24, fill: color(31, 31, 34), stroke: color(255, 255, 255, 0.05))
        drawSymbol(index == decks.count - 1 ? "+" : "▰", in: CGRect(x: tile.minX + 24, y: tile.maxY - 74, width: 48, height: 48), size: index == decks.count - 1 ? 38 : 25, color: index == decks.count - 1 ? color(155, 155, 160) : blue)
        drawText(deck.0, in: CGRect(x: tile.minX + 24, y: tile.minY + 58, width: tile.width - 48, height: 50), size: isPad ? 27 : 23, weight: .bold, color: index == decks.count - 1 ? color(158, 158, 164) : .white)
        if index != decks.count - 1 {
            if index == 0 || index == 2 {
                let badge = CGRect(x: tile.maxX - 72, y: tile.maxY - 70, width: 48, height: 48)
                circle(badge, fill: orange)
                drawText(deck.1, in: badge.insetBy(dx: 0, dy: 12), size: isPad ? 19 : 17, weight: .heavy, color: .white, alignment: .center)
            }
            drawText("\(deck.1) \(copy.code == "de" ? "Karteikarten" : "cards")", in: CGRect(x: tile.minX + 24, y: tile.minY + 28, width: tile.width - 48, height: 30), size: isPad ? 19 : 17, weight: .medium, color: color(156, 156, 162))
        }
    }
}

func drawStudyScene(in screen: CGRect, copy: LocaleCopy, isPad: Bool) {
    let margin = screen.width * 0.075
    let card = CGRect(x: screen.minX + margin, y: screen.minY + screen.height * 0.27, width: screen.width - margin * 2, height: screen.height * 0.42)
    roundedRect(card, radius: 38, fill: color(32, 32, 36), stroke: color(255, 255, 255, 0.08))
    drawSymbol("✦", in: CGRect(x: card.midX - 42, y: card.maxY - 112, width: 84, height: 84), size: 70, color: purple)
    drawText(copy.cardQuestion, in: CGRect(x: card.minX + 42, y: card.midY + 20, width: card.width - 84, height: 120), size: isPad ? 40 : 34, weight: .heavy, color: .white, alignment: .center, lineHeight: isPad ? 48 : 42)
    drawText(copy.cardAnswer, in: CGRect(x: card.minX + 42, y: card.midY - 94, width: card.width - 84, height: 110), size: isPad ? 25 : 22, weight: .medium, color: color(175, 175, 184), alignment: .center, lineHeight: 30)
    let buttonY = screen.minY + screen.height * 0.14
    let bw = (screen.width - margin * 2 - 24) / 3
    for (idx, item) in [("Nochmal", color(236, 82, 82)), ("Unsicher", orange), ("Gewusst", mint)].enumerated() {
        let rect = CGRect(x: screen.minX + margin + CGFloat(idx) * (bw + 12), y: buttonY, width: bw, height: 58)
        roundedRect(rect, radius: 18, fill: item.1.withAlphaComponent(0.14))
        drawText(item.0, in: rect.insetBy(dx: 8, dy: 17), size: isPad ? 18 : 15, weight: .bold, color: item.1, alignment: .center)
    }
}

func drawAIScene(in screen: CGRect, copy: LocaleCopy, isPad: Bool) {
    let margin = screen.width * 0.075
    let panel = CGRect(x: screen.minX + margin, y: screen.minY + screen.height * 0.18, width: screen.width - margin * 2, height: screen.height * 0.56)
    roundedRect(panel, radius: 34, fill: color(246, 246, 248), stroke: color(255, 255, 255, 0.20))
    drawSymbol("✦", in: CGRect(x: panel.minX + 34, y: panel.maxY - 112, width: 76, height: 76), size: 66, color: purple)
    drawText(copy.aiTitle, in: CGRect(x: panel.minX + 34, y: panel.maxY - 170, width: panel.width - 68, height: 58), size: isPad ? 39 : 32, weight: .heavy)
    drawText(copy.aiSubtitle, in: CGRect(x: panel.minX + 34, y: panel.maxY - 230, width: panel.width - 68, height: 64), size: isPad ? 24 : 20, weight: .medium, color: muted, lineHeight: 28)
    let features = ["KI-Karten erstellen", "Beispiel geben", "Merksatz erzeugen", "Mini-Quiz stellen"]
    for (index, feature) in features.enumerated() {
        let y = panel.maxY - 310 - CGFloat(index) * 70
        circle(CGRect(x: panel.minX + 34, y: y, width: 38, height: 38), fill: blue.withAlphaComponent(0.14))
        drawSymbol(index % 2 == 0 ? "✦" : "✓", in: CGRect(x: panel.minX + 36, y: y + 2, width: 34, height: 34), size: 24, color: blue)
        drawText(feature, in: CGRect(x: panel.minX + 88, y: y + 6, width: panel.width - 120, height: 34), size: isPad ? 23 : 19, weight: .bold)
    }
    let cta = CGRect(x: panel.minX + 34, y: panel.minY + 40, width: panel.width - 68, height: 68)
    roundedRect(cta, radius: 22, fill: color(42, 148, 255))
    drawText(isPad ? "2,99 € / Monat" : "2,99 € / Monat", in: cta.insetBy(dx: 16, dy: 19), size: isPad ? 23 : 20, weight: .bold, color: .white, alignment: .center)
}

func drawAudioScene(in screen: CGRect, copy: LocaleCopy, isPad: Bool) {
    let margin = screen.width * 0.075
    let panel = CGRect(x: screen.minX + margin, y: screen.minY + screen.height * 0.20, width: screen.width - margin * 2, height: screen.height * 0.52)
    roundedRect(panel, radius: 34, fill: color(32, 32, 36), stroke: color(255, 255, 255, 0.08))
    drawText(copy.settings, in: CGRect(x: panel.minX + 34, y: panel.maxY - 78, width: panel.width - 68, height: 42), size: isPad ? 36 : 29, weight: .heavy, color: .white)
    let rows = [("Deutsch", "de-DE", blue), ("English", "en-US", purple), ("Español", "es-ES", orange), ("Audio", "1.2×", mint)]
    for (index, row) in rows.enumerated() {
        let rect = CGRect(x: panel.minX + 34, y: panel.maxY - 160 - CGFloat(index) * 88, width: panel.width - 68, height: 64)
        roundedRect(rect, radius: 18, fill: color(255, 255, 255, 0.08))
        drawText(row.0, in: CGRect(x: rect.minX + 20, y: rect.minY + 18, width: rect.width * 0.55, height: 30), size: isPad ? 24 : 20, weight: .bold, color: .white)
        drawText(row.1, in: CGRect(x: rect.midX, y: rect.minY + 18, width: rect.width * 0.42, height: 30), size: isPad ? 22 : 18, weight: .semibold, color: row.2, alignment: .right)
    }
    drawSymbol("▶", in: CGRect(x: panel.midX - 44, y: panel.minY + 48, width: 88, height: 88), size: 72, color: mint)
}

func render(copy: LocaleCopy, screenshot: ScreenshotCopy, index: Int, canvas: Canvas) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.size.width),
        pixelsHigh: Int(canvas.size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "ScreenshotGeneration", code: 1)
    }

    bitmap.size = canvas.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    drawBackground(canvas: canvas)
    drawHeader(copy: copy, screenshot: screenshot, canvas: canvas)

    let deviceRect: CGRect
    if canvas.isPad {
        deviceRect = CGRect(x: 420, y: 170, width: 1208, height: 1670)
    } else {
        deviceRect = CGRect(x: 142, y: 150, width: 1000, height: 1750)
    }
    drawDeviceFrame(in: deviceRect, canvas: canvas, scene: screenshot.scene, copy: copy)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScreenshotGeneration", code: 1)
    }

    let kind = canvas.isPad ? "ipad_2048x2732" : "iphone_1284x2778"
    let dir = outputRoot.appendingPathComponent(copy.code).appendingPathComponent(kind)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(String(format: "%02d_%@.png", index + 1, screenshot.scene.fileName))
    try data.write(to: file)
}

extension Scene {
    var fileName: String {
        switch self {
        case .overview: "learn_with_teresa"
        case .decks: "decks"
        case .study: "study_cards"
        case .ai: "ai_features"
        case .audio: "language_audio"
        }
    }
}

for locale in locales {
    try? FileManager.default.removeItem(at: outputRoot.appendingPathComponent(locale.code))
}
for locale in locales {
    for (index, screenshot) in locale.screenshots.enumerated() {
        try render(copy: locale, screenshot: screenshot, index: index, canvas: iphone)
        try render(copy: locale, screenshot: screenshot, index: index, canvas: ipad)
    }
}

print("Generated App Store screenshots in \(outputRoot.path)")
