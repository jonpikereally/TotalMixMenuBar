import AppKit
import SwiftUI

// Renders the popover and the volume overlay to PNGs, fed by the fake
// TotalMix, so the look can be checked without installing. ./test.sh --snapshot
let prefs = Prefs.shared
prefs.sendPort = Int(CommandLine.arguments[1])!
prefs.listenPort = Int(CommandLine.arguments[2])!
prefs.shownInputs = []
prefs.shownOutputs = []
let out = URL(fileURLWithPath: CommandLine.arguments[3])
_ = NSApplication.shared
Mixer.shared.connect()
RunLoop.main.run(until: Date().addingTimeInterval(2.5))

@MainActor func render<V: View>(_ view: V, _ name: String) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed: \(name)"); return
    }
    try! png.write(to: out.appendingPathComponent(name))
    print("wrote \(name)")
}
MainActor.assumeIsolated {
    render(ContentView(actions: MenuActions()), "popover.png")
    AppStatus.shared.banner = .init(error: AppError(.legacyMode), action: nil)
    render(ContentView(actions: MenuActions()).environmentObject(Mixer.shared), "popover-banner.png")
}
