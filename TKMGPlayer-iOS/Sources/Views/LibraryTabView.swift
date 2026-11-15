import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager
    @EnvironmentObject var updateChecker: AppUpdateChecker

    @State private var searchText = ""
    @State private var activeFilter: MediaFilter = .all
    @State private var sortMode: MediaSortMode = .natural
    @State private var showFileImporter = false
    @State private var showRenameSheet = false
    @State private var selectedIDs = Set<String>()
    @State private var isSelecting = false
    @State private var showAddPlaylistDialog = false

    private var visibleItems: [MediaItem] {
        library.filteredAndSortedItems(query: searchText, filter: activeFilter, sortMode: sortMode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let pending = updateChecker.bannerUpdate {
                    UpdateAvailableBannerView(update: pending) {
                        updateChecker.alertUpdate = pending
                    }
                }
                // Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MediaFilter.allCases) { filter in
                            Button {
                                activeFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(activeFilter == filter ? Color.accentColor : Color.white.opacity(0.08))
                                    .foregroundColor(activeFilter == filter ? .black : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if visibleItems.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "music.note.tv")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Text("Chưa có file MP3 / Video nào")
                            .font(.headline)
                        Text("Nhấn \"Nhập file\" để chọn từ Tệp (Files), iCloud Drive hoặc chép thẳng vào thư mục TKMG Player trên iPhone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Nhập MP3 / Video", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(visibleItems) { item in
                            MediaRowView(
                                item: item,
                                preferFileName: library.preferFileName,
                                isPlayingNow: playerManager.currentItem?.id == item.id,
                                isSelecting: isSelecting,
                                isSelected: selectedIDs.contains(item.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelecting {
                                    if selectedIDs.contains(item.id) {
                                        selectedIDs.remove(item.id)
                                    } else {
                                        selectedIDs.insert(item.id)
                                    }
                                } else {
                                    playerManager.play(item: item, inQueue: visibleItems)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    library.deleteItem(item)
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    library.toggleFavorite(item.id)
                                } label: {
                                    Label("Yêu thích", systemImage: item.isFavorite ? "heart.slash" : "heart.fill")
                                }
                                .tint(.pink)
                            }
                        }

                        if playerManager.currentItem != nil {
                            Color.clear.frame(height: 68).listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("TKMG Player")
            .searchable(text: $searchText, prompt: "Tìm tập truyện, bài hát...")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sắp xếp", selection: $sortMode) {
                            ForEach(MediaSortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Toggle("Ưu tiên hiển thị Tên File", isOn: Binding(
                            get: { library.preferFileName },
                            set: { library.preferFileName = $0; library.saveState() }
                        ))
                        Divider()
                        Button {
                            Task { await updateChecker.checkForUpdates(manual: true) }
                        } label: {
                            Label(
                                updateChecker.isChecking ? "Đang kiểm tra..." : "Kiểm tra bản mới (v\(updateChecker.localVersion))",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(updateChecker.isChecking)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isSelecting {
                        Button("Thêm PL") {
                            showAddPlaylistDialog = true
                        }
                        .disabled(selectedIDs.isEmpty)

                        Button("Đổi tên") {
                            showRenameSheet = true
                        }
                        .disabled(selectedIDs.isEmpty)

                        Button("Xong") {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    } else {
                        Button {
                            isSelecting = true
                        } label: {
                            Image(systemName: "checklist")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        Button {
                            Task { await library.scanAllSources() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFileImporter) {
                MediaFilePicker { urls in
                    Task { await library.importFiles(urls) }
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                BatchRenameSheet(
                    targetItems: visibleItems.filter { selectedIDs.contains($0.id) }
                )
                .environmentObject(library)
            }
            .confirmationDialog("Thêm \(selectedIDs.count) bài vào Playlist", isPresented: $showAddPlaylistDialog) {
                ForEach(library.playlists) { pl in
                    Button(pl.name) {
                        library.addItems(Array(selectedIDs), toPlaylist: pl.id)
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                }
                Button("Tạo Playlist mới...") {
                    library.createPlaylist(
                        name: "Playlist \(library.playlists.count + 1)",
                        initialItemIDs: Array(selectedIDs)
                    )
                    isSelecting = false
                    selectedIDs.removeAll()
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}

struct MediaRowView: View {
    let item: MediaItem
    let preferFileName: Bool
    let isPlayingNow: Bool
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)
            }

            Image(systemName: item.kind == .video ? "film.fill" : "music.note")
                .foregroundColor(isPlayingNow ? .black : .accentColor)
                .frame(width: 40, height: 40)
                .background(isPlayingNow ? Color.accentColor : Color.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.displayTitle(preferFileName: preferFileName))
                        .font(.subheadline.weight(isPlayingNow ? .bold : .medium))
                        .foregroundColor(isPlayingNow ? .accentColor : .primary)
                        .lineLimit(2)
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.pink)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.folderName)
                    Text("•")
                    Text(EpisodeNameHelper.formatDuration(item.durationSec))
                    Text("•")
                    Text(EpisodeNameHelper.formatBytes(item.sizeBytes))
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if item.progressFraction > 0.01 {
                    ProgressView(value: item.isCompleted ? 1.0 : item.progressFraction)
                        .tint(item.isCompleted ? .green : .accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
