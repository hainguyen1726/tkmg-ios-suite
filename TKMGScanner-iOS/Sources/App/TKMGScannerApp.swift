import SwiftUI

@main
struct TKMGScannerApp: App {
    @StateObject private var store = ScanStore()
#if SIDELOAD_BUILD
    @StateObject private var updateChecker = AppUpdateChecker(appId: "tkmg-scanner-ios")
#endif

    var body: some Scene {
        WindowGroup {
#if SIDELOAD_BUILD
            ContentView()
                .environmentObject(store)
                .environmentObject(updateChecker)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.06, green: 0.72, blue: 0.50))
                .withAppUpdateAlerts(checker: updateChecker)
                .onAppear {
                    updateChecker.checkOnLaunchIfNeeded()
                }
#else
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.06, green: 0.72, blue: 0.50))
#endif
        }
    }
}
