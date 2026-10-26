import AppKit
import SwiftUI

/// Small always-on-top meter window for the popover's inputs. A channel name
/// turns red when it clips and stays red until you click it.
final class LevelsWindow: NSObject, NSWindowDelegate {
    static let shared = LevelsWindow()
    private var panel: NSPanel?
    var onClose: () -> Void = {}

    var isShown: Bool { panel?.isVisible == true }

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 120),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .hudWindow],
                            backing: .buffered, defer: false)
            p.title = "Levels"
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.delegate = self
            let host = NSHostingView(rootView: LevelsView())
            host.sizingOptions = [.preferredContentSize]
            p.contentView = host
            p.setFrameAutosaveName("MixBarLevels")
            if p.frame.origin == .zero, let s = NSScreen.main {
                p.setFrameOrigin(NSPoint(x: s.visibleFrame.maxX - 260, y: s.visibleFrame.maxY - 200))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    func windowWillClose(_ notification: Notification) { onClose() }
}

private struct LevelsView: View {
    @ObservedObject var mixer = Mixer.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var peaks: [Int: (db: Double, at: Date)] = [:]
    @State private var clipped: Set<Int> = []

    var body: some View {
        let channels = prefs.inputs(from: mixer)
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { ctx in
            VStack(spacing: 7) {
                if channels.isEmpty {
                    Text(mixer.link == .connected ? "No inputs chosen" : "Not connected to TotalMix")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(channels) { ch in
                    row(ch, now: ctx.date)
                }
            }
            .padding(10)
            .frame(width: 230)
        }
        .environment(\.colorScheme, .dark)
    }

    private func level(_ ch: Channel) -> Double {
        let l = mixer.levels[ch.index] ?? -100
        return ch.stereo ? max(l, mixer.levels[ch.index + 1] ?? -100) : l
    }

    private func row(_ ch: Channel, now: Date) -> some View {
        let db = level(ch)
        let peak = updatePeak(ch.index, db, now)
        let isClipped = clipped.contains(ch.index)
        return HStack(spacing: 8) {
            Text(ch.displayName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isClipped ? Theme.red : .primary)
                .frame(width: 44, alignment: .leading)
                .lineLimit(1)
            MeterBar(db: db, peak: peak).frame(height: 7)
            Text(db <= -99 ? "−∞" : String(format: "%.1f", peak).replacingOccurrences(of: "-", with: "−"))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(isClipped ? Theme.red : .secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { clipped.remove(ch.index) }
        .help(isClipped ? "Clipped — click to reset" : ch.displayName)
    }

    /// Peak hold for 1.5 s, and the clip latch at 0 dBFS.
    private func updatePeak(_ i: Int, _ db: Double, _ now: Date) -> Double {
        var p = peaks[i] ?? (db, now)
        if db >= p.db || now.timeIntervalSince(p.at) > 1.5 { p = (db, now) }
        DispatchQueue.main.async {
            peaks[i] = p
            if db >= -0.1 { clipped.insert(i) }
        }
        return p.db
    }
}

private struct MeterBar: View {
    let db: Double
    let peak: Double

    /// Maps −60…0 dBFS onto the bar.
    private func x(_ v: Double) -> Double { min(max((v + 60) / 60, 0), 1) }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                LinearGradient(stops: [.init(color: Theme.green, location: 0),
                                       .init(color: Theme.green, location: 0.75),
                                       .init(color: Theme.amber, location: 0.88),
                                       .init(color: Theme.red, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .mask(alignment: .leading) { Capsule().frame(width: x(db) * w) }
                Rectangle().fill(Color.white.opacity(0.8)).frame(width: 1.5)
                    .offset(x: max(0, x(peak) * w - 1.5))
                    .opacity(peak > -60 ? 1 : 0)
            }
        }
    }
}
