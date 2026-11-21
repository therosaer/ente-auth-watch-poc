import Foundation
import CryptoKit

/// A single account synced from the phone. Parsed from an otpauth:// URL.
struct OTPAccount: Identifiable, Hashable {
    enum Kind { case totp, steam }

    let id: String
    let issuer: String
    let account: String
    let secret: Data
    let digits: Int
    let period: Int
    let algorithm: String
    let kind: Kind

    var title: String { issuer.isEmpty ? account : issuer }
    var subtitle: String { issuer.isEmpty ? "" : account }

    init?(url: String) {
        guard let comps = URLComponents(string: url), comps.scheme == "otpauth" else { return nil }
        let host = comps.host ?? ""
        switch host {
        case "totp": kind = .totp
        case "steam": kind = .steam
        default: return nil
        }
        func q(_ name: String) -> String? {
            comps.queryItems?.first { $0.name.lowercased() == name }?.value
        }
        guard let rawSecret = q("secret"),
              let data = Base32.decode(rawSecret), !data.isEmpty else { return nil }
        secret = data

        var label = comps.path
        if label.hasPrefix("/") { label.removeFirst() }
        label = label.removingPercentEncoding ?? label
        var labelIssuer = ""
        var labelAccount = label
        if let idx = label.firstIndex(of: ":") {
            labelIssuer = String(label[..<idx])
            labelAccount = String(label[label.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        }
        issuer = q("issuer") ?? labelIssuer
        account = labelAccount
        // Reject out-of-range values instead of showing a wrong code or crashing.
        let digits = kind == .steam ? 5 : (Int(q("digits") ?? "") ?? 6)
        let period = Int(q("period") ?? "") ?? 30
        let algorithm = (q("algorithm") ?? "SHA1").uppercased()
        guard (4...10).contains(digits),
              (1...3600).contains(period),
              ["SHA1", "SHA256", "SHA512"].contains(algorithm) else { return nil }
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        id = url
    }

    func code(at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(max(period, 1))
        var be = counter.bigEndian
        let msg = Data(bytes: &be, count: 8)
        let mac = hmac(msg)
        guard mac.count >= 20 else { return "------" }
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let bin = (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        if kind == .steam {
            let alphabet = Array("23456789BCDFGHJKMNPQRTVWXY")
            var v = bin
            var out = ""
            for _ in 0..<5 {
                out.append(alphabet[Int(v % UInt32(alphabet.count))])
                v /= UInt32(alphabet.count)
            }
            return out
        }
        // UInt64 so 10^10 doesn't overflow; digits is capped at 10 in init.
        var mod: UInt64 = 1
        for _ in 0..<digits { mod *= 10 }
        let n = UInt64(bin) % mod
        return String(format: "%0\(digits)d", n)
    }

    func secondsRemaining(at date: Date = Date()) -> Int {
        let p = max(period, 1)
        return p - Int(date.timeIntervalSince1970) % p
    }

    private func hmac(_ msg: Data) -> [UInt8] {
        let key = SymmetricKey(data: secret)
        switch algorithm {
        case "SHA256": return Array(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        case "SHA512": return Array(HMAC<SHA512>.authenticationCode(for: msg, using: key))
        default: return Array(HMAC<Insecure.SHA1>.authenticationCode(for: msg, using: key))
        }
    }
}

enum Base32 {
    static func decode(_ s: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, value = 0
        var out = [UInt8]()
        for ch in s.uppercased().filter({ $0 != "=" && $0 != " " && $0 != "-" }) {
            guard let idx = alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | idx
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return Data(out)
    }
}
