import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryTabView()
                    .tabItem {
                        Label("Thư viện", systemImage: "music.note.list")
                    }

                FoldersTabView()
                    .tabItem {
                        Label("Thư mục", systemImage: "folder.fill")
                    }

                PlaylistsTabView()
                    .tabItem {
                        Label("Playlist", systemImage: "list.bullet.rectangle")
                    }
            }

            if playerManager.currentItem != nil {
                MiniPlayerBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 54)
            }
        }
        .sheet(isPresented: $playerManager.showFullPlayer) {
            FullPlayerSheet()
                .environmentObject(library)
                .environmentObject(playerManager)
        }
        .alert("Thông báo", isPresented: Binding(
            get: { library.statusMessage != nil },
            set: { if !$0 { library.statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.statusMessage = nil }
        } message: {
            Text(library.statusMessage ?? "")
        }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager

    var body: some View {
        if let item = playerManager.currentItem {
            HStack(spacing: 12) {
                Image(systemName: item.kind == .video ? "film.fill" : "waveform")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle(preferFileName: library.preferFileName))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(EpisodeNameHelper.formatDuration(playerManager.currentTimeSec)) / \(EpisodeNameHelper.formatDuration(playerManager.durationSec))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    playerManager.togglePlayPause()
                } label: {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }

                Button {
                    playerManager.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                        .frame(width: 32, height: 36)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .onTapGesture {
                playerManager.showFullPlayer = true
            }
        }
    }
}
