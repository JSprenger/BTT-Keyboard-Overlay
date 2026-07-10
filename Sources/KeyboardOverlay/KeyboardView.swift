import SwiftUI

// MARK: - Gesamtansicht

struct ContentView: View {
    @ObservedObject var state: OverlayState
    let controller: OverlayController

    var body: some View {
        // Alles in Units der Fensterbreite → Inhalt skaliert mit dem Fenster,
        // das Seitenverhältnis ist fix (AppMain setzt contentAspectRatio).
        GeometryReader { proxy in
            let unit = proxy.size.width / KeyboardGeometry.contentUnitsWide
            VStack(spacing: unit * KeyboardGeometry.topBarSpacing) {
                TopBar(state: state, controller: controller, unit: unit)
                    .frame(height: unit * KeyboardGeometry.topBarHeight)
                KeyboardView(state: state)
            }
            .padding(unit * KeyboardGeometry.padding)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Kopfzeile

struct TopBar: View {
    @ObservedObject var state: OverlayState
    let controller: OverlayController
    let unit: CGFloat

    private var captionSize: CGFloat { unit * 0.18 }

    var body: some View {
        HStack(spacing: unit * 0.2) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: unit * 0.28))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Tastaturübersicht+ beenden")

            Text(state.layoutName)
                .font(.system(size: unit * 0.24, weight: .semibold))

            HStack(spacing: unit * 0.07) {
                Circle().fill(Color.accentColor).frame(width: unit * 0.12, height: unit * 0.12)
                Text("\(state.bttReplacements.count) BTT-Ersetzungen")
                Button {
                    controller.reloadBTT()
                    state.showToast("BTT neu geladen")
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("BTT-Ersetzungen neu laden")
            }
            .font(.system(size: captionSize))
            .foregroundStyle(.secondary)

            HStack(spacing: unit * 0.07) {
                Circle().fill(Color.orange).frame(width: unit * 0.12, height: unit * 0.12)
                Text("Akzenttaste")
            }
            .font(.system(size: captionSize))
            .foregroundStyle(.secondary)

            if state.liveDeadKeyState != 0 {
                Text("Akzent aktiv – nächste Taste kombiniert (esc bricht ab)")
                    .font(.system(size: captionSize))
                    .foregroundStyle(.orange)
            }

            Spacer()

            if let toast = state.toast {
                Text(toast)
                    .font(.system(size: captionSize))
                    .padding(.horizontal, unit * 0.12)
                    .padding(.vertical, unit * 0.05)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    .transition(.opacity)
            }

            if !state.monitoringActive {
                Button {
                    controller.openInputMonitoringSettings()
                } label: {
                    Label("Eingabeüberwachung erlauben", systemImage: "exclamationmark.triangle")
                        .font(.system(size: captionSize))
                }
                .help("""
                    Ohne die Berechtigung „Eingabeüberwachung“ kann das Overlay \
                    gedrückte Tasten nicht anzeigen. Modifier lassen sich \
                    trotzdem per Klick umschalten.
                    """)
            }

            HStack(spacing: unit * 0.07) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: captionSize))
                    .foregroundStyle(.secondary)
                Slider(value: $state.windowAlpha, in: 0.25...1)
                    .frame(width: unit * 1.8)
                    .controlSize(.mini)
            }
            .help("Transparenz des Overlays")
        }
        .animation(.easeInOut(duration: 0.15), value: state.toast)
    }
}

// MARK: - Tastatur

struct KeyboardView: View {
    @ObservedObject var state: OverlayState
    private let keys = KeyboardGeometry.makeLayout()

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / KeyboardGeometry.totalWidth
            ZStack(alignment: .topLeading) {
                ForEach(keys) { cap in
                    KeyView(cap: cap, state: state, unit: unit)
                        .frame(width: cap.width * unit, height: cap.height * unit)
                        .offset(x: cap.x * unit, y: cap.y * unit)
                }
            }
        }
    }
}

// MARK: - Einzelne Taste

struct KeyView: View {
    let cap: KeyCap
    @ObservedObject var state: OverlayState
    let unit: CGFloat

