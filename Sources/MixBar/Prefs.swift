import Foundation
import Combine

/// Settings, saved in UserDefaults (com.jonpike.mixbar).
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    enum MuteKeyAction: String, CaseIterable, Identifiable {
        case dim, mute
        var id: String { rawValue }
        var label: String { self == .dim ? "Dim" : "Mute the output" }
    }

    // Connection — must match the remote set up in TotalMix's OSC settings.
    @Published var host: String { didSet { d.set(host, forKey: "host") } }
    @Published var sendPort: Int { didSet { d.set(sendPort, forKey: "sendPort") } }
    @Published var listenPort: Int { didSet { d.set(listenPort, forKey: "listenPort") } }

    // What the popover shows. Empty means "pick sensibly from what TotalMix reports".
    @Published var shownOutputs: [Int] { didSet { d.set(shownOutputs, forKey: "shownOutputs") } }
    @Published var shownInputs: [Int] { didSet { d.set(shownInputs, forKey: "shownInputs") } }
    @Published var outputLabels: [String: String] { didSet { d.set(outputLabels, forKey: "outputLabels") } }
    /// Inputs whose 48V MixBar will never switch on (ribbon mics, line gear).
    /// Switching it off is still allowed, in case TotalMix already has it on.
    @Published var phantomLocked: [Int] { didSet { d.set(phantomLocked, forKey: "phantomLocked") } }

    // Volume keys
    @Published var volumeKeys: Bool { didSet { d.set(volumeKeys, forKey: "volumeKeys") } }
    /// Output the keys control; -1 = the first shown output.
    @Published var keyOutput: Int { didSet { d.set(keyOutput, forKey: "keyOutput") } }
    @Published var stepDb: Double { didSet { d.set(stepDb, forKey: "stepDb") } }
    /// Ceiling for every volume change MixBar makes, to protect ears and speakers.
    @Published var maxDb: Double { didSet { d.set(maxDb, forKey: "maxDb") } }
    @Published var onlyWhenRMEIsOutput: Bool { didSet { d.set(onlyWhenRMEIsOutput, forKey: "onlyWhenRMEIsOutput") } }
    @Published var muteKey: MuteKeyAction { didSet { d.set(muteKey.rawValue, forKey: "muteKey") } }
    @Published var showHUD: Bool { didSet { d.set(showHUD, forKey: "showHUD") } }

    @Published var monoShortcut: Bool { didSet { d.set(monoShortcut, forKey: "monoShortcut") } }
    @Published var levelsWindow: Bool { didSet { d.set(levelsWindow, forKey: "levelsWindow") } }
    @Published var showGain: Bool { didSet { d.set(showGain, forKey: "showGain") } }

    private init() {
        d.register(defaults: [
            "host": "127.0.0.1", "sendPort": 7001, "listenPort": 9001,
            "volumeKeys": true, "keyOutput": -1, "stepDb": 2.0, "maxDb": 0.0,
            "onlyWhenRMEIsOutput": true, "muteKey": "dim", "showHUD": true,
            "monoShortcut": true, "levelsWindow": false, "showGain": false,
        ])
        host = d.string(forKey: "host") ?? "127.0.0.1"
        sendPort = d.integer(forKey: "sendPort")
        listenPort = d.integer(forKey: "listenPort")
        shownOutputs = d.array(forKey: "shownOutputs") as? [Int] ?? []
        shownInputs = d.array(forKey: "shownInputs") as? [Int] ?? []
        outputLabels = d.dictionary(forKey: "outputLabels") as? [String: String] ?? [:]
        phantomLocked = d.array(forKey: "phantomLocked") as? [Int] ?? []
        volumeKeys = d.bool(forKey: "volumeKeys")
        keyOutput = d.integer(forKey: "keyOutput")
        stepDb = d.double(forKey: "stepDb")
        maxDb = d.double(forKey: "maxDb")
        onlyWhenRMEIsOutput = d.bool(forKey: "onlyWhenRMEIsOutput")
        muteKey = MuteKeyAction(rawValue: d.string(forKey: "muteKey") ?? "") ?? .dim
        showHUD = d.bool(forKey: "showHUD")
        monoShortcut = d.bool(forKey: "monoShortcut")
        levelsWindow = d.bool(forKey: "levelsWindow")
        showGain = d.bool(forKey: "showGain")
    }

    func label(for ch: Channel) -> String {
        if let l = outputLabels[String(ch.index)], !l.isEmpty { return l }
        return ch.displayName
    }

    /// Outputs for the popover: the chosen ones, or else TotalMix's Control
    /// Room Main and Phones outputs, or failing that the first output plus the
    /// first one named like headphones.
    func outputs(from mixer: Mixer) -> [Channel] {
        let visible = mixer.visible(.output)
        if !shownOutputs.isEmpty {
            return shownOutputs.compactMap { i in visible.first { $0.index == i } }
        }
        let controlRoom = ([mixer.mainOut] + mixer.phones).filter { $0 >= 0 }
        let assigned = controlRoom.compactMap { i in visible.first { $0.index == i } }
        if !assigned.isEmpty { return assigned }
        var picked: [Channel] = []
        if let first = visible.first { picked.append(first) }
        if let phones = visible.first(where: { $0.looksLikePhones && !picked.contains($0) }) { picked.append(phones) }
        return picked
    }

    /// Inputs for the popover: the chosen ones, or else up to four inputs that
    /// have 48V or Instrument switches (the mic and instrument inputs).
    func inputs(from mixer: Mixer) -> [Channel] {
        let visible = mixer.visible(.input)
        if !shownInputs.isEmpty {
            return shownInputs.compactMap { i in visible.first { $0.index == i } }
        }
        let preamps = visible.filter { $0.hasPhantom || $0.hasInstrument }
        return Array((preamps.isEmpty ? visible : preamps).prefix(4))
    }

    /// The output the volume keys control.
    func keyTarget(from mixer: Mixer) -> Channel? {
        if keyOutput >= 0, let ch = mixer.output(keyOutput), !ch.hidden { return ch }
        return outputs(from: mixer).first
    }
}
