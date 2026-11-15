import SwiftUI

struct FoldersTabView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Nguồn thư mục Offline") {
                    ForEach(library.folders) { folder in
                        HStack {
                            Image(systemName: folder.isSandboxBuiltIn ? "iphone" : "folder.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(folder.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(folder.isSandboxBuiltIn ? "App Tệp -> Trên iPhone -> TKMG Player" : "Thư mục liên kết từ Files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { folder.isEnabled },
                                set: { _ in library.toggleFolder(folder.id) }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions {
                            if !folder.isSandboxBuiltIn {
                                Button(role: .destructive) {
                                    library.removeExternalFolder(folder.id)
                                } label: {
                                    Label("Gỡ liên kết", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Liên kết thêm thư mục từ Tệp (Files)", systemImage: "folder.badge.plus")
                    }
                }
            }
            .navigationTitle("Thư mục")
            .sheet(isPresented: $showFolderPicker) {
                FolderLinkPicker { url in
                    Task { await library.linkExternalFolder(url) }
                }
            }
        }
    }
}

struct PlaylistsTabView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var showNewAlert = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if library.playlists.isEmpty {
                    Text("Chưa có Playlist nào. Nhấn \"+\" để tạo danh sách phát riêng.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlist.id)
                                .environmentObject(library)
                                .environmentObject(playerManager)
                        } label: {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 36, height: 36)
                                    .background(Color.accentColor.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(playlist.name)
                                        .font(.headline)
                                    Text("\(playlist.itemIDs.count) bài")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                library.deletePlaylist(playlist.id)
                            } label: {
                                Label("Xóa", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Playlist")
            .toolbar {
                Button {
                    newName = ""
                    showNewAlert = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .alert("Tạo Playlist mới", isPresented: $showNewAlert) {
                TextField("Tên Playlist", text: $newName)
                Button("Tạo") {
                    library.createPlaylist(name: newName)
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager
    let playlistID: String
    @State private var showAddPicker = false

    private var playlist: Playlist? {
        library.playlists.first { $0.id == playlistID }
    }

    private var playlistItems: [MediaItem] {
        library.filteredAndSortedItems(query: "", filter: .all, sortMode: .natural, playlistID: playlistID)
    }

    var body: some View {
        List {
            ForEach(playlistItems) { item in
                HStack {
                    Image(systemName: item.kind == .video ? "film" : "waveform")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text(item.displayTitle(preferFileName: library.preferFileName))
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(EpisodeNameHelper.formatDuration(item.durationSec))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    playerManager.play(item: item, inQueue: playlistItems)
                }
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            Button {
                showAddPicker = true
            } label: {
                Label("Thêm bài", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showAddPicker) {
            MultiAddPlaylistSheet(playlistID: playlistID)
                .environmentObject(library)
        }
    }
}

struct MultiAddPlaylistSheet: View {
    @EnvironmentObject var library: MediaLibraryStore
    @Environment(\.dismiss) var dismiss
    let playlistID: String

    @State private var query = ""
    @State private var selected = Set<String>()

    private var candidates: [MediaItem] {
        library.filteredAndSortedItems(query: query, filter: .all, sortMode: .natural)
    }

    var body: some View {
        NavigationStack {
            List(candidates) { item in
                HStack {
                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected.contains(item.id) ? .accentColor : .secondary)
                    Text(item.displayTitle(preferFileName: library.preferFileName))
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(item.id) { selected.remove(item.id) }
                    else { selected.insert(item.id) }
                }
            }
            .searchable(text: $query, prompt: "Lọc nhanh...")
            .navigationTitle("Chọn bài thêm vào Playlist")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chọn hết") {
                        selected = Set(candidates.map(\.id))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Thêm (\(selected.count))") {
                        library.addItems(Array(selected), toPlaylist: playlistID)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
