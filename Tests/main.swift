import Foundation

// Drives Mixer against Tests/fake_totalmix.py. Run with ./test.sh.
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}
func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

// Codec round trip, including strings that need padding.
let m = OSCMessage(address: "/input/12/name", args: [.string("Mic 1"), .float(-3.5), .int(7), .bool(true)])
let back = OSCMessage.decode(m.encoded()).first
check(back?.address == "/input/12/name" && back?.args == m.args, "OSC message round trip")

check(abs(FaderCurve.db(fromLinear: FaderCurve.linear(fromDb: -25.1)) + 25.1) < 0.05, "fader curve inverse at -25.1 dB")
check(abs(FaderCurve.db(fromLinear: FaderCurve.linear(fromDb: 3)) - 3) < 0.05, "fader curve inverse at +3 dB")
check(FaderCurve.linear(fromDb: -80) == 0 && FaderCurve.linear(fromDb: 10) == 1, "fader curve clamps")

let prefs = Prefs.shared
prefs.host = "127.0.0.1"
prefs.sendPort = Int(CommandLine.arguments[1])!
prefs.listenPort = Int(CommandLine.arguments[2])!
prefs.shownOutputs = []
prefs.shownInputs = []
prefs.keyOutput = -1
prefs.maxDb = 0

let mixer = Mixer.shared
mixer.connect()
spin(2.5)
check(mixer.link == .connected, "connects and sees Global OSC traffic")
check(mixer.device == "Fireface UCX II", "reads the device name")
check(mixer.visible(.output).map(\.index) == [0, 6], "folds stereo pairs and hides colour-0 outputs")
check(mixer.mainOut == 0 && mixer.phones == [6, -1, -1, -1], "reads Control Room assignments")
check(prefs.outputs(from: mixer).map(\.index) == [0, 6], "default outputs are Control Room Main plus Phones")
check(prefs.keyTarget(from: mixer)?.index == 0, "volume keys default to the first output")
check(mixer.output(0)?.volume == Double(Float(-25.1)), "reads output volume in dB")
check(mixer.output(0)?.eq == true, "reads output EQ state")
check(mixer.input(0)?.phantom == true && mixer.input(1)?.instrument == true, "reads 48V and Instrument")
check(prefs.inputs(from: mixer).map(\.index) == [0, 1], "default inputs are the ones with preamp switches")
check(mixer.input(2)?.hasPhantom == false, "line input has no 48V")
check(mixer.mono && !mixer.dim, "reads Control Room state")
check(mixer.levels[0] == -12.5, "reads input levels")

mixer.nudge(output: 0, by: 2)
check(abs((mixer.output(0)?.volume ?? 0) + 23.1) < 0.01, "volume up by 2 dB")
mixer.setVolume(output: 0, db: 4)
check(mixer.output(0)?.volume == 0, "never louder than the ceiling")
mixer.setPhantom(input: 1, true)
mixer.setDim(true)
spin(1)
check(mixer.input(1)?.phantom == true && mixer.dim, "local changes survive the echo")

// 48V lock: never switches on, still switches off.
prefs.phantomLocked = [1]
mixer.setPhantom(input: 1, false)
spin(0.5)
check(mixer.input(1)?.phantom == false, "locked input can still turn 48V off")
mixer.setPhantom(input: 1, true)
spin(0.5)
check(mixer.input(1)?.phantom == false, "locked input refuses 48V on")
prefs.phantomLocked = []

// Stereo linking.
check(mixer.stereoPairs().map(\.left.index) == [0], "Mic 1 + Mic 2 is a linkable pair, Line 3 has no partner")
mixer.setStereo(input: 0, true)
spin(1.2)
check(mixer.input(0)?.stereo == true && mixer.visible(.input).map(\.index) == [0, 2], "linking folds Mic 2 into Mic 1")
mixer.setStereo(input: 0, false)
spin(1.2)
check(mixer.input(0)?.stereo == false && mixer.visible(.input).map(\.index) == [0, 1, 2], "unlinking brings Mic 2 back")
// Mic 1 has 48V on; lock Mic 2: linking would carry 48V onto it.
mixer.setPhantom(input: 0, true)
prefs.phantomLocked = [1]
check(mixer.stereoLinkBlocked(left: 0) != nil, "linking refused when it would carry 48V onto a locked input")
mixer.setStereo(input: 0, true)
check(mixer.input(0)?.stereo == false, "blocked link isn't sent")
prefs.phantomLocked = []

// Gain.
check(mixer.input(0)?.gain == 65, "reads input gain")
let mic = GainRanges.range(device: mixer.device, input: mixer.input(0)!)
let line = GainRanges.range(device: mixer.device, input: mixer.input(2)!)
check(mic == GainRange(min: 0, max: 75, step: 1), "UCX II mic gain is 0 to 75 dB")
check(line == GainRange(min: 0, max: 24, step: 0.5), "UCX II line gain is 0 to 24 dB in half steps")
check(GainRanges.range(device: "Fireface UCX (123)", input: mixer.input(0)!)?.max == 65, "UCX (not II) mic gain tops out at 65 dB")
check(mixer.setGain(input: 2, db: 30) == 24, "gain clamps to the range")
check(mixer.setGain(input: 2, db: 3.3) == 3.5, "gain snaps to the step")
check(mixer.setGain(input: 3, db: 5) == nil, "no gain on an input that doesn't report one")
spin(0.5)
check(mixer.input(2)?.gain == 3.5, "gain change survives the echo")

if failures == 0 { print("All tests passed") } else { print("\(failures) failed"); exit(1) }
