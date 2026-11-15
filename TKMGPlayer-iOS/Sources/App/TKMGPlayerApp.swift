import SwiftUI

@main
struct TKMGPlayerApp: App {
    @StateObject private var library = MediaLibraryStore()
    @StateObject private var playerManager = AudioPlayerManager()
    @StateObject private var updateChecker = AppUpdateChecker(appId: "tkmg-player-ios")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(playerManager)
                .environmentObject(updateChecker)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.06, green: 0.72, blue: 0.50))
                .withAppUpdateAlerts(checker: updateChecker)
                .onAppear {
                    playerManager.attachLibrary(library)
                    updateChecker.checkOnLaunchIfNeeded()
                }
                .onOpenURL { url in
                    Task {
                        await library.importFiles([url])
                    }
                }
        }
    }
}
