import SwiftUI

enum Theme {
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let card = Color(white: 0.2)
    static let cardHover = Color(white: 0.24)
    static let stroke = Color.white.opacity(0.08)
    static let blue = Color(red: 0.25, green: 0.47, blue: 1.0)
    static let red = Color(red: 0.91, green: 0.27, blue: 0.22)
    static let amber = Color(red: 0.96, green: 0.6, blue: 0.18)
    static let green = Color(red: 0.24, green: 0.72, blue: 0.36)

    static func fraction(_ db: Double) -> Double { FaderCurve.linear(fromDb: db) }
}

/// What the popover's "…" button and the status item's right-click show.
struct MenuActions {
    var openSettings: () -> Void = {}
    var showMenu: (NSView?) -> Void = { _ in }
    var toggleLevels: () -> Void = {}
}

struct ContentView: View {
    @ObservedObject var mixer = Mixer.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var status = AppStatus.shared
    var actions: MenuActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let banner = status.banner { BannerView(error: banner.error, action: banner.action) }
            if mixer.link == .connected {
                outputs
                Divider().overlay(Theme.stroke)
                controlRoom
                let ins = prefs.inputs(from: mixer)
                if !ins.isEmpty {
                    Divider().overlay(Theme.stroke)
                    inputs(ins)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("MixBar").font(.system(size: 14, weight: .bold))
            if !mixer.device.isEmpty {
                Text(mixer.device).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: actions.toggleLevels) {
                Text("Levels").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(prefs.levelsWindow ? Theme.blue : .secondary)
            }
            .buttonStyle(.plain)
            .help("Show the input level meters in a floating window")
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            MenuAnchor(show: actions.showMenu)
                .frame(width: 16, height: 16)
                .help("Updates, Open at Login, Quit")
        }
    }

    // MARK: Outputs

    private var outputs: some View {
        VStack(spacing: 12) {
            let target = prefs.keyTarget(from: mixer)?.index
            ForEach(prefs.outputs(from: mixer)) { ch in
                OutputRow(ch: ch, label: prefs.label(for: ch), isKeyTarget: ch.index == target && prefs.volumeKeys)
            }
            if prefs.outputs(from: mixer).isEmpty {
                Text("Waiting for TotalMix's outputs…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Control Room

    private var controlRoom: some View {
        VStack(spacing: 8) {
            PillToggle(title: "Speaker B", on: mixer.speakerB, tint: Theme.blue) { mixer.setSpeakerB(!mixer.speakerB) }
            HStack(spacing: 8) {
                PillToggle(title: "Dim", on: mixer.dim, tint: Theme.amber) { mixer.setDim(!mixer.dim) }
                PillToggle(title: "Mono", on: mixer.mono, tint: Theme.blue) { mixer.setMono(!mixer.mono) }
                    .help(prefs.monoShortcut ? "Mono — ⇧⌘M" : "Mono")
            }
        }
    }

    // MARK: Inputs

    private func inputs(_ channels: [Channel]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(4, max(channels.count, 1))),
                  spacing: 10) {
            ForEach(channels) { ch in InputColumn(ch: ch) }
        }
    }
}

// MARK: - Pieces

/// Shared state for the banner at the top of the popover.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()
    struct Banner {
        let error: AppError
        let action: (title: String, run: () -> Void)?
    }
    @Published var banner: Banner?
}

struct OutputRow: View {
    let ch: Channel
    let label: String
    let isKeyTarget: Bool
    @ObservedObject var mixer = Mixer.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: ch.looksLikePhones ? "headphones" : "hifispeaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Button { prefs.keyOutput = ch.index } label: {
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help(isKeyTarget ? "The volume keys control this output" : "Click to control this output with the volume keys")
                if isKeyTarget {
                    Image(systemName: "keyboard").font(.system(size: 9)).foregroundStyle(Theme.blue)
                }
                Spacer()
                Text(ch.mute ? "Muted" : FaderCurve.format(ch.volume))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ch.mute ? Theme.red : .secondary)
            }
            HStack(spacing: 6) {
                Button { mixer.setMute(output: ch.index, !ch.mute) } label: {
                    Image(systemName: ch.mute ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ch.mute ? Theme.red : .secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(ch.mute ? "Unmute" : "Mute")
                MiniToggle(title: "Comp", on: ch.dynamics) { mixer.setDynamics(.output, ch.index, !ch.dynamics) }
                MiniToggle(title: "EQ", on: ch.eq) { mixer.setEQ(.output, ch.index, !ch.eq) }
                FaderSlider(db: ch.volume, maxDb: prefs.maxDb, dimmed: ch.mute) { mixer.setVolume(output: ch.index, db: $0) }
                    .frame(height: 18)
            }
        }
    }
}

