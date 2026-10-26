import AppKit

/// Every failure a user can run into has a stable code, so it can be looked up
/// on the public error list (ERRORS.md) or pasted into an LLM. Add new codes
/// here and to ERRORS.md together, and never show a user an error without one.
/// Codes are never reused or renumbered.
enum ErrorCode: String, CaseIterable {
    // 1xx — updates
    case noUpdateSource = "MB-101"
    case badUpdateSource = "MB-102"
    case updateSourceUnreachable = "MB-103"
    case updateServerError = "MB-104"
    case updateInfoMalformed = "MB-105"
    case updateDownloadFailed = "MB-106"
    case updateUnpackFailed = "MB-107"
    case updateMissingApp = "MB-108"
    case updateWrongApp = "MB-109"
    case updateDamagedApp = "MB-110"
    case updateInstallerFailed = "MB-111"
    case updateSwapFailed = "MB-112"
    // 2xx — talking to TotalMix
    case socketFailed = "MB-201"
    case portInUse = "MB-202"
    case badHost = "MB-203"
    case noResponse = "MB-204"
    case legacyMode = "MB-205"
    // 3xx — volume keys and the Mono shortcut
    case accessibilityMissing = "MB-301"
    case eventTapFailed = "MB-302"
    case shortcutUnavailable = "MB-303"
    // 4xx — login item
    case loginItemFailed = "MB-401"
    // 6xx — reserved for the Install MixBar.command script (release.sh)
    // 9xx — anything not covered above
    case unexpected = "MB-999"

    var summary: String {
        switch self {
        case .noUpdateSource: return "No update source is set."
        case .badUpdateSource: return "The update source isn't a web link or a file path."
        case .updateSourceUnreachable: return "Couldn't reach the update source."
        case .updateServerError: return "The update server returned an error."
        case .updateInfoMalformed: return "The update information is damaged or in the wrong format."
        case .updateDownloadFailed: return "Couldn't download the update."
        case .updateUnpackFailed: return "Couldn't unpack the downloaded update."
        case .updateMissingApp: return "The downloaded update doesn't contain MixBar."
        case .updateWrongApp: return "The downloaded update is a different app."
        case .updateDamagedApp: return "The downloaded update is damaged."
        case .updateInstallerFailed: return "Couldn't start installing the update."
        case .updateSwapFailed: return "Installing the update failed, so the previous version was kept."
        case .socketFailed: return "Couldn't open a network socket to talk to TotalMix."
        case .portInUse: return "MixBar's OSC listening port is already in use by another app."
        case .badHost: return "The TotalMix host address isn't a valid IP address."
        case .noResponse: return "TotalMix isn't answering over OSC."
        case .legacyMode: return "TotalMix is answering in its old OSC mode, not Global OSC."
        case .accessibilityMissing: return "MixBar doesn't have Accessibility permission, so the volume keys still control macOS instead of TotalMix."
        case .eventTapFailed: return "Couldn't start listening for the volume keys."
        case .shortcutUnavailable: return "Couldn't set up the ⇧⌘M Mono shortcut."
        case .loginItemFailed: return "Couldn't change Open at Login."
        case .unexpected: return "Something unexpected went wrong."
        }
    }

    var hint: String {
        switch self {
        case .noUpdateSource, .badUpdateSource:
            return "Set one with “Update Source…” in the menu, or leave it empty to use the built-in source."
        case .updateSourceUnreachable:
            return "Check your internet connection and try again."
        case .updateServerError, .updateDownloadFailed:
            return "Try again in a few minutes. If it keeps happening, download the latest version from GitHub."
        case .updateInfoMalformed, .updateUnpackFailed, .updateMissingApp, .updateWrongApp, .updateDamagedApp:
            return "The published update is broken. Download the latest version from GitHub instead."
        case .updateInstallerFailed, .updateSwapFailed:
            return "Make sure MixBar is in ~/Applications and that the folder isn't locked, then try again."
        case .socketFailed:
            return "Quit and reopen MixBar. If it keeps happening, restart the Mac."
        case .portInUse:
            return "Another OSC app (a Stream Deck plugin, Companion, TouchOSC…) is listening on the same port. Give MixBar its own TotalMix remote: in MixBar's Settings pick another pair of ports (e.g. 7002/9002) and set the same ports on a second remote in TotalMix's OSC settings."
        case .badHost:
            return "Use 127.0.0.1 when TotalMix runs on this Mac, or the other computer's IP address (like 192.168.1.20)."
        case .noResponse:
            return "Make sure TotalMix FX is running, OSC is enabled (Options → Enable OSC Control), and the remote in Options → Settings → OSC uses the same host and ports as MixBar's Settings (default 127.0.0.1, port incoming 7001, outgoing 9001)."
        case .legacyMode:
            return "In TotalMix open Options → Settings → OSC and set Compatibility (Mode) to Global OSC. This needs TotalMix FX 2.1 or newer."
        case .accessibilityMissing:
            return "Turn MixBar on in System Settings → Privacy & Security → Accessibility. If it's already on, remove it with “−”, add it again, and relaunch MixBar."
        case .eventTapFailed:
            return "Quit and reopen MixBar. If it keeps happening, remove MixBar from Accessibility with “−”, add it again, and relaunch."
        case .shortcutUnavailable:
            return "Another app is probably using ⇧⌘M. Turn off the shortcut in MixBar's Settings, or quit the other app."
        case .loginItemFailed:
            return "You can add MixBar yourself in System Settings → General → Login Items."
        case .unexpected:
            return "Try again. If it keeps happening, copy the details and ask for help."
        }
    }
}

