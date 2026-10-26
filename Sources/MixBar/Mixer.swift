import Foundation
import Combine

enum Bus: String {
    case input, playback, output

    /// The short form used in /level/… and /mix/… paths.
    var levelSegment: String {
        switch self {
        case .input: return "in"
        case .playback: return "pb"
        case .output: return "out"
        }
    }
}

/// One TotalMix channel as Global OSC reports it. Indexes are zero-based, and
/// a stereo pair is addressed through its left channel.
struct Channel: Identifiable, Equatable {
    let bus: Bus
    let index: Int
    var name: String = ""
    var color: Int = -1          // 0 = hidden in TotalMix
    var stereo = false
    var mute = false
    var volume: Double = -65     // dB, outputs only
    var phantom = false
    var instrument = false
    var dynamics = false
    var eq = false
    /// Which paths TotalMix has reported, so buttons for options a channel
    /// doesn't have (48V on a line input, say) can be greyed out.
    var paths: Set<String> = []

    var id: String { "\(bus.rawValue)/\(index)" }
    var hidden: Bool { color == 0 }
    var hasPhantom: Bool { paths.contains("48v") }
    var hasInstrument: Bool { paths.contains("instrument") }
    var displayName: String { name.isEmpty ? "\(bus == .output ? "Out" : "In") \(index + 1)" : name }
    var looksLikePhones: Bool {
        let n = name.lowercased()
        return n.hasPrefix("ph") || n.contains("phone")
    }
}

/// Live mirror of TotalMix, kept in sync over Global OSC. TotalMix is the
/// authority: every local change is sent, then confirmed by its echo.
final class Mixer: ObservableObject {
    static let shared = Mixer()

    enum Link: Equatable {
        case starting
        case connected
        case legacyMode      // TotalMix answers, but in the pre-2.1 OSC mode
        case silent          // nothing heard from TotalMix
        case failed(AppError)

        static func == (a: Link, b: Link) -> Bool {
            switch (a, b) {
            case (.starting, .starting), (.connected, .connected), (.legacyMode, .legacyMode), (.silent, .silent): return true
            case (.failed(let x), .failed(let y)): return x.code == y.code
            default: return false
            }
        }
    }

    @Published private(set) var link: Link = .starting
    @Published private(set) var device = ""
    @Published private(set) var inputs: [Int: Channel] = [:]
    @Published private(set) var outputs: [Int: Channel] = [:]
    @Published private(set) var dim = false
    @Published private(set) var mono = false
    @Published private(set) var speakerB = false
    @Published private(set) var talkback = false
    /// Control Room assignments from TotalMix: Main Out, then Phones 1–4 (-1 = unassigned).
    @Published private(set) var mainOut = -1
    @Published private(set) var phones: [Int] = [-1, -1, -1, -1]

    /// Meter values in dBFS, by input index. Kept out of @Published so the
    /// popover doesn't redraw 20 times a second; the levels window polls it.
    private(set) var levels: [Int: Double] = [:]
    private(set) var outputLevels: [Int: Double] = [:]

    private let transport = OSCTransport()
    private var lastGlobalPacket = Date.distantPast
    private var lastLegacyPacket = Date.distantPast
    private var lastRequest = Date.distantPast
    private var watchdog: Timer?
    /// Paths we just changed locally, with the time. Echoes of older values
    /// arriving inside this window are ignored so sliders don't jump back.
    private var recentWrites: [String: Date] = [:]
    private let writeGuard: TimeInterval = 0.35

    // MARK: - Connection

