import AVKit
import SwiftUI

struct FullPlayerSheet: View {
    @EnvironmentObject var library: MediaLibraryStore
    @EnvironmentObject var playerManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showSleepOptions = false

    private let rates: [Float] = [0.8, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let item = playerManager.currentItem {
                    if item.kind == .video {
                        VideoPlayer(player: playerManager.player)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 112))
                                .foregroundColor(.accentColor)
                            Text("Rust ARM64 Natural Engine")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    VStack(spacing: 6) {
                        Text(item.displayTitle(preferFileName: library.preferFileName))
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Text(item.folderName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { isDragging ? dragValue : playerManager.currentTimeSec },
                                set: { dragValue = $0 }
                            ),
                            in: 0...max(playerManager.durationSec, 1),
                            onEditingChanged: { editing in
                                isDragging = editing
                                if !editing {
                                    playerManager.seek(to: dragValue)
                                }
                            }
                        )
                        HStack {
                            Text(EpisodeNameHelper.formatDuration(isDragging ? dragValue : playerManager.currentTimeSec))
                            Spacer()
                            Text(EpisodeNameHelper.formatDuration(playerManager.durationSec))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    }

                    HStack(spacing: 24) {
                        Button { playerManager.playPrevious() } label: {
                            Image(systemName: "backward.end.fill").font(.title2)
                        }
                        Button { playerManager.seek(by: -15) } label: {
                            Image(systemName: "gobackward.15").font(.title2)
                        }
                        Button { playerManager.togglePlayPause() } label: {
                            Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.accentColor)
                        }
                        Button { playerManager.seek(by: 15) } label: {
                            Image(systemName: "goforward.15").font(.title2)
                        }
                        Button { playerManager.playNext() } label: {
                            Image(systemName: "forward.end.fill").font(.title2)
                        }
                    }

                    HStack(spacing: 16) {
                        Menu {
                            ForEach(rates, id: \.self) { rate in
                                Button("\(String(format: "%.2gx", rate))") {
                                    playerManager.setRate(rate)
                                }
                            }
                        } label: {
                            Label("\(String(format: "%.2gx", playerManager.playbackRate))", systemImage: "speedometer")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }

                        Button {
                            playerManager.repeatOne.toggle()
                        } label: {
                            Label("Lặp 1 bài", systemImage: "repeat.1")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(playerManager.repeatOne ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }

                        Button {
                            showSleepOptions = true
                        } label: {
                            let label = playerManager.sleepTimerRemainingSec > 0
                                ? "\(playerManager.sleepTimerRemainingSec / 60 + 1)p"
                                : "Hẹn tắt"
                            Label(label, systemImage: "moon.zzz.fill")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(playerManager.sleepTimerRemainingSec > 0 ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Đang phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Đóng") { dismiss() }
            }
            .confirmationDialog("Hẹn giờ tắt phát", isPresented: $showSleepOptions) {
                Button("15 phút") { playerManager.startSleepTimer(minutes: 15) }
                Button("30 phút") { playerManager.startSleepTimer(minutes: 30) }
                Button("45 phút") { playerManager.startSleepTimer(minutes: 45) }
                Button("60 phút") { playerManager.startSleepTimer(minutes: 60) }
                if playerManager.sleepTimerRemainingSec > 0 {
                    Button("Tắt hẹn giờ", role: .destructive) { playerManager.cancelSleepTimer() }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }
}

struct BatchRenameSheet: View {
    @EnvironmentObject var library: MediaLibraryStore
    @Environment(\.dismiss) var dismiss
    let targetItems: [MediaItem]

    @State private var style: BatchRenameStyle = .normalizeEpisode
    @State private var stripQuality = true
    @State private var rows: [RenamePreviewRow] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Kiểu chuẩn hóa tên tập") {
                    Picker("Kiểu", selection: $style) {
                        ForEach(BatchRenameStyle.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .onChange(of: style) { _ in rebuildRows() }

                    Toggle("Bỏ đuôi (MP3_70K) / (720p)", isOn: $stripQuality)
                        .onChange(of: stripQuality) { _ in rebuildRows() }
                }

                Section("Xem trước (\(rows.filter(\.hasChanges).count) file thay đổi)") {
                    ForEach($rows) { $row in
                        Toggle(isOn: $row.isSelected) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.item.fileName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .strikethrough(row.hasChanges)
                                Text(row.newFileName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(row.hasChanges ? .accentColor : .primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chuẩn hóa tên hàng loạt")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Áp dụng") {
                        Task {
                            await library.applyBatchRename(rows)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { rebuildRows() }
        }
    }

    private func rebuildRows() {
        rows = targetItems.map { item in
            let next = EpisodeNameHelper.normalizedEpisodeFileName(
                originalFileName: item.fileName,
                style: style,
                stripQualitySuffix: stripQuality
            )
            return RenamePreviewRow(item: item, newFileName: next, isSelected: true)
        }
    }
}
