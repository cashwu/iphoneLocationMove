import AppKit
import Foundation

@MainActor
protocol SystemSleepHandling: AnyObject {
    func systemWillSleep()
    func systemDidWake()
}

@MainActor
final class SystemSleepObserver: NSObject {
    private weak var handler: (any SystemSleepHandling)?
    private let notificationCenter: NotificationCenter
    private let willSleepNotification: Notification.Name
    private let didWakeNotification: Notification.Name
    private var isStarted = false

    init(
        handler: (any SystemSleepHandling)? = nil,
        notificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        willSleepNotification: Notification.Name =
            NSWorkspace.willSleepNotification,
        didWakeNotification: Notification.Name =
            NSWorkspace.didWakeNotification
    ) {
        self.handler = handler
        self.notificationCenter = notificationCenter
        self.willSleepNotification = willSleepNotification
        self.didWakeNotification = didWakeNotification
    }

    func setHandler(_ handler: (any SystemSleepHandling)?) {
        self.handler = handler
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        notificationCenter.addObserver(
            self,
            selector: #selector(receiveWillSleep),
            name: willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(receiveDidWake),
            name: didWakeNotification,
            object: nil
        )
    }

    func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        notificationCenter.removeObserver(self)
    }

    @objc
    private func receiveWillSleep(_ notification: Notification) {
        handler?.systemWillSleep()
    }

    @objc
    private func receiveDidWake(_ notification: Notification) {
        handler?.systemDidWake()
    }
}
