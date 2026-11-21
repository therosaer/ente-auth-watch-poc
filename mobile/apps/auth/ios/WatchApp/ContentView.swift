import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    Text("Open Ente Auth on your iPhone to sync codes.")
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        List(store.accounts) { acct in
                            AccountRow(account: acct, date: timeline.date)
                        }
                    }
                }
            }
            .navigationTitle("Auth")
        }
    }
}

struct AccountRow: View {
    let account: OTPAccount
    let date: Date

    var body: some View {
        let remaining = account.secondsRemaining(at: date)
        let code = account.code(at: date)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.title).font(.caption).lineLimit(1)
                if !account.subtitle.isEmpty {
                    Text(account.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(formatted(code))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(remaining <= 5 ? .red : .primary)
            }
            Spacer()
            ZStack {
                Circle().stroke(.secondary.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(account.period, 1)))
                    .stroke(remaining <= 5 ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(remaining)").font(.system(size: 10))
            }
            .frame(width: 26, height: 26)
        }
    }

    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return code.prefix(3) + " " + code.suffix(3)
    }
}
