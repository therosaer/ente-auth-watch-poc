import Foundation
import Security
import WatchConnectivity

/// Holds synced accounts. Secrets live in the watch Keychain, not in plain files.
final class AccountStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var accounts: [OTPAccount] = []

    private let service = "ente.auth.watch"
    private let keychainAccount = "codes"

    override init() {
        super.init()
        accounts = loadFromKeychain()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        apply(context)
    }

    private func apply(_ context: [String: Any]) {
        guard let urls = context["codes"] as? [String] else { return }
        let parsed = urls.compactMap { OTPAccount(url: $0) }
        saveToKeychain(urls)
        DispatchQueue.main.async { self.accounts = parsed }
    }

    // MARK: Keychain

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: keychainAccount]
    }

    private func saveToKeychain(_ urls: [String]) {
        guard let data = try? JSONEncoder().encode(urls) else { return }
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    private func loadFromKeychain() -> [OTPAccount] {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let urls = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return urls.compactMap { OTPAccount(url: $0) }
    }
}
