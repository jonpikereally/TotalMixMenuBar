import Foundation

/// Input gain ranges per interface. TotalMix's Global OSC reports the gain
/// value but not its range, so these come from bitfocus/companion-module-rme-totalmix
/// (only the UCX II has been checked against a real interface; its line
/// inputs go higher than that module says). Indexes are zero-based inputs.
struct GainRange: Equatable {
    let min: Double
    let max: Double
    let step: Double

    func clamp(_ db: Double) -> Double {
        let snapped = (db / step).rounded() * step
        return Swift.min(Swift.max(snapped, min), max)
    }
}

enum GainRanges {
    private struct Model {
        let name: String
        let ranges: [Int: GainRange]
        /// Narrower range some mic/instrument inputs switch to in Instrument mode.
        var instrument: [Int: GainRange] = [:]
    }

    private static func r(_ indices: [Int], _ min: Double, _ max: Double, step: Double = 1) -> [Int: GainRange] {
        Dictionary(uniqueKeysWithValues: indices.map { ($0, GainRange(min: min, max: max, step: step)) })
    }

    private static let models: [Model] = [
        // Line inputs measured on a real UCX II: TotalMix caps them at +24 dB, in 0.5 dB steps.
        Model(name: "Fireface UCX II", ranges: r([0, 1], 0, 75).merging(r(Array(2...7), 0, 24, step: 0.5)) { a, _ in a }),
        Model(name: "Fireface UCX", ranges: r([0, 1], 0, 65).merging(r([2, 3], 0, 12, step: 0.5)) { a, _ in a }),
        Model(name: "Fireface UC", ranges: r([0, 1], 0, 65).merging(r([2, 3], 0, 18, step: 0.5)) { a, _ in a }),
        Model(name: "Fireface UFX III", ranges: r(Array(0...7), 0, 12, step: 0.5).merging(r(Array(8...11), 0, 75)) { a, _ in a },
              instrument: r(Array(8...11), 8, 50)),
        Model(name: "Fireface UFX II", ranges: r(Array(0...7), 0, 12, step: 0.5).merging(r(Array(8...11), 0, 75)) { a, _ in a },
              instrument: r(Array(8...11), 8, 50)),
        Model(name: "Fireface UFX", ranges: r(Array(8...11), 0, 65), instrument: r(Array(8...11), 10, 65)),
        Model(name: "Fireface 802", ranges: r(Array(0...7), 0, 12, step: 0.5).merging(r(Array(8...11), 6, 60)) { a, _ in a }),
        Model(name: "Babyface Pro", ranges: r([0, 1], -11, 65).merging(r([2, 3], 0, 9, step: 0.5)) { a, _ in a }),
        Model(name: "Babyface", ranges: r([0, 1], 9, 60)),
        Model(name: "Digiface AES", ranges: r([4, 5], 0, 75)),
    ]

    /// The range for an input, or nil when it has no adjustable gain.
    /// `device` is TotalMix's /status/device name; longer names are matched
    /// first so "Fireface UCX II" doesn't fall into "Fireface UCX".
    static func range(device: String, input ch: Channel) -> GainRange? {
        guard ch.paths.contains("gain") else { return nil }
        let model = models.sorted { $0.name.count > $1.name.count }.first { device.hasPrefix($0.name) }
        if let model {
            if ch.instrument, let r = model.instrument[ch.index] { return r }
            return model.ranges[ch.index]
        }
        // Unknown interface: a typical mic preamp, or a typical line input.
        return ch.hasPhantom ? GainRange(min: 0, max: 65, step: 1) : GainRange(min: 0, max: 12, step: 0.5)
    }
}
