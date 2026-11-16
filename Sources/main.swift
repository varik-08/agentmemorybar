import AppKit
import Foundation
import Darwin

final class MenuBarDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let headline = NSMenuItem(title: "Checking status…", action: nil, keyEquivalent: "")
    private let startup = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let checked = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var restartItem: NSMenuItem!
    private var viewerItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var snapshot: [String: Any] = [:]
    private var lastError: String?
    private var operation: String?
    private var refreshing = false
    private var refreshAgain = false
    private let worker = DispatchQueue(label: "local.agentmemorybar.control", qos: .utility)
    private var files: [DispatchSourceFileSystemObject] = []
    private var processes: [pid_t: DispatchSourceProcess] = [:]
    private var wakeObserver: NSObjectProtocol?
    private var instanceLock: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? Controller.prepare()
        instanceLock = open(Controller.service.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o600)
        if instanceLock < 0 || flock(instanceLock, LOCK_EX | LOCK_NB) != 0 {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        for item in [headline, startup, checked] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        startItem = add("Start agentmemory", #selector(startServer))
        stopItem = add("Stop agentmemory", #selector(stopServer))
        restartItem = add("Restart server", #selector(restartServer))
        menu.addItem(.separator())
        viewerItem = add("Open memory viewer", #selector(openViewer))
        refreshItem = add("Refresh status", #selector(refreshStatus))
        _ = add("Open logs…", #selector(showLogs))
        menu.addItem(.separator())
        settingsItem = add("Settings…", #selector(openSettings))
        loginItem = add("Launch app at login", #selector(toggleLogin))
        menu.addItem(.separator())
        let quit = add("Quit AgentMemoryBar", #selector(quitApp))
        quit.toolTip = "Сервер продолжит работу. Для остановки выберите «Stop agentmemory»."
        watchDirectory(Controller.root)
        watchDirectory(Controller.service)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        render()
        perform("login", title: "Starting…")
    }

    private func add(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func render() {
        let server = snapshot["server"] as? String
        let healthy = server == "healthy"
        let stopped = server == "unavailable"
        let busy = operation != nil
        let title: String
        let symbol: String
        let color: NSColor
        if let operation {
            title = operation
            symbol = "arrow.triangle.2.circlepath"
            color = .systemOrange
        } else if lastError != nil || (server != nil && !healthy && !stopped) {
            title = "Needs attention"
            symbol = "exclamationmark.triangle"
            color = .systemRed
        } else if healthy {
            title = "Server running"
            symbol = "memorychip.fill"
            color = .systemGreen
        } else if stopped {
            title = "Server stopped"
            symbol = "memorychip"
            color = .secondaryLabelColor
        } else {
            title = "Checking status…"
            symbol = "memorychip"
            color = .systemOrange
        }
        headline.title = "AgentMemoryBar — " + title
        startup.title = (snapshot["enabled"] as? Bool == true)
            ? "Start server when app opens: on" : "Start server when app opens: off"
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "AgentMemory")
            icon?.isTemplate = true
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(string: " ●", attributes: [
                .foregroundColor: color, .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ])
            button.toolTip = "AgentMemoryBar — " + title
            button.setAccessibilityLabel("AgentMemoryBar: " + title)
        }
        startItem.isEnabled = !busy && !healthy
        stopItem.isEnabled = !busy && (!stopped || snapshot["enabled"] as? Bool == true)
        restartItem.isEnabled = !busy && healthy
        viewerItem.isEnabled = !busy && healthy
        refreshItem.isEnabled = !busy
        loginItem.state = snapshot["app_login_enabled"] as? Bool == true ? .on : .off
        loginItem.isEnabled = !busy
        settingsItem.isEnabled = !busy
        headline.toolTip = lastError
    }

    private func apply(_ result: ControlResult) {
        if let state = result.snapshot { snapshot = state }
        lastError = result.error
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        checked.title = "Checked at " + formatter.string(from: Date())
        watchProcesses()
        render()
    }

    private func refresh() {
        if operation != nil || refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        worker.async { [weak self] in
            let result = Controller.run("status")
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                self.apply(result)
                if self.refreshAgain && self.operation == nil {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func perform(_ action: String, title: String) {
        guard operation == nil else { return }
        operation = title
        render()
        worker.async { [weak self] in
            let result = Controller.run(action)
            let finalState = result.snapshot == nil ? Controller.run("status") : result
            DispatchQueue.main.async {
                guard let self else { return }
                self.operation = nil
                self.apply(finalState)
                if let error = result.error {
                    self.lastError = error
                    self.render()
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Could not complete action"
                    alert.informativeText = String(error.prefix(800))
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func watchDirectory(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        files.append(source)
    }

    private func watchProcesses() {
        let path = Controller.root.appendingPathComponent("engine-state.json")
        let data = try? Data(contentsOf: path)
        let state = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let identifiers = Set(["composePid", "enginePid"].compactMap { key -> pid_t? in
            guard let number = state?[key] as? NSNumber, number.intValue > 1 else { return nil }
            return number.int32Value
        })
        for pid in Array(processes.keys) where !identifiers.contains(pid) {
            processes.removeValue(forKey: pid)?.cancel()
        }
        for pid in identifiers where processes[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in self?.refresh() }
            processes[pid] = source
            source.resume()
        }
    }

    @objc private func toggleLogin() {
        perform(snapshot["app_login_enabled"] as? Bool == true ? "login-off" : "login-on", title: "Updating login settings…")
    }

    @objc private func openSettings() {
        guard let config = try? Controller.settings() else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AgentMemoryBar Settings"
        alert.informativeText = "Leave executable and CLI empty for auto-detection. For nvm/fnm, enter the full Node.js path and agentmemory CLI .mjs path. Changes apply to the next start."
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 190))
        var fields: [NSTextField] = []
        for (index, entry) in [("Executable (node or agentmemory)", config.executable), ("CLI .mjs (only with node)", config.cliPath), ("agentmemory data directory", config.dataDirectory)].enumerated() {
            let y = CGFloat(150 - index * 55)
            let label = NSTextField(labelWithString: entry.0)
            label.frame = NSRect(x: 0, y: y + 24, width: 460, height: 20)
            let field = NSTextField(string: entry.1)
            field.frame = NSRect(x: 0, y: y, width: 460, height: 24)
            view.addSubview(label)
            view.addSubview(field)
            fields.append(field)
        }
        alert.accessoryView = view
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var updated = config
        updated.executable = fields[0].stringValue.trimmingCharacters(in: .whitespaces)
        updated.cliPath = fields[1].stringValue.trimmingCharacters(in: .whitespaces)
        updated.dataDirectory = fields[2].stringValue.trimmingCharacters(in: .whitespaces)
        do {
            guard updated.dataDirectory.hasPrefix("/"), updated.executable.isEmpty || updated.executable.hasPrefix("/"),
                  updated.cliPath.isEmpty || updated.cliPath.hasPrefix("/"),
                  updated.cliPath.isEmpty || !updated.executable.isEmpty else {
                throw BarError(message: "Use absolute paths. A CLI file requires a Node.js executable.")
            }
            // Changing the store while a server is alive would make ownership checks misleading.
            if snapshot["server"] as? String != "unavailable", updated.dataDirectory != config.dataDirectory {
                throw BarError(message: "Stop the server before changing its data directory.")
            }
            _ = try Controller.command(updated)
            try Controller.save(updated)
            refresh()
        } catch {
            let failure = NSAlert()
            failure.messageText = "Settings were not saved"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    @objc private func startServer() { perform("on", title: "Starting…") }
    @objc private func stopServer() { perform("off", title: "Stopping…") }
    @objc private func restartServer() { perform("restart", title: "Restarting…") }
    @objc private func refreshStatus() { refresh() }
    @objc private func openViewer() {
        NSWorkspace.shared.open(URL(string: "http://localhost:3113")!)
    }
    @objc private func showLogs() {
        NSWorkspace.shared.open(Controller.service)
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--control" {
    let result = Controller.run(CommandLine.arguments[2])
    var value = result.snapshot ?? [:]
    if let error = result.error { value["error"] = error }
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
    exit(result.error == nil ? 0 : 1)
}

let application = NSApplication.shared
let delegate = MenuBarDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
