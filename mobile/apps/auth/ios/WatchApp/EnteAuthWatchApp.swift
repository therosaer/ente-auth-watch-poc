import SwiftUI

@main
struct EnteAuthWatchApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
