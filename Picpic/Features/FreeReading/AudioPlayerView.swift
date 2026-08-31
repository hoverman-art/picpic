//
//  AudioPlayerView.swift
//  Picpic
//
//  Lecteur de livres audio LibriVox : streaming AVPlayer des chapitres
//  (MP3 archive.org, HTTPS), enchaînement automatique, ±15 s.
//

import AVFoundation
import SwiftUI

@MainActor
@Observable
final class AudioPlayerModel {
    let audiobook: FreeAudiobook

    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?

    private(set) var currentSectionID: Int?
    private(set) var isPlaying = false

    init(audiobook: FreeAudiobook) {
        self.audiobook = audiobook
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func play(_ section: FreeAudiobook.Section) {
        if currentSectionID == section.id {
            togglePlayPause()
            return
        }
        currentSectionID = section.id
        let item = AVPlayerItem(url: section.listenURL)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forItem: item, queue: .main
        ) { [weak self] in
            Task { @MainActor [weak self] in self?.playNext() }
        }
        player.replaceCurrentItem(with: item)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func skip(_ seconds: Double) {
        let current = player.currentTime().seconds
        let target = max(0, current + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func playNext() {
        guard let currentSectionID,
              let index = audiobook.sections.firstIndex(where: { $0.id == currentSectionID }),
              index + 1 < audiobook.sections.count else {
            isPlaying = false
            return
        }
        play(audiobook.sections[index + 1])
    }

    func stop() {
        player.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private extension NotificationCenter {
    func addObserver(forItem item: AVPlayerItem, queue: OperationQueue,
                     handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item, queue: queue) { _ in handler() }
    }
}

struct AudioPlayerView: View {
    @State private var model: AudioPlayerModel
    @Environment(\.dismiss) private var dismiss

    init(audiobook: FreeAudiobook) {
        _model = State(initialValue: AudioPlayerModel(audiobook: audiobook))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section("Chapitres") {
                    ForEach(model.audiobook.sections) { section in
                        sectionRow(section)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Écouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.currentSectionID != nil {
                    playbackBar
                }
            }
        }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            MascotView(pose: .reading, height: 80)
            Text(model.audiobook.title)
                .font(.display(20))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let total = model.audiobook.totalTimeLabel {
                Label("Durée totale : \(total)", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Lu par des bénévoles LibriVox · domaine public")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionRow(_ section: FreeAudiobook.Section) -> some View {
        Button {
            model.play(section)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.currentSectionID == section.id && model.isPlaying
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(model.currentSectionID == section.id ? Theme.accent : Theme.teal)
                Text(section.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                if let playtime = section.playtime {
                    Text(playtime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("audio.section.\(section.id)")
    }

    private var playbackBar: some View {
        HStack(spacing: 24) {
            Button { model.skip(-15) } label: {
                Image(systemName: "gobackward.15").font(.title3)
            }
            Button { model.togglePlayPause() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: 54, height: 54)
                    .background(Theme.ink, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("audio.playPause")
            Button { model.skip(15) } label: {
                Image(systemName: "goforward.15").font(.title3)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}
