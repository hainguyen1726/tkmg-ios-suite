import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnlineGrabTabView: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager

    @State private var inputURL = ""
    @State private var formatChoice = "audio" // "audio" | "video"
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

    private let client = OnlineMediaClient()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("https://www.youtube.com/playlist?list=...", text: $inputURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
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

                    Picker("Định dạng", selection: $formatChoice) {
                        Text("Audio (MP3)").tag("audio")
                        Text("Video (MP4)").tag("video")
                    }
                    .pickerStyle(.segmented)

                    Button {
                        Task { await resolveLink() }
                    } label: {
                        HStack {
                            Spacer()
                            if isResolving {
                                ProgressView().padding(.trailing, 6)
                                Text("Đang phân giải...")
                            } else {
                                Label("Lấy thông tin / Danh sách bài", systemImage: "magnifyingglass")
                            }
                            Spacer()
                        }
                        .fontWeight(.semibold)
                    }
                    .disabled(isResolving || isDownloading || inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Nhập Link Video hoặc Playlist")
                } footer: {
                    Text("Hỗ trợ YouTube, Playlist YouTube, TikTok, Facebook, SoundCloud... qua máy chủ download.netslive.com.")
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
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(resolved.title)
                                .font(.headline)
                            Text("\(resolved.uploader.isEmpty ? "Nguồn trực tuyến" : resolved.uploader) · \(resolved.count) mục · Đang chọn \(selectedIndexes.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button {
                                playOnline(startIndex: nil)
                            } label: {
                                Label("Nghe Online", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                saveAsOnlinePlaylist()
                            } label: {
                                Label("Lưu Playlist", systemImage: "bookmark.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            Task { await downloadSelected() }
                        } label: {
                            Label(
                                "Tải \(selectedIndexes.count) file \(formatChoice == "audio" ? "MP3" : "MP4") về Tệp (Offline)",
                                systemImage: "arrow.down.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .disabled(isDownloading || selectedIndexes.isEmpty)

                        Toggle("Tự tạo Playlist sau khi tải xong", isOn: $savePlaylistOnDownload)
                            .font(.subheadline)

                        if resolved.count > 1 {
                            HStack(spacing: 8) {
                                let allSelected = selectedIndexes.count == resolved.items.count
                                Button(allSelected ? "Bỏ chọn hết" : "Chọn tất cả") {
                                    if allSelected {
                                        selectedIndexes.removeAll()
                                    } else {
                                        selectedIndexes = Set(resolved.items.map { $0.index })
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

                    Section("Danh sách (\(resolved.items.count))") {
                        ForEach(resolved.items) { track in
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

                if playerManager.currentItem != nil {
                    Color.clear.frame(height: 68).listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Tải / Online")
        }
    }

    private func resolveLink() async {
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") else {
            errorMessage = "Hãy nhập liên kết hợp lệ bắt đầu bằng http:// hoặc https://"
            return
        }
        isResolving = true
        errorMessage = nil
        do {
            let batch = try await client.resolve(url: trimmed)
            resolved = batch
            selectedIndexes = Set(batch.items.prefix(40).map { $0.index })
            rangeFromText = "1"
            rangeToText = "\(min(batch.count, 40))"
        } catch {
            errorMessage = error.localizedDescription
        }
        isResolving = false
    }

    private func applyRangeSelection() {
        guard let resolved else { return }
        let a = max(1, Int(rangeFromText) ?? 1)
        let b = min(resolved.count, Int(rangeToText) ?? resolved.count)
        let lo = min(a, b)
        let hi = max(a, b)
        selectedIndexes = Set(resolved.items.filter { $0.index >= lo && $0.index <= hi }.map { $0.index })
    }

    private func playOnline(startIndex: Int?) {
        guard let resolved else { return }
        let asVideo = (formatChoice == "video")
        let tracks: [ResolvedOnlineTrack]
        if startIndex != nil {
            tracks = resolved.items
        } else {
            let picked = resolved.items.filter { selectedIndexes.contains($0.index) }
            tracks = picked.isEmpty ? resolved.items : picked
        }
        guard !tracks.isEmpty else { return }

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
                album: resolved.title,
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

    private func saveAsOnlinePlaylist() {
        guard let resolved else { return }
        let picked = resolved.items.filter { selectedIndexes.contains($0.index) }
        let chosen = picked.isEmpty ? resolved.items : picked
        guard !chosen.isEmpty else { return }
        library.saveOnlinePlaylistToLibrary(name: resolved.title, tracks: chosen, asVideo: formatChoice == "video")
    }

    private func downloadSelected() async {
        guard let resolved, !isDownloading else { return }
        let chosen = resolved.items.filter { selectedIndexes.contains($0.index) }
        guard !chosen.isEmpty else { return }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        let isPlaylist = (resolved.type == "playlist" || chosen.count > 1)
        let targetDir = library.getOnlineDownloadDir(subFolderName: isPlaylist ? resolved.title : nil)
        var downloadedIDs: [String] = []
        var okCount = 0
        var failCount = 0

        for (idx, track) in chosen.enumerated() {
            do {
                let savedURL = try await client.downloadTrack(
                    track: track,
                    format: formatChoice,
                    totalCount: resolved.count,
                    targetDir: targetDir,
                    isFromPlaylist: isPlaylist,
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
        if isPlaylist && savePlaylistOnDownload && !downloadedIDs.isEmpty {
            library.createPlaylist(name: resolved.title, initialItemIDs: downloadedIDs)
        }

        isDownloading = false
        downloadStatus = ""
        library.statusMessage = failCount == 0
            ? "Đã tải xong \(okCount) tệp vào mục Tệp -> TKMG Player -> Online Downloads!"
            : "Tải xong \(okCount) tệp, \(failCount) tệp lỗi."
    }
}
