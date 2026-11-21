import Foundation
import LocalAuthentication
import Security
import WatchConnectivity

/// Holds synced accounts.
///
/// Secrets arrive only as live messages from the phone and are kept in the
/// watch Keychain (unlocked-only, this device only). The persisted application
/// context carries no secrets: just whether sync is on and a revision stamp.
/// Nothing is kept or shown unless the watch has a passcode.
final class AccountStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var accounts: [OTPAccount] = []
    @Published private(set) var needsPasscode = false

    private let service = "ente.auth.watch"
    private let keychainAccount = "codes"
    private let wipePendingKey = "wipePending"
    private let lastRevKey = "lastRev"
    private let keychainMigratedKey = "keychainWhenUnlocked"
    private let defaults = UserDefaults.standard

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        refresh()
    }

    /// Run on launch and whenever the app becomes active.
    func refresh() {
        guard Self.hasPasscode() else {
            wipe()
            publish([], needsPasscode: true)
            return
        }
        if defaults.bool(forKey: wipePendingKey) { wipe() }
        let urls = loadFromKeychain() ?? []
        if !urls.isEmpty, !defaults.bool(forKey: keychainMigratedKey) {
            // Re-save once so older items move to the stricter accessibility class.
            saveToKeychain(urls)
        }
        publish(urls, needsPasscode: false)
        requestCodes()
    }

    static func hasPasscode() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private func publish(_ urls: [String], needsPasscode: Bool) {
        let parsed = urls.compactMap { OTPAccount(url: $0) }
        DispatchQueue.main.async {
            self.accounts = parsed
            self.needsPasscode = needsPasscode
        }
    }

    private func requestCodes() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": true], replyHandler: { [weak self] reply in
            self?.handle(reply)
        }, errorHandler: nil)
    }

    /// Handles a code payload from the phone (a reply or a push).
    private func handle(_ payload: [String: Any]) {
        if payload["unavailable"] as? Bool == true { return }
        guard let enabled = payload["enabled"] as? Bool else { return }
        guard enabled, Self.hasPasscode(), let urls = payload["codes"] as? [String] else {
            wipe()
            publish([], needsPasscode: !Self.hasPasscode())
            return
        }
        saveToKeychain(urls)
        publish(urls, needsPasscode: false)
    }

    private func handleState(_ context: [String: Any]) {
        // Contexts from older builds held a "codes" key with secrets; never read it.
        guard let enabled = context["enabled"] as? Bool else { return }
        if !enabled {
            wipe()
            publish([], needsPasscode: !Self.hasPasscode())
            return
        }
        let rev = context["rev"] as? Double ?? 0
        if rev != defaults.double(forKey: lastRevKey) {
            defaults.set(rev, forKey: lastRevKey)
            requestCodes()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        handleState(session.receivedApplicationContext)
        requestCodes()
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        handleState(context)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { requestCodes() }
    }

    // MARK: Keychain

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: keychainAccount]
    }

    /// Deletes stored codes. If the Keychain can't be reached (watch locked),
    /// the wipe is retried on next launch.
    private func wipe() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        let done = status == errSecSuccess || status == errSecItemNotFound
        defaults.set(!done, forKey: wipePendingKey)
    }

    @discardableResult
    private func saveToKeychain(_ urls: [String]) -> Bool {
        guard let data = try? JSONEncoder().encode(urls) else { return false }
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let ok = SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        if ok {
            defaults.set(false, forKey: wipePendingKey)
            defaults.set(true, forKey: keychainMigratedKey)
        }
        return ok
    }

    private func loadFromKeychain() -> [String]? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let urls = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return urls
    }
}
