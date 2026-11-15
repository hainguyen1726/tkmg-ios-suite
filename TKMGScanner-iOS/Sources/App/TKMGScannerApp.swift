import SwiftUI

@main
struct TKMGScannerApp: App {
    @StateObject private var store = ScanStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.06, green: 0.72, blue: 0.50))
        }
    }
}