struct InputColumn: View {
    let ch: Channel
    @ObservedObject var mixer = Mixer.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let locked = prefs.phantomLocked.isEmpty ? false : mixer.phantomLocked(input: ch.index)
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                if ch.stereo { Image(systemName: "link").font(.system(size: 8)).foregroundStyle(.secondary) }
                Text(ch.displayName).font(.system(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            }
            .help(ch.stereo ? "Stereo pair — right-click to unlink" : "Right-click to link as a stereo pair")
            // A locked input can still have 48V switched off if TotalMix has it on.
            IconToggle(symbol: locked ? "bolt.slash.fill" : "bolt.fill", on: ch.phantom, tint: Theme.red,
                       enabled: ch.hasPhantom && (!locked || ch.phantom),
                       help: locked ? "48V is turned off for this input in Settings" : "48V phantom power",
                       disabledHelp: locked ? "48V is turned off for this input in Settings" : nil) {
                mixer.setPhantom(input: ch.index, !ch.phantom)
            }
            IconToggle(symbol: "guitars.fill", on: ch.instrument, tint: Theme.amber, enabled: ch.hasInstrument,
                       help: "Instrument (Hi-Z) input") { mixer.setInstrument(input: ch.index, !ch.instrument) }
            TextToggle(title: "Comp", on: ch.dynamics, tint: Theme.green) { mixer.setDynamics(.input, ch.index, !ch.dynamics) }
            TextToggle(title: "EQ", on: ch.eq, tint: Theme.green) { mixer.setEQ(.input, ch.index, !ch.eq) }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke))
        .contextMenu { stereoMenu }
    }

    /// Link or unlink this input with its odd/even partner (1+2, 3+4 …).
    @ViewBuilder private var stereoMenu: some View {
        let left = ch.index - ch.index % 2
        if ch.stereo {
            Button("Unlink Stereo Pair") { mixer.setStereo(input: left, false) }
        } else if let partner = mixer.input(ch.index % 2 == 0 ? ch.index + 1 : ch.index - 1), !partner.hidden {
            let l = mixer.input(left)?.displayName ?? ""
            let r = mixer.input(left + 1)?.displayName ?? ""
            if let reason = mixer.stereoLinkBlocked(left: left) {
                Button("Link \(l) + \(r) as Stereo") {}.disabled(true)
                Text(reason)
            } else {
                Button("Link \(l) + \(r) as Stereo") { mixer.setStereo(input: left, true) }
            }
        } else {
            Text("No partner channel to link with")
        }
    }
}

struct PillToggle: View {
    let title: String
    let on: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Circle().fill(on ? tint : Color.white.opacity(0.18)).frame(width: 7, height: 7)
                    .shadow(color: on ? tint : .clear, radius: 3)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? tint.opacity(0.22) : (hover ? Theme.cardHover : Theme.card)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconToggle: View {
    let symbol: String
    let on: Bool
    let tint: Color
    let enabled: Bool
    let help: String
    var disabledHelp: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(on ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Capsule().fill(on ? tint : Theme.card))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .help(enabled ? help : disabledHelp ?? "\(help) — not available on this input")
    }
}

struct TextToggle: View {
    let title: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(on ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Capsule().fill(on ? tint : Theme.card))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct MiniToggle: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(on ? Theme.green : Color.white.opacity(0.35))
        }
        .buttonStyle(.plain)
        .help("\(title) on this output")
    }
}

/// A thin TotalMix-style fader. Positions follow TotalMix's own curve, so the
/// knob sits where it does in TotalMix.
struct FaderSlider: View {
    let db: Double
    let maxDb: Double
    let dimmed: Bool
    let onChange: (Double) -> Void
    @State private var dragging: Double?
    @State private var lastSent = Date.distantPast

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let pos = dragging ?? Theme.fraction(db)
            let limit = Theme.fraction(maxDb)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                if limit < 1 {
                    Rectangle().fill(Theme.red.opacity(0.5)).frame(width: 1.5, height: 9)
                        .offset(x: limit * w - 0.75)
                }
                Capsule().fill(dimmed ? Color.gray : Theme.blue).frame(width: max(4, pos * w), height: 4)
                Circle().fill(Color(white: 0.75)).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: pos * (w - 14))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let f = min(max(v.location.x / w, 0), min(1, limit))
                    dragging = f
                    // About 30 updates a second is plenty for UDP and TotalMix.
                    if Date().timeIntervalSince(lastSent) > 0.033 {
                        lastSent = Date()
                        onChange(FaderCurve.db(fromLinear: f).rounded(toPlaces: 1))
                    }
                }
                .onEnded { _ in
                    if let f = dragging { onChange(FaderCurve.db(fromLinear: f).rounded(toPlaces: 1)) }
                    dragging = nil
                })
        }
        .help(FaderCurve.format(db))
    }
}

struct BannerView: View {
    let error: AppError
    let action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(error.code.summary).font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(error.code.hint).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Error code: \(error.code.rawValue)").font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if let action {
                    Button(action.title, action: action.run).controlSize(.small)
                }
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ErrorReporter.details(error), forType: .string)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.amber.opacity(0.35)))
        .help(ErrorReporter.tooltip)
    }
}

/// An "…" button that pops the app menu from itself.
struct MenuAnchor: NSViewRepresentable {
    let show: (NSView?) -> Void

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")!,
                         target: context.coordinator, action: #selector(Coordinator.click(_:)))
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    func updateNSView(_ nsView: NSButton, context: Context) { context.coordinator.show = show }
    func makeCoordinator() -> Coordinator { Coordinator(show: show) }

    final class Coordinator: NSObject {
        var show: (NSView?) -> Void
        init(show: @escaping (NSView?) -> Void) { self.show = show }
        @objc func click(_ sender: NSButton) { show(sender) }
    }
}
