import AppKit
import UserNotifications
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    static let interval: TimeInterval = 20 * 60
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let reminderID = "position-reminder"
    private let testID = "test-reminder"
    private var testIDs: Set<String> = ["test-reminder"]
    private var testTask: Task<Void, Never>?
    private var statusItem: NSStatusItem!
    private let status = NSMenuItem(title: "Préparation…", action: nil, keyEquivalent: "")
    private var pauseItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var authorized = false
    private var sleeping = false
    private var exiting = false
    private var readyToQuit = false
    private var revision = 0
    private var reconciliation: Task<Void, Never>?
    private var firstReminder: Date?
    private var lastError: String?
    private var authorizationTimer: Timer?
    private let notificationGuide = NotificationGuide()
    private var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }
    private var soundEnabled: Bool {
        get { defaults.object(forKey: "soundEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        center.delegate = self
        let moved = UNNotificationAction(identifier: "moved", title: "J’ai bougé", options: [])
        let pause = UNNotificationAction(identifier: "pause", title: "Mettre en pause", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "position",
            actions: [moved, pause], intentIdentifiers: [], options: [])])
        buildMenu()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        Task {
            await requestAuthorization()
            if !exiting && defaults.integer(forKey: "notificationGuideVersion") < NotificationGuide.version {
                defaults.set(NotificationGuide.version, forKey: "notificationGuideVersion")
                notificationGuide.show()
            }
        }
    }

    private func requestAuthorization() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            // Some macOS versions return an error while the permission banner
            // is still awaiting the user's answer. Re-read the actual settings.
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await refreshAuthorization()
        if !authorized {
            authorizationTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.refreshAuthorization() }
            }
            authorizationTimer?.tolerance = 1
        }
    }

    private func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized
        if allowed {
            authorizationTimer?.invalidate()
            authorizationTimer = nil
        }
        if authorized != allowed {
            authorized = allowed
            reschedule()
        }
        refreshMenu()
    }

    // These local commands can also be used by Apple Shortcuts' Open URLs action.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "bouge" {
            Task {
                await refreshAuthorization()
                switch url.host {
                case "test": testNotification()
                case "help": showNotificationGuide()
                case "pause":
                    if !paused { togglePause() }
                case "resume":
                    if paused { togglePause() }
                case "reset": restart()
                case "quit": quit()
                default: break
                }
            }
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Bouge")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Bouge — changer de position toutes les 20 minutes"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        add("J’ai bougé — repartir sur 20 min", #selector(restart), to: menu)
        pauseItem = add("Mettre en pause", #selector(togglePause), to: menu)
        add("Tester la notification", #selector(testNotification), to: menu)
        menu.addItem(.separator())
        soundItem = add("Son des notifications", #selector(toggleSound), to: menu)
        loginItem = add("Ouvrir à la connexion", #selector(toggleLogin), to: menu)
        add("Réglages des notifications…", #selector(openNotificationSettings), to: menu)
        add("Notifications et Concentration…", #selector(showNotificationGuide), to: menu)
        menu.addItem(.separator())
        add("À propos de Bouge…", #selector(about), to: menu)
        let quit = add("Quitter Bouge", #selector(quit), to: menu)
        quit.keyEquivalent = "q"
        statusItem.menu = menu
        refreshMenu()
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
        Task {
            let settings = await center.notificationSettings()
            let allowed = settings.authorizationStatus == .authorized
            if authorized != allowed {
                authorized = allowed
                reschedule()
            }
            refreshMenu()
        }
    }

    private func refreshMenu() {
        if let lastError {
            status.title = "Erreur : \(lastError)"
        } else if !authorized {
            status.title = "Notifications non autorisées — voir les réglages"
        } else if paused {
            status.title = "Rappels en pause"
        } else if let firstReminder {
            let elapsed = Date().timeIntervalSince(firstReminder)
            let remaining = elapsed < 0 ? -elapsed : Self.interval - elapsed.truncatingRemainder(dividingBy: Self.interval)
            status.title = "Prochain rappel dans \(max(1, Int(ceil(remaining / 60)))) min · toutes les 20 min"
        } else {
            status.title = "Programmation du rappel…"
        }
        pauseItem.title = paused ? "Reprendre les rappels" : "Mettre en pause"
        soundItem.state = soundEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        statusItem.button?.appearsDisabled = paused
    }

    private func content(test: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = test ? "Bouge — notification de test" : "Il est temps de changer de position"
        content.body = "Bouge un peu sur ta chaise et change de position, comme conseillé par ton kiné."
        content.categoryIdentifier = "position"
        if soundEnabled { content.sound = .default }
        return content
    }

    // Serialize writes to the same request ID. Rapid pause/resume clicks must not
    // allow an older asynchronous add to recreate a cancelled reminder.
    private func reschedule() {
        revision += 1
        lastError = nil
        firstReminder = nil
        refreshMenu()
        guard reconciliation == nil else { return }
        reconciliation = Task {
            var processed: Int
            repeat {
                processed = revision
                center.removePendingNotificationRequests(withIdentifiers: [reminderID])
                center.removeDeliveredNotifications(withIdentifiers: [reminderID])
                if authorized && !paused && !sleeping && !exiting {
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.interval, repeats: true)
                    let nextDate = trigger.nextTriggerDate()
                    do {
                        try await center.add(UNNotificationRequest(identifier: reminderID,
                            content: content(), trigger: trigger))
                        if processed == revision { firstReminder = nextDate }
                    } catch {
                        if processed == revision { report(error) }
                    }
                }
            } while processed != revision
            reconciliation = nil
            refreshMenu()
        }
    }

    @objc private func restart() {
        paused = false
        center.removeDeliveredNotifications(withIdentifiers: [reminderID] + Array(testIDs))
        reschedule()
    }

    @objc private func togglePause() {
        paused.toggle()
        cancelTestNotification()
        reschedule()
    }

    @objc private func toggleSound() {
        soundEnabled.toggle()
        reschedule()
    }

    @objc private func testNotification() {
        guard !exiting && !sleeping else { return }
        let previousTask = testTask
        previousTask?.cancel()
        testTask = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized else {
                showAlert("Autorise les notifications de Bouge", "Dans Réglages Système → Notifications → Bouge, active « Autoriser les notifications ». Puis clique à nouveau sur « Tester la notification ».")
                return
            }
            do {
                let pending = await center.pendingNotificationRequests()
                let delivered = await center.deliveredNotifications()
                guard !Task.isCancelled else { return }
                testIDs.formUnion(pending.map(\.identifier).filter { $0.hasPrefix(testID) })
                testIDs.formUnion(delivered.map { $0.request.identifier }.filter { $0.hasPrefix(testID) })
                center.removePendingNotificationRequests(withIdentifiers: Array(testIDs))
                center.removeDeliveredNotifications(withIdentifiers: Array(testIDs))
                // A reused ID can update an old notification without a new
                // macOS banner. Each explicit test must be a fresh notification.
                let identifier = "\(testID)-\(UUID().uuidString)"
                testIDs.insert(identifier)
                try await center.add(UNNotificationRequest(identifier: identifier,
                    content: content(test: true),
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
                if Task.isCancelled {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                }
            } catch {
                if !Task.isCancelled { report(error) }
            }
        }
    }

    private func cancelTestNotification() {
        testTask?.cancel()
        center.removePendingNotificationRequests(withIdentifiers: Array(testIDs))
    }

    @objc private func toggleLogin() {
        Task {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try await SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            } catch {
                showAlert("Ouverture à la connexion indisponible", "\(error.localizedDescription)\n\nPlace Bouge.app dans Applications, puis ajoute-la dans Réglages Système → Général → Ouverture et extensions → Ouvrir à la connexion.")
            }
            refreshMenu()
        }
    }

    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showNotificationGuide() {
        notificationGuide.show()
    }

    @objc private func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
        showAlert("Bouge", "Un petit rappel pour changer de position toutes les 20 minutes.\n\n« J’ai bougé » relance un cycle de 20 minutes. La pause dure jusqu’à la reprise. Au réveil du Mac, un nouveau cycle commence. Quitter arrête les rappels.\n\nSwift + AppKit · Apple Silicon natif\nVersion \(version) · Gratuit · Aucun compte ni connexion réseau")
    }

    @objc private func willSleep() {
        sleeping = true
        cancelTestNotification()
        reschedule()
    }

    @objc private func didWake() {
        sleeping = false
        reschedule()
    }

    @objc private func quit() {
        guard !exiting else { return }
        exiting = true
        authorizationTimer?.invalidate()
        cancelTestNotification()
        reschedule()
        Task {
            await reconciliation?.value
            await testTask?.value
            center.removePendingNotificationRequests(withIdentifiers: [reminderID] + Array(testIDs))
            center.removeDeliveredNotifications(withIdentifiers: [reminderID] + Array(testIDs))
            // Await a read on the same connection so cancellation reaches
            // usernoted before the process exits.
            _ = await center.pendingNotificationRequests()
            _ = await center.deliveredNotifications()
            readyToQuit = true
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if readyToQuit { return .terminateNow }
        // Keep the normal event loop alive while Swift's async cleanup runs.
        quit()
        return .terminateCancel
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Even though the menu-bar app is running, show the normal macOS banner.
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            if action == "moved" { self.restart() }
            if action == "pause" {
                self.paused = true
                self.cancelTestNotification()
                self.reschedule()
            }
        }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        refreshMenu()
        showAlert("Impossible de programmer le rappel", error.localizedDescription)
    }

    private func showAlert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@main
struct Bouge {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--diagnostics") {
            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                let pending = await center.pendingNotificationRequests()
                let delivered = await center.deliveredNotifications()
                let data: [String: Any] = [
                    "authorization": settings.authorizationStatus.rawValue,
                    "alertSetting": settings.alertSetting.rawValue,
                    "soundSetting": settings.soundSetting.rawValue,
                    "paused": UserDefaults.standard.bool(forKey: "paused"),
                    "pending": pending.map { request -> [String: Any] in
                        let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
                        return ["id": request.identifier,
                            "interval": trigger?.timeInterval ?? 0,
                            "repeats": trigger?.repeats ?? false,
                            "sound": request.content.sound != nil]
                    },
                    "delivered": delivered.map { ["id": $0.request.identifier,
                        "title": $0.request.content.title, "date": $0.date.description] }
                ]
                if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: json, encoding: .utf8) { print(text) }
                exit(0)
            }
            application.run()
            return
        }
        // A direct launch of the executable should not start a second scheduler.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) { return }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
