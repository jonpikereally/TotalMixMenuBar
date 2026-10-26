import AppKit
import SwiftUI

/// The on-screen volume overlay shown when a volume key changes TotalMix,
/// in place of the macOS one.
final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = HUDModel()

    func show(name: String, icon: String, db: Double, muted: Bool, dimmed: Bool) {
        model.name = name
        model.icon = icon
        model.db = db
        model.muted = muted
        model.dimmed = dimmed
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 140))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel?.animator().alphaValue = 0
            }, completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 86),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }
}

final class HUDModel: ObservableObject {
    @Published var name = ""
    @Published var icon = "speaker.wave.2.fill"
    @Published var db = -65.0
    @Published var muted = false
    @Published var dimmed = false
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.muted ? "speaker.slash.fill" : model.icon)
                    .foregroundStyle(model.muted ? Theme.red : .white)
                Text(model.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.dimmed { Text("DIM").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber) }
                Text(model.muted ? "Muted" : FaderCurve.format(model.db))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LevelBar(fraction: Theme.fraction(model.db), tint: model.muted ? .gray : Theme.blue)
                .frame(height: 6)
        }
        .padding(16)
        .frame(width: 260, height: 86)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke))
        .environment(\.colorScheme, .dark)
    }
}

struct LevelBar: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
    }
}
