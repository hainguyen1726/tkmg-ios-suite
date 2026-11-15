import SwiftUI

@main
struct TKMGPlayerApp: App {
    @StateObject private var library = MediaLibraryStore()
    @StateObject private var playerManager = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(playerManager)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.06, green: 0.72, blue: 0.50))
                .onAppear {
                    playerManager.attachLibrary(library)
                }
                .onOpenURL { url in
                    Task {
                        await library.importFiles([url])
                    }
                }
        }
    }
}
