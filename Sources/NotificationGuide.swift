import AppKit

@MainActor
final class NotificationGuide: NSObject {
    static let version = 1
    private var alert: NSAlert?

    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Pour voir les rappels sur le Bureau"
        alert.informativeText = "Si « Ne pas déranger » ou un autre mode Concentration est actif, macOS peut masquer les bannières de Bouge, même si les notifications sont autorisées.\n\nTu peux :\n• Désactiver ce mode dans le Centre de contrôle.\n• Ou garder ce mode et autoriser Bouge dans Réglages Système → Concentration → ton mode → Apps autorisées.\n\nVérifie aussi que l’affichage sur le Bureau est activé dans Réglages Système → Notifications → Bouge. Puis utilise « Tester la notification »."
        alert.addButton(withTitle: "J’ai compris")
        alert.addButton(withTitle: "Réglages Concentration…")
        return alert
    }

    func show() {
        if let alert {
            NSApp.activate(ignoringOtherApps: true)
            alert.window.makeKeyAndOrderFront(nil)
            return
        }
        let alert = Self.makeAlert()
        self.alert = alert
        alert.buttons[0].target = self
        alert.buttons[0].action = #selector(dismiss)
        alert.buttons[1].target = self
        alert.buttons[1].action = #selector(openFocusSettings)
        alert.layout()
        alert.window.center()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)
    }

    @objc private func dismiss() {
        alert?.window.close()
        alert = nil
    }

    @objc private func openFocusSettings() {
        dismiss()
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
