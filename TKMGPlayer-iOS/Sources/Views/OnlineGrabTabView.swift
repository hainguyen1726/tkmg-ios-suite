import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnlineGrabTabView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager

    @State private var inputURL = ""
    @State private var searchType = "video" // "video" | "playlist"
    @State private var formatChoice = "audio" // "audio" | "video"
    @State private var videoQuality = "720" // "480" | "720" | "1080" | "best"
    @State private var isResolving = false
    @State private var resolved: ResolvedOnlineBatch?
    @State private var selectedIndexes = Set<Int>()
    @State private var rangeFromText = "1"
    @State private var rangeToText = "40"
    @State private var isDownloading = false
    @State private var downloadProgress = 0.0
    @State private var downloadStatus = ""
    @State private var savePlaylistOnDownload = true
    @State private var errorMessage: String?

    @State private var showPlaylistSheet = false
    @State private var playlistSheetTracks: [ResolvedOnlineTrack]?
    @State private var newPlaylistName = ""

    private let client = OnlineMediaClient()

    private var trimmedInput: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isURLInput: Bool {
        let lower = trimmedInput.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    private var qualityLabel: String {
        videoQuality == "best" ? "Gốc" : "\(videoQuality)p"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Từ khóa YouTube hoặc Link https://...", text: $inputURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.search)
                            .onSubmit {
                                if !isResolving && !isDownloading && !trimmedInput.isEmpty {
                                    Task { await resolveOrSearch() }
                                }
                            }
                        #if canImport(UIKit)
                        Button("Dán") {
                            if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !clip.isEmpty {
                                inputURL = clip
                                errorMessage = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        #endif
                    }

                    if !isURLInput {
                        Picker("Loại tìm kiếm", selection: $searchType) {
                            Text("Tìm Video").tag("video")
                            Text("Tìm Playlist YT").tag("playlist")
                        }
                        .pickerStyle(.segmented)
                    }

                    Picker("Định dạng", selection: $formatChoice) {
                        Text("Audio (MP3)").tag("audio")
                        Text("Video (MP4)").tag("video")
                    }
                    .pickerStyle(.segmented)

                    if formatChoice == "video" {
                        Picker("Chất lượng tải", selection: $videoQuality) {
                            Text("480p").tag("480")
                            Text("720p").tag("720")
                            Text("1080p").tag("1080")
                            Text("Gốc").tag("best")
                        }
                        .pickerStyle(.segmented)
                    }

                    Button {
                        Task { await resolveOrSearch() }
                    } label: {
                        HStack {
                            Spacer()
                            if isResolving {
                                ProgressView().padding(.trailing, 6)
                                Text(isURLInput ? "Đang phân giải..." : "Đang tìm YouTube...")
                            } else {
                                Label(
                                    isURLInput ? "Lấy thông tin / Danh sách bài" : "Tìm kiếm trên YouTube",
                                    systemImage: "magnifyingglass"
                                )
                            }
                            Spacer()
                        }
                        .fontWeight(.semibold)
                    }
                    .disabled(isResolving || isDownloading || trimmedInput.isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Tìm YouTube hoặc Dán Link")
                } footer: {
                    Text("Nhập từ khóa để tìm video / playlist YouTube hoặc dán link Video / Playlist (YouTube, TikTok, Facebook, SoundCloud) qua download.netslive.com.")
                }

                if isDownloading {
                    Section("Đang tải về iPhone") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(downloadStatus)
                                .font(.caption.weight(.medium))
                            ProgressView(value: downloadProgress)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let resolved {
                    let playableItems = resolved.items.filter { !$0.isPlaylistItem }
                    let isPlaylistSearch = (resolved.type == "search" && resolved.searchType == "playlist")

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(resolved.title)
                                .font(.headline)
                            Text(
                                isPlaylistSearch
                                ? "\(resolved.count) Playlist YouTube · Chạm vào Playlist để mở danh sách bài"
                                : "\(resolved.uploader.isEmpty ? "Nguồn trực tuyến" : resolved.uploader) · \(resolved.count) mục · Đang chọn \(selectedIndexes.count)"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        if !isPlaylistSearch && !playableItems.isEmpty {
                            HStack(spacing: 10) {
                                Button {
                                    playOnline(startIndex: nil)
                                } label: {
                                    Label("Nghe Online", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    openPlaylistSheet(tracks: nil)
                                } label: {
                                    Label("Tạo / Thêm PL", systemImage: "bookmark.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                Task { await downloadSelected() }
                            } label: {
                                let fmtLabel = formatChoice == "audio" ? "MP3" : "MP4 (\(qualityLabel))"
                                Label(
                                    "Tải \(selectedIndexes.count) file \(fmtLabel) về Tệp (Offline)",
                                    systemImage: "arrow.down.circle.fill"
                                )
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .disabled(isDownloading || selectedIndexes.isEmpty)

                            Toggle("Tự tạo Playlist Offline khi tải nhiều bài", isOn: $savePlaylistOnDownload)
                                .font(.subheadline)

                            if playableItems.count > 1 {
                                HStack(spacing: 8) {
                                    let allSelected = selectedIndexes.count == playableItems.count
                                    Button(allSelected ? "Bỏ chọn hết" : "Chọn tất cả") {
                                        if allSelected {
                                            selectedIndexes.removeAll()
                                        } else {
                                            selectedIndexes = Set(playableItems.map { $0.index })
                                        }
                                    }
                                    .font(.caption.weight(.semibold))
                                    Spacer()
                                    TextField("Từ", text: $rangeFromText)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 52)
                                    Text("-")
                                    TextField("Đến", text: $rangeToText)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 52)
                                    Button("Chọn") {
                                        applyRangeSelection()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    Section("Danh sách (\(resolved.items.count))") {
                        ForEach(resolved.items) { track in
                            if track.isPlaylistItem {
                                HStack(spacing: 10) {
                                    Image(systemName: "list.bullet.rectangle.fill")
                                        .font(.title3)
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(track.index). \(track.title)")
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                        Text("Playlist YouTube · Chạm để mở danh sách bài")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await openSearchPlaylist(track) }
                                }
                            } else {
                                let isChecked = selectedIndexes.contains(track.index)
                                HStack(spacing: 10) {
                                    Button {
                                        if isChecked {
                                            selectedIndexes.remove(track.index)
                                        } else {
                                            selectedIndexes.insert(track.index)
                                        }
                                    } label: {
                                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isChecked ? .accentColor : .secondary)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isDownloading)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(track.index). \(track.title)")
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(2)
                                        HStack(spacing: 6) {
                                            if !track.uploader.isEmpty {
                                                Text(track.uploader)
                                            }
                                            if track.duration > 0 {
                                                Text("· \(EpisodeNameHelper.formatDuration(track.duration))")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        playOnline(startIndex: track.index)
                                    }

                                    Spacer()

                                    Menu {
                                        Button {
                                            playOnline(startIndex: track.index)
                                        } label: {
                                            Label("Nghe / Xem Online", systemImage: "play.fill")
                                        }
                                        Button {
                                            openPlaylistSheet(tracks: [track])
                                        } label: {
                                            Label("Thêm vào Playlist", systemImage: "text.badge.plus")
                                        }
                                        Divider()
                                        Button {
                                            Task { await downloadTracks([track], format: "audio", isPlaylist: false, folderTitle: nil, createPlaylist: false) }
                                        } label: {
                                            Label("Tải Audio (MP3)", systemImage: "music.note")
                                        }
                                        .disabled(isDownloading)
                                        Button {
                                            Task { await downloadTracks([track], format: "video", isPlaylist: false, folderTitle: nil, createPlaylist: false) }
                                        } label: {
                                            Label("Tải Video (MP4 - \(qualityLabel))", systemImage: "film")
                                        }
                                        .disabled(isDownloading)
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                    }

                                    Button {
                                        playOnline(startIndex: track.index)
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if playerManager.currentItem != nil {
                    Color.clear.frame(height: 68).listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Tải / Online")
            .sheet(isPresented: $showPlaylistSheet) {
                playlistPickerSheet
            }
        }
    }

    private var playlistPickerSheet: some View {
        NavigationStack {
            List {
                Section("Tạo Playlist Online mới") {
                    TextField("Tên Playlist", text: $newPlaylistName)
                    Button {
                        saveTracksToNewPlaylist()
                    } label: {
                        Label("Tạo Playlist mới", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !library.playlists.isEmpty {
                    Section("Hoặc thêm vào Playlist đã có") {
                        ForEach(library.playlists) { pl in
                            Button {
                                addTracksToExistingPlaylist(pl.id)
                            } label: {
                                HStack {
                                    Text(pl.name)
                                    Spacer()
                                    Text("\(pl.itemIDs.count) bài")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lưu vào Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showPlaylistSheet = false }
                }
            }
        }
    }

    private func cleanDefaultTitle(from batch: ResolvedOnlineBatch) -> String {
        let stripped = batch.title.replacingOccurrences(of: "Tìm kiếm:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "Playlist Online" : stripped
    }

    private func openPlaylistSheet(tracks: [ResolvedOnlineTrack]?) {
        guard let resolved else { return }
        playlistSheetTracks = tracks
        newPlaylistName = cleanDefaultTitle(from: resolved)
        showPlaylistSheet = true
    }

    private func resolveOrSearch(forcePlaylist: Bool = false) async {
        let trimmed = trimmedInput
        guard !trimmed.isEmpty else {
            errorMessage = "Hãy nhập từ khóa YouTube hoặc liên kết Video / Playlist"
            return
        }
        isResolving = true
        errorMessage = nil
        do {
            let batch: ResolvedOnlineBatch
            if isURLInput {
                batch = try await client.resolve(url: trimmed, forcePlaylist: forcePlaylist)
            } else {
                batch = try await client.searchYoutube(query: trimmed, limit: 20, searchType: searchType)
            }
            resolved = batch
            if batch.type == "search" {
                selectedIndexes = []
            } else {
                selectedIndexes = Set(batch.items.filter { !$0.isPlaylistItem }.prefix(40).map { $0.index })
            }
            rangeFromText = "1"
            rangeToText = "\(min(batch.count, 40))"
        } catch {
            errorMessage = error.localizedDescription
        }
        isResolving = false
    }

    private func openSearchPlaylist(_ track: ResolvedOnlineTrack) async {
        guard !track.url.isEmpty, !isResolving else { return }
        inputURL = track.url
        await resolveOrSearch(forcePlaylist: true)
    }

    private func applyRangeSelection() {
        guard let resolved else { return }
        let playable = resolved.items.filter { !$0.isPlaylistItem }
        let a = max(1, Int(rangeFromText) ?? 1)
        let b = min(resolved.count, Int(rangeToText) ?? resolved.count)
        let lo = min(a, b)
        let hi = max(a, b)
        selectedIndexes = Set(playable.filter { $0.index >= lo && $0.index <= hi }.map { $0.index })
    }

    private func playOnline(startIndex: Int?) {
        guard let resolved else { return }
        let playable = resolved.items.filter { !$0.isPlaylistItem }
        guard !playable.isEmpty else { return }

        let asVideo = (formatChoice == "video")
        let tracks: [ResolvedOnlineTrack]
        if startIndex != nil {
            tracks = playable
        } else {
            let picked = playable.filter { selectedIndexes.contains($0.index) }
            tracks = picked.isEmpty ? playable : picked
        }
        guard !tracks.isEmpty else { return }

        let albumName = cleanDefaultTitle(from: resolved)
        let now = Date().timeIntervalSince1970
        let queue = tracks.map { t in
            let streamURL = asVideo ? t.streamVideoURL : t.streamAudioURL
            let padded = String(format: "%02d", t.index)
            return MediaItem(
                id: "online:\(asVideo ? "v" : "a"):\(t.id):\(abs(streamURL.hashValue))",
                relativePath: nil,
                bookmarkData: nil,
                remoteStreamURL: streamURL,
                fileName: "\(padded) - \(t.title).\(asVideo ? "mp4" : "m4a")",
                folderName: "Online",
                kind: asVideo ? .video : .audio,
                sizeBytes: 0,
                modifiedAt: now,
                durationSec: t.duration,
                title: t.title,
                artist: t.uploader.isEmpty ? resolved.uploader : t.uploader,
                album: albumName,
                positionSec: 0,
                isCompleted: false,
                isFavorite: false,
                lastPlayedAt: 0
            )
        }
        let target: MediaItem
        if let startIndex, let found = queue.first(where: { $0.fileName.hasPrefix(String(format: "%02d -", startIndex)) }) {
            target = found
        } else {
            target = queue[0]
        }
        playerManager.play(item: target, inQueue: queue)
    }

    private func tracksForPlaylistSave() -> [ResolvedOnlineTrack] {
        if let explicit = playlistSheetTracks {
            return explicit.filter { !$0.isPlaylistItem }
        }
        guard let resolved else { return [] }
        let playable = resolved.items.filter { !$0.isPlaylistItem }
        let picked = playable.filter { selectedIndexes.contains($0.index) }
        return picked.isEmpty ? playable : picked
    }

    private func saveTracksToNewPlaylist() {
        let chosen = tracksForPlaylistSave()
        guard !chosen.isEmpty else { return }
        library.saveOnlinePlaylistToLibrary(name: newPlaylistName, tracks: chosen, asVideo: formatChoice == "video")
        showPlaylistSheet = false
    }

    private func addTracksToExistingPlaylist(_ playlistID: String) {
        guard let resolved else { return }
        let chosen = tracksForPlaylistSave()
        guard !chosen.isEmpty else { return }
        library.addOnlineTracks(
            chosen,
            toPlaylist: playlistID,
            fallbackAlbum: cleanDefaultTitle(from: resolved),
            asVideo: formatChoice == "video"
        )
        showPlaylistSheet = false
    }

    private func downloadSelected() async {
        guard let resolved, !isDownloading else { return }
        let chosen = resolved.items.filter { !$0.isPlaylistItem && selectedIndexes.contains($0.index) }
        guard !chosen.isEmpty else { return }

        let isPlaylist = (resolved.type == "playlist" || chosen.count > 1)
        let folderTitle = isPlaylist ? cleanDefaultTitle(from: resolved) : nil
        await downloadTracks(
            chosen,
            format: formatChoice,
            isPlaylist: isPlaylist,
            folderTitle: folderTitle,
            createPlaylist: isPlaylist && savePlaylistOnDownload
        )
    }

    private func downloadTracks(
        _ chosen: [ResolvedOnlineTrack],
        format: String,
        isPlaylist: Bool,
        folderTitle: String?,
        createPlaylist: Bool
    ) async {
        guard !isDownloading, !chosen.isEmpty else { return }
        let totalRefCount = resolved?.count ?? chosen.count

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        let targetDir = library.getOnlineDownloadDir(subFolderName: folderTitle)
        var downloadedIDs: [String] = []
        var okCount = 0
        var failCount = 0

        for (idx, track) in chosen.enumerated() {
            do {
                let savedURL = try await client.downloadTrack(
                    track: track,
                    format: format,
                    totalCount: totalRefCount,
                    targetDir: targetDir,
                    isFromPlaylist: isPlaylist,
                    quality: format == "video" ? videoQuality : nil,
                    onStatus: { text in
                        Task { @MainActor in
                            downloadStatus = "(\(idx + 1)/\(chosen.count)) \(track.title): \(text)"
                            downloadProgress = Double(idx) / Double(chosen.count)
                        }
                    }
                )
                if let itemId = library.itemIDForDownloadedURL(savedURL) {
                    downloadedIDs.append(itemId)
                }
                okCount += 1
            } catch {
                failCount += 1
            }
            downloadProgress = Double(idx + 1) / Double(chosen.count)
        }

        await library.scanAllSources()
        if createPlaylist && !downloadedIDs.isEmpty {
            library.createPlaylist(name: folderTitle ?? "Playlist Online", initialItemIDs: downloadedIDs)
        }

        isDownloading = false
        downloadStatus = ""
        library.statusMessage = failCount == 0
            ? "Đã tải xong \(okCount) tệp vào mục Tệp -> TKMG Player -> Online Downloads!"
            : "Tải xong \(okCount) tệp, \(failCount) tệp lỗi."
    }
}