    func connect() {
        let p = Prefs.shared
        transport.onMessages = { [weak self] messages in
            DispatchQueue.main.async { self?.handle(messages) }
        }
        do {
            try transport.open(host: p.host, sendPort: UInt16(clamping: p.sendPort), listenPort: UInt16(clamping: p.listenPort))
            link = .starting
            requestAll()
        } catch {
            let e = AppError(wrapping: error)
            link = .failed(e)
            ErrorReporter.shared.report(e, surface: .logOnly)
        }
        if watchdog == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            watchdog = t
        }
    }

    func reconnect() {
        transport.close()
        lastGlobalPacket = .distantPast
        lastLegacyPacket = .distantPast
        connect()
    }

    /// Asks TotalMix for its complete state.
    func requestAll() {
        lastRequest = Date()
        transport.send(OSCMessage(address: "/sendall", args: [.float(1)]))
    }

    private func tick() {
        if case .failed = link { return }
        let now = Date()
        let heardGlobal = now.timeIntervalSince(lastGlobalPacket) < 4
        let heardLegacy = now.timeIntervalSince(lastLegacyPacket) < 4
        let next: Link = heardGlobal ? .connected : heardLegacy ? .legacyMode : (link == .starting && now.timeIntervalSince(lastRequest) < 3 ? .starting : .silent)
        if next != link {
            if next == .connected { requestAll() }
            if next == .legacyMode { ErrorReporter.shared.report(AppError(.legacyMode), surface: .logOnly) }
            if next == .silent && link == .connected { ErrorReporter.shared.report(AppError(.noResponse), surface: .logOnly) }
            link = next
        }
        // Ask again while TotalMix is quiet (just launched, or "Send status" off).
        if !heardGlobal && now.timeIntervalSince(lastRequest) > 2 { requestAll() }
        else if heardGlobal && now.timeIntervalSince(lastGlobalPacket) > 1.5 && now.timeIntervalSince(lastRequest) > 2 {
            lastRequest = now
            transport.send(OSCMessage(address: "/sendstate", args: [.float(1)]))
        }
    }

    // MARK: - Incoming

    private func handle(_ messages: [OSCMessage]) {
        var touchedInputs = inputs
        var touchedOutputs = outputs
        var changedChannels = false
        let now = Date()

        for m in messages {
            let a = m.address
            if a.hasPrefix("/1/") || a.hasPrefix("/2/") || a.hasPrefix("/3/") || a.hasPrefix("/4/") || a == "/" {
                lastLegacyPacket = now
                continue
            }
            lastGlobalPacket = now

            if a.hasPrefix("/level/") {
                let parts = a.split(separator: "/")
                if parts.count == 3, let i = Int(parts[2]), let v = m.number {
                    if parts[1] == "in" { levels[i] = v } else if parts[1] == "out" { outputLevels[i] = v }
                }
                continue
            }
            if let r = recentWrites[a], now.timeIntervalSince(r) < writeGuard { continue }

            switch a {
            case "/status/device":
                // "Fireface UCX II (24129057)" — the serial number is noise in the header.
                if let s = m.text {
                    let name = s.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
                    if name != device { device = name }
                }
                continue
            case "/controlroom/mainout": if let v = m.number, Int(v) != mainOut { mainOut = Int(v) }; continue
            case "/controlroom/phones1", "/controlroom/phones2", "/controlroom/phones3", "/controlroom/phones4":
                if let v = m.number, let n = Int(String(a.last!)), phones[n - 1] != Int(v) { phones[n - 1] = Int(v) }
                continue
            case "/controlroom/dim": setIfChanged(\.dim, (m.number ?? 0) >= 0.5); continue
            case "/controlroom/mainmono": setIfChanged(\.mono, (m.number ?? 0) >= 0.5); continue
            case "/controlroom/speakerb": setIfChanged(\.speakerB, (m.number ?? 0) >= 0.5); continue
            case "/controlroom/talkback": setIfChanged(\.talkback, (m.number ?? 0) >= 0.5); continue
            default: break
            }

            // /input/3/48v, /output/0/volume, /input/2/eq/enable …
            let parts = a.split(separator: "/", maxSplits: 2).map(String.init)
            guard parts.count == 3, let bus = Bus(rawValue: parts[0]), bus != .playback,
                  let index = Int(parts[1]) else { continue }
            let path = parts[2]
            var ch = (bus == .input ? touchedInputs[index] : touchedOutputs[index]) ?? Channel(bus: bus, index: index)
            let before = ch
            ch.paths.insert(path)
            let on = (m.number ?? 0) >= 0.5
            switch path {
            case "name": if let s = m.text { ch.name = s }
            case "color": if let v = m.number { ch.color = Int(v) }
            case "stereo": ch.stereo = on
            case "mute": ch.mute = on
            case "volume": if let v = m.number { ch.volume = v }
            case "faderlin": if let v = m.number, !ch.paths.contains("volume") { ch.volume = FaderCurve.db(fromLinear: v) }
            case "48v": ch.phantom = on
            case "instrument": ch.instrument = on
            case "dynamics/enable": ch.dynamics = on
            case "eq/enable": ch.eq = on
            default: break
            }
            if ch != before {
                changedChannels = true
                if bus == .input { touchedInputs[index] = ch } else { touchedOutputs[index] = ch }
            }
        }
        if changedChannels {
            inputs = touchedInputs
            outputs = touchedOutputs
        }
    }

    private func setIfChanged(_ key: ReferenceWritableKeyPath<Mixer, Bool>, _ value: Bool) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    // MARK: - Lists for the UI

    /// Channels TotalMix shows, with the right half of each stereo pair folded
    /// into its left channel.
    func visible(_ bus: Bus) -> [Channel] {
        let all = (bus == .input ? inputs : outputs).values.sorted { $0.index < $1.index }
        var out: [Channel] = []
        var skip = Set<Int>()
        for ch in all where !skip.contains(ch.index) {
            if ch.stereo { skip.insert(ch.index + 1) }
            if !ch.hidden { out.append(ch) }
        }
        return out
    }

    func output(_ index: Int) -> Channel? { outputs[index] }
    func input(_ index: Int) -> Channel? { inputs[index] }

    // MARK: - Commands

    private func send(_ address: String, _ value: Float) {
        recentWrites[address] = Date()
        transport.send(OSCMessage(address: address, args: [.float(value)]))
    }

    func setVolume(output index: Int, db: Double) {
        let clamped = min(max(db, FaderCurve.minDb), min(FaderCurve.maxDb, Prefs.shared.maxDb))
        outputs[index]?.volume = clamped
        send("/output/\(index)/volume", Float(clamped))
    }

    /// Volume-key step. Returns the new level, or nil when the output is unknown.
    @discardableResult
    func nudge(output index: Int, by step: Double) -> Double? {
        guard let ch = outputs[index] else { return nil }
        var start = ch.volume
        if step > 0 && start <= FaderCurve.minDb { start = FaderCurve.minDb - 0.0001 }
        let next = (start + step).rounded(toPlaces: 1)
        setVolume(output: index, db: next)
        if ch.mute && step > 0 { setMute(output: index, false) }
        return outputs[index]?.volume
    }

    func setMute(output index: Int, _ on: Bool) {
        outputs[index]?.mute = on
        send("/output/\(index)/mute", on ? 1 : 0)
    }

    func setMute(input index: Int, _ on: Bool) {
        inputs[index]?.mute = on
        send("/input/\(index)/mute", on ? 1 : 0)
    }

    /// Input pairs that can be stereo linked: an odd/even pair (Analog 1+2,
    /// 3+4 …) whose channels TotalMix shows, by left index.
    func stereoPairs() -> [(left: Channel, right: Channel)] {
        inputs.keys.sorted().compactMap { i in
            guard i % 2 == 0, let l = inputs[i], let r = inputs[i + 1], !l.hidden, l.stereo || !r.hidden else { return nil }
            return (l, r)
        }
    }

    /// Why linking a pair is refused, or nil when it's fine. Linking copies the
    /// left input's settings, 48V included, onto the right one (seen live on a
    /// UCX II), so it must never carry 48V onto an input locked in Settings.
    func stereoLinkBlocked(left index: Int) -> String? {
        guard let l = inputs[index], let r = inputs[index + 1] else { return "TotalMix hasn't reported both channels yet." }
        let locked = Prefs.shared.phantomLocked
        if l.phantom != r.phantom && (locked.contains(index) || locked.contains(index + 1)) {
            return "48V is on for one of these inputs and locked for the other. Switch 48V off first."
        }
        return nil
    }

    func setStereo(input index: Int, _ on: Bool) {
        guard index % 2 == 0 else { return }
        if on && stereoLinkBlocked(left: index) != nil { return }
        inputs[index]?.stereo = on
        send("/input/\(index)/stereo", on ? 1 : 0)
        // TotalMix renames the pair ("Analog 1/2") and changes its routing;
        // fetch the new state once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.requestAll() }
    }

    /// 48V is locked for an input, or for its partner when the two are linked
    /// (they then share one switch).
    func phantomLocked(input index: Int) -> Bool {
        let locked = Prefs.shared.phantomLocked
        if locked.contains(index) { return true }
        return inputs[index]?.stereo == true && locked.contains(index + 1)
    }

    func setPhantom(input index: Int, _ on: Bool) {
        if on && phantomLocked(input: index) { return }
        inputs[index]?.phantom = on
        send("/input/\(index)/48v", on ? 1 : 0)
    }

    func setInstrument(input index: Int, _ on: Bool) {
        inputs[index]?.instrument = on
        send("/input/\(index)/instrument", on ? 1 : 0)
    }

    func setDynamics(_ bus: Bus, _ index: Int, _ on: Bool) {
        if bus == .input { inputs[index]?.dynamics = on } else { outputs[index]?.dynamics = on }
        send("/\(bus.rawValue)/\(index)/dynamics/enable", on ? 1 : 0)
    }

    func setEQ(_ bus: Bus, _ index: Int, _ on: Bool) {
        if bus == .input { inputs[index]?.eq = on } else { outputs[index]?.eq = on }
        send("/\(bus.rawValue)/\(index)/eq/enable", on ? 1 : 0)
    }

    func setDim(_ on: Bool) { dim = on; send("/controlroom/dim", on ? 1 : 0) }
    func setMono(_ on: Bool) { mono = on; send("/controlroom/mainmono", on ? 1 : 0) }
    func setSpeakerB(_ on: Bool) { speakerB = on; send("/controlroom/speakerb", on ? 1 : 0) }
    func setTalkback(_ on: Bool) { talkback = on; send("/controlroom/talkback", on ? 1 : 0) }
}

/// TotalMix's 1023-step fader curve (from RME's OSC table), for the rare case
/// TotalMix sends only linear fader positions.
enum FaderCurve {
    static let minDb = -65.0
    static let maxDb = 6.0

    static func db(fromLinear value: Double) -> Double {
        let p = min(max(value, 0), 1) * 1023
        if p >= 649 { return p * 0.0320855615 - 26.8235294118 }
        return p * p * (-1 / 11033) + p * 0.1497326203 - 65
    }

    /// Fader position 0…1 for a dB value; sliders use it so they move like TotalMix's.
    static func linear(fromDb db: Double) -> Double {
        if db <= minDb { return 0 }
        if db >= maxDb { return 1 }
        let p = db >= -6 ? (db + 26.8235294118) / 0.0320855615 : 826 - (-34869 - 11033 * db).squareRoot()
        return min(max(p / 1023, 0), 1)
    }

    static func format(_ db: Double) -> String {
        db <= minDb ? "−∞ dB" : String(format: "%.1f dB", db).replacingOccurrences(of: "-", with: "−")
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10, Double(places))
        return (self * m).rounded() / m
    }
}
