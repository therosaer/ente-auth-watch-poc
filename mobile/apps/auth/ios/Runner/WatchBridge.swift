import Flutter
import WatchConnectivity

/// Sends codes to the paired Apple Watch app.
///
/// Secrets only ever travel with `sendMessage`, which is live and never written
/// to disk by the system. The application context (which the system keeps on
/// disk on both devices) carries only non-secret state: whether sync is on and a
/// revision stamp. That lets the watch wipe itself, or ask for fresh codes, even
/// if it was out of range when something changed.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private let queue = DispatchQueue(label: "io.ente.auth.watch-bridge")
    // All state below is only touched on `queue`.
    private var enabled = false
    private var codes: [String] = []
    private var stateKnown = false  // false until Flutter has sent its first sync
    private var needsPublish = false
    private var waitingReplies: [([String: Any]) -> Void] = []

    func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "io.ente.auth/watch", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "syncCodes":
                let args = call.arguments as? [String: Any] ?? [:]
                let enabled = args["enabled"] as? Bool ?? false
                let codes = args["codes"] as? [String] ?? []
                self?.queue.async { self?.update(enabled: enabled, codes: codes) }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: State (on queue)

    private func update(enabled: Bool, codes: [String]) {
        self.enabled = enabled
        self.codes = enabled ? codes : []
        stateKnown = true
        let replies = waitingReplies
        waitingReplies = []
        replies.forEach { $0(payload()) }
        publishState()
        pushIfReachable()
    }

    private func payload() -> [String: Any] {
        enabled ? ["enabled": true, "codes": codes] : ["enabled": false]
    }

    private func publishState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            needsPublish = true
            return
        }
        needsPublish = false
        guard session.isPaired, session.isWatchAppInstalled else { return }
        // Also replaces any older context that still held secrets.
        try? session.updateApplicationContext([
            "enabled": enabled,
            "rev": Date().timeIntervalSince1970,
        ])
    }

    private func pushIfReachable() {
        guard stateKnown, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(payload(), replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        queue.async {
            guard state == .activated, self.stateKnown else { return }
            if self.needsPublish { self.publishState() }
            self.pushIfReachable()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        queue.async { self.pushIfReachable() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? Bool == true else {
            replyHandler([:])
            return
        }
        queue.async {
            if self.stateKnown {
                replyHandler(self.payload())
                return
            }
            // Woken before Flutter has synced. Wait briefly, then give up.
            self.waitingReplies.append(replyHandler)
            if self.waitingReplies.count == 1 {
                self.queue.asyncAfter(deadline: .now() + 8) {
                    guard !self.stateKnown else { return }
                    let replies = self.waitingReplies
                    self.waitingReplies = []
                    replies.forEach { $0(["unavailable": true]) }
                }
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
