import AppKit
import SwiftUI
import ServiceManagement

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "MixBar Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            w.setFrameAutosaveName("MixBarSettings")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var mixer = Mixer.shared
    @State private var host = Prefs.shared.host
    @State private var sendPort = String(Prefs.shared.sendPort)
    @State private var listenPort = String(Prefs.shared.listenPort)
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = MediaKeys.accessibilityTrusted

    var body: some View {
        Form {
            Section("TotalMix connection") {
                HStack {
                    Circle().fill(linkColor).frame(width: 8, height: 8)
                    Text(linkText).font(.callout)
                }
                TextField("TotalMix host", text: $host)
                TextField("Port incoming (TotalMix listens on)", text: $sendPort)
                TextField("Port outgoing (MixBar listens on)", text: $listenPort)
                HStack {
                    Button("Apply and Reconnect") { applyConnection() }
                    Button("Copy TotalMix Setup Steps") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(setupSteps, forType: .string)
                    }
                }
                Text(setupSteps).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }

            Section("Outputs in the menu") {
                Text("None ticked = the Main and Phones outputs from TotalMix's Control Room settings.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(mixer.visible(.output)) { ch in
                    HStack {
                        Toggle(ch.displayName, isOn: binding(for: ch.index, in: \.shownOutputs))
                            .frame(width: 140, alignment: .leading)
                        TextField("Label", text: labelBinding(ch.index), prompt: Text(ch.displayName))
                    }
                }
            }

            Section("Inputs in the menu and Levels window") {
                Text("None ticked = up to four inputs that have 48V or Instrument.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading) {
                    ForEach(mixer.visible(.input)) { ch in
                        Toggle(ch.displayName, isOn: binding(for: ch.index, in: \.shownInputs))
                    }
                }
            }

            Section("Volume keys") {
                Toggle("Volume keys control TotalMix", isOn: $prefs.volumeKeys)
                if prefs.volumeKeys && !axTrusted {
                    HStack {
                        Text("⚠️ Needs Accessibility permission (\(ErrorCode.accessibilityMissing.rawValue))")
                            .help(ErrorReporter.tooltip)
                        Button("Grant…") {
                            MediaKeys.promptForAccessibility()
                            MediaKeys.openAccessibilitySettings()
                        }
                    }
                }
                Picker("Output", selection: $prefs.keyOutput) {
                    Text("First output in the menu").tag(-1)
                    ForEach(mixer.visible(.output)) { ch in Text(prefs.label(for: ch)).tag(ch.index) }
                }
                HStack {
                    Text("Step")
                    Slider(value: $prefs.stepDb, in: 1...10, step: 1)
                    Text("\(Int(prefs.stepDb)) dB").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Never louder than")
                    Slider(value: $prefs.maxDb, in: -30...6, step: 1)
                    Text(FaderCurve.format(prefs.maxDb)).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                Picker("Mute key", selection: $prefs.muteKey) {
                    ForEach(Prefs.MuteKeyAction.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Only when the RME is the Mac's sound output", isOn: $prefs.onlyWhenRMEIsOutput)
                Toggle("Show the volume overlay", isOn: $prefs.showHUD)
                Text("Hold ⇧⌥ while pressing a volume key for ¼ steps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("⇧⌘M toggles Mono", isOn: $prefs.monoShortcut)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { setOpenAtLogin($0) }
                Text("MixBar v\(AppVersion.version) (built \(AppVersion.built))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 500)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = MediaKeys.accessibilityTrusted
        }
    }

    private var setupSteps: String {
        """
        In TotalMix FX 2.1 or newer:
        1. Options → Settings → OSC tab.
        2. Pick a free Remote Controller slot and tick "In Use".
        3. Port incoming: \(sendPort)   Port outgoing: \(listenPort)
        4. IP or Host Name: 127.0.0.1 (this Mac).
        5. Compatibility (Mode): Global OSC. Under Details, tick Send changes and Send status.
        6. Tick "Send Level Data" for the Levels window.
        7. Options → Enable OSC Control must be ticked.
        """
    }

    private var linkColor: Color {
        switch mixer.link {
        case .connected: return Theme.green
        case .starting: return .gray
        default: return Theme.red
        }
    }

    private var linkText: String {
        switch mixer.link {
        case .connected: return mixer.device.isEmpty ? "Connected" : "Connected to \(mixer.device)"
        case .starting: return "Connecting…"
        case .legacyMode: return "\(ErrorCode.legacyMode.summary) (\(ErrorCode.legacyMode.rawValue))"
        case .silent: return "\(ErrorCode.noResponse.summary) (\(ErrorCode.noResponse.rawValue))"
        case .failed(let e): return "\(e.code.summary) (\(e.code.rawValue))"
        }
    }

    private func applyConnection() {
        prefs.host = host.trimmingCharacters(in: .whitespaces)
        if let p = Int(sendPort), (1...65535).contains(p) { prefs.sendPort = p } else { sendPort = String(prefs.sendPort) }
        if let p = Int(listenPort), (1...65535).contains(p) { prefs.listenPort = p } else { listenPort = String(prefs.listenPort) }
        mixer.reconnect()
    }

    private func binding(for index: Int, in key: ReferenceWritableKeyPath<Prefs, [Int]>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: key].contains(index) },
            set: { on in
                var list = prefs[keyPath: key].filter { $0 != index }
                if on { list.append(index); list.sort() }
                prefs[keyPath: key] = list
            })
    }

    private func labelBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { prefs.outputLabels[String(index)] ?? "" },
            set: { prefs.outputLabels[String(index)] = $0.isEmpty ? nil : $0 })
    }

    private func setOpenAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            ErrorReporter.shared.report(AppError(.loginItemFailed, error.localizedDescription),
                                        surface: .alert, title: "Couldn't change Open at Login")
        }
        openAtLogin = service.status == .enabled
    }
}
