import AVFoundation
import Combine
import Foundation
import MediaPlayer

@MainActor
final class AudioPlayerManager: ObservableObject {
    @Published var currentItem: MediaItem?
    @Published var queue: [MediaItem] = []
    @Published var isPlaying = false
    @Published var currentTimeSec: Double = 0
    @Published var durationSec: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var repeatOne = false
    @Published var sleepTimerRemainingSec: Int = 0
    @Published var showFullPlayer = false

    let player = AVPlayer()

    private weak var library: MediaLibraryStore?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var sleepTimer: Timer?
    private var activeSecurityURL: URL?
    private var lastSavedAt: Date = .distantPast

    func attachLibrary(_ library: MediaLibraryStore) {
        self.library = library
        configureAudioSession()
        configureRemoteCommands()
        observePlayer()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func observePlayer() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite {
                    self.currentTimeSec = sec
                    self.updateNowPlayingElapsed()
                    if let current = self.currentItem,
                       Date().timeIntervalSince(self.lastSavedAt) >= 2.0 {
                        self.lastSavedAt = Date()
                        self.library?.updateProgress(
                            itemID: current.id,
                            positionSec: sec,
                            durationSec: self.durationSec
                        )
                    }
                }
            }
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackEnded()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: 15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: posEvent.positionTime) }
            return .success
        }
    }

    func play(item: MediaItem, inQueue newQueue: [MediaItem]) {
        queue = newQueue.isEmpty ? [item] : newQueue
        startItem(item)
    }

    private func startItem(_ item: MediaItem) {
        if let activeSecurityURL {
            activeSecurityURL.stopAccessingSecurityScopedResource()
            self.activeSecurityURL = nil
        }

        guard let resolved = library?.resolveURL(for: item) else { return }
        if resolved.isSecurityScoped {
            if resolved.url.startAccessingSecurityScopedResource() {
                activeSecurityURL = resolved.url
            }
        }

        let playerItem = AVPlayerItem(url: resolved.url)
        player.replaceCurrentItem(with: playerItem)
        currentItem = item
        durationSec = item.durationSec

        let resumeAt = (!item.isCompleted && item.positionSec > 1.0 && item.positionSec < max(item.durationSec - 2.0, 1.0))
            ? item.positionSec
            : 0.0
        currentTimeSec = resumeAt

        if resumeAt > 0 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlayingMetadata(for: item)

        Task {
            if let loadedDuration = try? await playerItem.asset.load(.duration) {
                let sec = CMTimeGetSeconds(loadedDuration)
                if sec.isFinite && sec > 0 {
                    self.durationSec = sec
                    self.updateNowPlayingElapsed()
                }
            }
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        player.pause()
        isPlaying = false
        if let current = currentItem {
            library?.updateProgress(itemID: current.id, positionSec: currentTimeSec, durationSec: durationSec)
        }
        updateNowPlayingElapsed()
    }

    func resume() {
        guard currentItem != nil else { return }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlayingElapsed()
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(durationSec, 0))
        currentTimeSec = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        updateNowPlayingElapsed()
    }

    func seek(by delta: Double) {
        seek(to: currentTimeSec + delta)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
        updateNowPlayingElapsed()
    }

    func playNext() {
        guard let current = currentItem,
              let idx = queue.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIdx = idx + 1
        if nextIdx < queue.count {
            startItem(queue[nextIdx])
        } else {
            pause()
        }
    }

    func playPrevious() {
        if currentTimeSec > 4.0 {
            seek(to: 0)
            return
        }
        guard let current = currentItem,
              let idx = queue.firstIndex(where: { $0.id == current.id }),
              idx > 0 else {
            seek(to: 0)
            return
        }
        startItem(queue[idx - 1])
    }

    private func handleTrackEnded() {
        if let current = currentItem {
            library?.updateProgress(itemID: current.id, positionSec: durationSec, durationSec: durationSec)
        }
        if repeatOne, let current = currentItem {
            var restarted = current
            restarted.positionSec = 0
            restarted.isCompleted = false
            startItem(restarted)
        } else {
            playNext()
        }
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        sleepTimerRemainingSec = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.sleepTimerRemainingSec > 1 {
                    self.sleepTimerRemainingSec -= 1
                } else {
                    self.cancelSleepTimer()
                    self.pause()
                }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemainingSec = 0
    }

    private func updateNowPlayingMetadata(for item: MediaItem) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.displayTitle(preferFileName: library?.preferFileName ?? true),
            MPMediaItemPropertyArtist: item.artist ?? item.folderName,
            MPMediaItemPropertyPlaybackDuration: durationSec,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTimeSec,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        if let album = item.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = durationSec
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTimeSec
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
