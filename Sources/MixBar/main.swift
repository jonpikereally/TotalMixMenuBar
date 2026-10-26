import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var updateMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var levelsMenuItem: NSMenuItem!
    private var problemMenuItem: NSMenuItem!
    private let hotKey = HotKeyManager()
    private var hotKeyError: AppError?
    private var tapError: AppError?
    private var bag = Set<AnyCancellable>()

    private let mixer = Mixer.shared
    private let prefs = Prefs.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "MixBar")
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let host = NSHostingController(rootView: ContentView(actions: MenuActions(
            openSettings: { [weak self] in self?.openSettings() },
            showMenu: { [weak self] view in self?.popMenu(from: view) },
            toggleLevels: { [weak self] in self?.toggleLevels() })))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)

        buildMenu()
        ErrorReporter.shared.onChange = { [weak self] in self?.refreshProblemItem() }
        Updater.shared.onChange = { [weak self] in self?.refreshUpdateItem() }
        Updater.shared.startAutomaticChecks()
        reportFailedUpdateIfAny()

        LevelsWindow.shared.onClose = { [weak self] in self?.prefs.levelsWindow = false }
        if prefs.levelsWindow { LevelsWindow.shared.show() }

        setUpKeys()
        mixer.connect()

        // Keep the banner, the icon and the shortcut in step with the state.
        mixer.$link.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshStatus() } }.store(in: &bag)
        prefs.$volumeKeys.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshKeys() } }.store(in: &bag)
        prefs.$monoShortcut.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshShortcut() } }.store(in: &bag)
        // Accessibility can be granted at any moment in System Settings.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshKeys() }
    }

    // MARK: - Status item

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popMenu(from: nil)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func popMenu(from view: NSView?) {
        menuNeedsUpdate(menu)
        if let view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        } else if let button = statusItem.button {
            popover.performClose(nil)
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func refreshIcon() {
        let name = Updater.shared.available != nil ? "arrow.up.circle.fill" : "slider.vertical.3"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "MixBar")
        statusItem.button?.appearsDisabled = mixer.link != .connected
    }

    // MARK: - Menu

    private func buildMenu() {
        problemMenuItem = NSMenuItem(title: "", action: #selector(showPendingProblem), keyEquivalent: "")
        problemMenuItem.target = self
        problemMenuItem.isHidden = true
        menu.addItem(problemMenuItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        levelsMenuItem = NSMenuItem(title: "Levels Window", action: #selector(toggleLevels), keyEquivalent: "")
        levelsMenuItem.target = self
        menu.addItem(levelsMenuItem)

        loginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())

        updateMenuItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)

        let source = NSMenuItem(title: "Update Source…", action: #selector(editUpdateSource), keyEquivalent: "")
        source.target = self
        menu.addItem(source)

        let github = NSMenuItem(title: "MixBar on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        github.target = self
        menu.addItem(github)

        let version = NSMenuItem(title: "Version \(AppVersion.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit MixBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        menu.autoenablesItems = false
        for item in menu.items where item.action != nil { item.isEnabled = true }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        levelsMenuItem.state = prefs.levelsWindow ? .on : .off
        refreshProblemItem()
    }

    @objc private func openSettings() {
        popover.performClose(nil)
        SettingsWindow.shared.show()
    }

    @objc private func toggleLevels() {
        prefs.levelsWindow.toggle()
        if prefs.levelsWindow { LevelsWindow.shared.show() } else { LevelsWindow.shared.hide() }
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            ErrorReporter.shared.report(AppError(.loginItemFailed, error.localizedDescription),
                                        surface: .alert, title: "Couldn't change Open at Login")
        }
        loginMenuItem.state = service.status == .enabled ? .on : .off
    }

    // MARK: - Volume keys and the Mono shortcut

    private func setUpKeys() {
        let keys = MediaKeys.shared
        keys.shouldHandle = { [weak self] in
            guard let self, self.prefs.volumeKeys, self.mixer.link == .connected,
                  self.prefs.keyTarget(from: self.mixer) != nil else { return false }
            return !self.prefs.onlyWhenRMEIsOutput || SoundOutput.isRME
        }
        keys.onKey = { [weak self] key, fine in self?.handleKey(key, fine: fine) ?? false }
        hotKey.onPress = { [weak self] in
            guard let self, self.mixer.link == .connected else { return }
            self.mixer.setMono(!self.mixer.mono)
        }
    }

    private func handleKey(_ key: MediaKeys.Key, fine: Bool) -> Bool {
        guard let target = prefs.keyTarget(from: mixer) else { return false }
        let step = fine ? prefs.stepDb / 4 : prefs.stepDb
        switch key {
        case .up: mixer.nudge(output: target.index, by: step)
        case .down: mixer.nudge(output: target.index, by: -step)
        case .mute:
            if prefs.muteKey == .dim { mixer.setDim(!mixer.dim) } else { mixer.setMute(output: target.index, !target.mute) }
        }
        if prefs.showHUD, let ch = mixer.output(target.index) {
            HUD.shared.show(name: prefs.label(for: ch), icon: ch.looksLikePhones ? "headphones" : "hifispeaker.fill",
                            db: ch.volume, muted: ch.mute, dimmed: mixer.dim)
        }
        return true
    }

    private func refreshKeys() {
        let keys = MediaKeys.shared
        if prefs.volumeKeys {
            if !keys.running {
                do {
                    try keys.start()
                    tapError = nil
                } catch {
                    let e = AppError(wrapping: error)
                    if tapError?.code != e.code { ErrorReporter.shared.report(e, surface: .logOnly) }
                    tapError = e
                }
            }
        } else {
            keys.stop()
            tapError = nil
        }
        refreshStatus()
    }

    private func refreshShortcut() {
        hotKeyError = nil
        if prefs.monoShortcut {
            if let failure = hotKey.register() {
                hotKeyError = AppError(.shortcutUnavailable, failure)
                ErrorReporter.shared.report(hotKeyError!, surface: .logOnly)
            }
        } else {
            hotKey.unregister()
        }
        refreshStatus()
    }

    /// The popover's banner shows the most useful problem, if there is one.
    private func refreshStatus() {
        refreshIcon()
        let banner: AppStatus.Banner?
        switch mixer.link {
        case .legacyMode:
            banner = .init(error: AppError(.legacyMode), action: nil)
        case .silent:
            banner = .init(error: AppError(.noResponse, "Sending to \(prefs.host):\(prefs.sendPort), listening on port \(prefs.listenPort)"),
                           action: ("Settings…", { [weak self] in self?.openSettings() }))
        case .failed(let e):
            banner = .init(error: e, action: ("Settings…", { [weak self] in self?.openSettings() }))
        case .starting, .connected:
            if let e = tapError {
                banner = .init(error: e, action: e.code == .accessibilityMissing
                               ? ("Grant…", { MediaKeys.promptForAccessibility(); MediaKeys.openAccessibilitySettings() })
                               : nil)
            } else if let e = hotKeyError {
                banner = .init(error: e, action: nil)
            } else {
                banner = nil
            }
        }
        let status = AppStatus.shared
        if status.banner?.error.code != banner?.error.code || status.banner?.error.detail != banner?.error.detail {
            status.banner = banner
        }
    }

    // MARK: - Updates

    private func refreshUpdateItem() {
        if let m = Updater.shared.available {
            updateMenuItem.title = "⬆︎ Install Update to v\(m.version)…"
        } else {
            updateMenuItem.title = "Check for Updates…"
        }
        refreshIcon()
    }

    @objc private func checkForUpdates() {
        if let m = Updater.shared.available {
            offerInstall(m)
            return
        }
        updateMenuItem.title = "Checking for Updates…"
        Updater.shared.check { [weak self] result in
            guard let self else { return }
            self.refreshUpdateItem()
            switch result {
            case .success(let m?):
                self.offerInstall(m)
            case .success(nil):
                let alert = NSAlert()
                alert.messageText = "MixBar is up to date"
                alert.informativeText = "You're running v\(AppVersion.version), the newest version available."
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            case .failure(let error):
                self.showUpdateError(error)
            }
        }
    }

    private func offerInstall(_ m: UpdateManifest) {
        let alert = NSAlert()
        alert.messageText = "Update to MixBar v\(m.version)?"
        var info = "You have v\(AppVersion.version)."
        if let notes = m.notes, !notes.isEmpty { info += "\n\nWhat's new:\n\(notes)" }
        info += "\n\nMixBar will quit, update itself and reopen. Your settings are kept."
            + "\n\nAfterwards macOS will ask you to turn Accessibility back on for MixBar "
            + "(it asks after every update). Until you do, the volume keys control macOS instead of TotalMix."
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        updateMenuItem.title = "Installing Update…"
        updateMenuItem.isEnabled = false
        Updater.shared.install(m) { [weak self] error in
            self?.updateMenuItem.isEnabled = true
            self?.refreshUpdateItem()
            self?.showUpdateError(error)
        }
    }

    private func showUpdateError(_ error: Error) {
        let e = AppError(wrapping: error)
        let sourceProblem = e.code == .noUpdateSource || e.code == .badUpdateSource
        let picked = ErrorReporter.shared.present(e, title: "Couldn't update MixBar",
                                                  actions: sourceProblem ? ["Set Update Source…"] : [])
        if picked == 0 { editUpdateSource() }
    }

    /// The swap script leaves a coded marker when installing an update fails
    /// and it has put the previous version back.
    private func reportFailedUpdateIfAny() {
        let marker = Updater.swapFailureMarker
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: marker)
        let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
        let code = parts.first.flatMap { ErrorCode(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? .updateSwapFailed
        ErrorReporter.shared.report(AppError(code, parts.count > 1 ? parts[1] : nil),
                                    surface: .alert, title: "Couldn't install the update")
    }

    private func refreshProblemItem() {
        if let p = ErrorReporter.shared.pending {
            problemMenuItem.title = "⚠️ Problem \(p.code.rawValue) — click for details"
            problemMenuItem.toolTip = ErrorReporter.tooltip
            problemMenuItem.isHidden = false
        } else {
            problemMenuItem.isHidden = true
        }
    }

    @objc private func showPendingProblem() {
        guard let p = ErrorReporter.shared.pending else { return }
        ErrorReporter.shared.clearPending()
        ErrorReporter.shared.present(p, title: "MixBar ran into a problem")
    }

    @objc private func editUpdateSource() {
        let alert = NSAlert()
        alert.messageText = "Update Source"
        alert.informativeText = "Where MixBar looks for new versions: a web link or a file path to a latest.json feed. "
            + "Leave it empty to use the built-in source"
            + (AppVersion.updateFeed.isEmpty ? " (none in this build)." : ":\n\(AppVersion.updateFeed)")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: "updateFeed") ?? ""
        field.placeholderString = AppVersion.updateFeed.isEmpty ? "https://…/latest.json" : AppVersion.updateFeed
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && Updater.url(from: value) == nil {
            showUpdateError(AppError(.badUpdateSource, value))
            return
        }
        Updater.shared.feed = value
        Updater.shared.check { _ in }
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/jonpikereally/TotalMixMenuBar") { NSWorkspace.shared.open(url) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
