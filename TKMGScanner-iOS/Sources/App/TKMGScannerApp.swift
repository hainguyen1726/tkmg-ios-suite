import SwiftUI

@main
struct TKMGScannerApp: App {
    @StateObject private var store = ScanStore()
    @StateObject private var updateChecker = AppUpdateChecker(appId: "tkmg-scanner-ios")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(updateChecker)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.06, green: 0.72, blue: 0.50))
                .withAppUpdateAlerts(checker: updateChecker)
                .onAppear {
                    updateChecker.checkOnLaunchIfNeeded()
                }
        }
    }
}