    var body: some View {
        let info = keyInfo
        Button {
            state.keyClicked(cap)
        } label: {
            keyShape
                .fill(fillColor(info: info))
                .overlay(keyShape.strokeBorder(borderColor(info: info), lineWidth: info.isDead ? 1.5 : 0.5))
                .overlay(labelView(info: info))
                .overlay(alignment: .topTrailing) {
                    if info.source == .btt {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: unit * 0.14, height: unit * 0.14)
                            .padding(unit * 0.1)
                    }
                }
                .overlay(alignment: .bottom) {
                    // Orientierungsstrich wie der fühlbare Steg auf F und J.
                    if KeyboardGeometry.homeRowKeyCodes.contains(cap.keyCode) {
                        Capsule()
                            .fill(.secondary)
                            .frame(width: unit * 0.28, height: unit * 0.05)
                            .padding(.bottom, unit * 0.12)
                    }
                }
                .padding(unit * 0.04)
        }
        .buttonStyle(.plain)
        .help(helpText(info: info))
    }

    // MARK: Anzeige-Inhalt

    private struct Info {
        var text = ""
        var systemImage: String?
        var source: KeyDisplay.Source = .none
        var isDead = false
        var pressed = false
        var secondary = false  // kleinere, graue Beschriftung (Modifier etc.)
    }

    private var keyInfo: Info {
        var info = Info()
        info.pressed = state.pressedKeys.contains(cap.keyCode)

        switch cap.kind {
        case .character, .isoEnter:
            let display = state.display(forKeyCode: cap.keyCode)
            info.text = display.text
            info.source = display.source
            info.isDead = display.isDead
            if case .isoEnter = cap.kind, info.text.isEmpty || info.text == "\r" || info.text == "\n" {
                info.text = "↩"
                info.secondary = true
                info.source = .none
            }
        case .modifier(let flag):
            info.text = modifierSymbol(flag)
            info.secondary = true
            if state.isModifierActive(flag) { info.pressed = true }
        case .special(let label):
            info.text = label
            info.secondary = true
        case .fkey(let number):
            if state.displayFlags.contains(.maskSecondaryFn) {
                info.text = "F\(number)"
            } else {
                info.systemImage = fRowMediaSymbols[number - 1]
            }
            info.secondary = true
        }
        return info
    }

    private func modifierSymbol(_ flag: CGEventFlags) -> String {
        switch flag {
        case .maskShift: return "⇧"
        case .maskControl: return "⌃"
        case .maskAlternate: return "⌥"
        case .maskCommand: return "⌘"
        case .maskSecondaryFn: return "fn"
        case .maskAlphaShift: return "⇪"
        default: return ""
        }
    }

    // MARK: Optik

    private var keyShape: AnyInsettableShape {
        if case .isoEnter = cap.kind {
            return AnyInsettableShape(ISOEnterShape())
        }
        return AnyInsettableShape(RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous))
    }

    private func fillColor(info: Info) -> Color {
        if info.pressed {
            return Color.accentColor.opacity(0.55)
        }
        if info.isDead {
            return Color.orange.opacity(0.35)
        }
        if info.source == .btt {
            return Color.accentColor.opacity(0.16)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.9)
    }

    private func borderColor(info: Info) -> Color {
        info.isDead ? Color.orange : Color.primary.opacity(0.15)
    }

    @ViewBuilder
    private func labelView(info: Info) -> some View {
        if let symbol = info.systemImage {
            Image(systemName: symbol)
                .font(.system(size: unit * 0.28))
                .foregroundStyle(.secondary)
        } else {
            let baseSize = info.secondary ? unit * 0.26 : unit * 0.38
            Text(info.text)
                .font(.system(size: baseSize))
                .fontWeight(info.source == .btt ? .semibold : .regular)
                .foregroundStyle(info.secondary
                    ? AnyShapeStyle(.secondary)
                    : (info.source == .btt ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, unit * 0.08)
        }
    }

    private func helpText(info: Info) -> String {
        switch cap.kind {
        case .character, .isoEnter:
            let display = state.display(forKeyCode: cap.keyCode)
            let tip = state.tooltip(for: display)
            return tip.isEmpty ? "" : tip + "\nKlick kopiert das Zeichen"
        case .modifier:
            return "Klick schaltet den Modifier für die Vorschau um"
        default:
            return ""
        }
    }
}

// MARK: - ISO-Enter-Form (L-förmig über zwei Reihen)

struct ISOEnterShape: InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> ISOEnterShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = min(r.width, r.height) * 0.08
        // Oberer Teil: volle Breite, obere Hälfte.
        // Unterer Teil: rechte 75 % der Breite, untere Hälfte.
        let notchX = r.minX + r.width * 0.25
        let midY = r.minY + r.height * 0.5

        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY),
                 tangent2End: CGPoint(x: r.maxX, y: r.minY + radius), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX - radius, y: r.maxY), radius: radius)
        p.addLine(to: CGPoint(x: notchX + radius, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: notchX, y: r.maxY),
                 tangent2End: CGPoint(x: notchX, y: r.maxY - radius), radius: radius)
        p.addLine(to: CGPoint(x: notchX, y: midY + radius))
        p.addArc(tangent1End: CGPoint(x: notchX, y: midY),
                 tangent2End: CGPoint(x: notchX - radius, y: midY), radius: radius)
        p.addLine(to: CGPoint(x: r.minX + radius, y: midY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: midY),
                 tangent2End: CGPoint(x: r.minX, y: midY - radius), radius: radius)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + radius, y: r.minY), radius: radius)
        p.closeSubpath()
        return p
    }
}

/// Typ-Radierer, damit RoundedRectangle und ISOEnterShape dieselbe
/// View-Hierarchie durchlaufen können.
struct AnyInsettableShape: InsettableShape {
    private let makePath: @Sendable (CGRect) -> Path
    private let insetAmount: CGFloat
    private let insetFn: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        makePath = { rect in shape.path(in: rect) }
        insetAmount = 0
        insetFn = { amount in AnyInsettableShape(shape.inset(by: amount)) }
    }

    func path(in rect: CGRect) -> Path {
        makePath(rect)
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        insetFn(amount)
    }
}