struct AppError: LocalizedError {
    let code: ErrorCode
    /// Technical specifics (paths, system error text). Never user content.
    let detail: String?

    init(_ code: ErrorCode, _ detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    init(wrapping error: Error, as code: ErrorCode = .unexpected) {
        if let e = error as? AppError { self = e } else { self.init(code, error.localizedDescription) }
    }

    var errorDescription: String? { "\(code.summary) (\(code.rawValue))" }
}

/// Logs every error to ~/Library/Application Support/MixBar/errors.log and
/// shows it to the user with its code: in an alert, or as a menu bar row for
/// background failures.
final class ErrorReporter {
    enum Surface {
        case alert     // shown right away
        case menu      // "⚠️ Problem MB-xxx" row in the menu bar dropdown
        case logOnly   // e.g. an automatic update check while offline
    }

    static let shared = ErrorReporter()
    /// The public error list. Both URLs work without a GitHub account; the raw
    /// one is plain text, which AI assistants read most reliably.
    static let helpURL = "https://github.com/jonpikereally/TotalMixMenuBar/blob/main/ERRORS.md"
    static let plainTextHelpURL = "https://raw.githubusercontent.com/jonpikereally/TotalMixMenuBar/main/ERRORS.md"

    /// Hover text for anything that shows an error.
    static let tooltip = "Look up this error code on the MixBar error list: \(helpURL)\n"
        + "You can also give that page and the copied error details to an AI assistant for help."

    /// Latest background problem waiting in the menu, if any.
    private(set) var pending: AppError?
    var onChange: () -> Void = {}
    private var lastLogged: [ErrorCode: Date] = [:]

    static let logURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MixBar", isDirectory: true)
            .appendingPathComponent("errors.log")
    }()

    func report(_ error: AppError, surface: Surface, title: String = "MixBar ran into a problem") {
        DispatchQueue.main.async {
            self.log(error)
            switch surface {
            case .alert:
                self.present(error, title: title)
            case .menu:
                self.pending = error
                self.onChange()
            case .logOnly:
                break
            }
        }
    }

    func clearPending() {
        pending = nil
        onChange()
    }

    /// Shows the error with its code. `actions` become extra buttons; returns
    /// the index of the action picked, or nil for OK.
    @discardableResult
    func present(_ error: AppError, title: String, actions: [String] = []) -> Int? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        var text = error.code.summary
        if let d = error.detail, !d.isEmpty { text += "\n\n\(d)" }
        text += "\n\n\(error.code.hint)\n\nError code: \(error.code.rawValue)"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        for a in actions { alert.addButton(withTitle: a) }
        alert.addButton(withTitle: "Copy Error Details")
        alert.addButton(withTitle: "Open Error List")
        Self.addTooltips(to: alert)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if response == actions.count + 1 {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Self.details(error), forType: .string)
            return nil
        }
        if response == actions.count + 2 {
            if let url = URL(string: Self.helpURL) { NSWorkspace.shared.open(url) }
            return nil
        }
        if response >= 1 && response <= actions.count { return response - 1 }
        return nil
    }

    /// Puts the error-list hover text on every piece of text in the alert,
    /// and on the alert itself for the space between them.
    static func addTooltips(to alert: NSAlert) {
        alert.layout()
        func walk(_ view: NSView) {
            if view is NSTextField { view.toolTip = tooltip }
            view.subviews.forEach(walk)
        }
        if let content = alert.window.contentView {
            content.toolTip = tooltip
            walk(content)
        }
    }

    /// Copyable report: everything needed to troubleshoot, nothing private.
    static func details(_ error: AppError) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        var lines = ["MixBar error \(error.code.rawValue): \(error.code.summary)"]
        if let d = error.detail, !d.isEmpty { lines.append("Details: \(d)") }
        lines.append("Suggested fix: \(error.code.hint)")
        lines.append("MixBar v\(AppVersion.version) (built \(AppVersion.built)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(arch)")
        lines.append("Time: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Error code list: \(helpURL)")
        lines.append("Plain-text error list for AI assistants: \(plainTextHelpURL)")
        return lines.joined(separator: "\n")
    }

    private func log(_ error: AppError) {
        // The same code repeating (e.g. a full disk failing every save) is
        // logged at most once a minute.
        let now = Date()
        if let last = lastLogged[error.code], now.timeIntervalSince(last) < 60 { return }
        lastLogged[error.code] = now

        let line = "\(ISO8601DateFormatter().string(from: now)) \(error.code.rawValue) v\(AppVersion.version) "
            + error.code.summary + (error.detail.map { " — \($0)" } ?? "") + "\n"
        let url = Self.logURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512 * 1024 {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
