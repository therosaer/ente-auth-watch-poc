import Flutter
import WatchConnectivity

/// Pushes otpauth URLs to the paired Apple Watch app via WatchConnectivity.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var pending: [String]?

    func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "io.ente.auth/watch", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "syncCodes":
                let urls = (call.arguments as? [String]) ?? []
                self?.send(urls)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func send(_ urls: [String]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = urls
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(["codes": urls])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let urls = pending, state == .activated {
            pending = nil
            send(urls)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
