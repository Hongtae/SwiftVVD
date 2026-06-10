//
//  File: AudioDeviceContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

private let minBufferTime = 0.4
private let maxBufferTime = 10.0

public final class AudioDeviceContext: @unchecked Sendable {
    public let device: AudioDevice
    public let listener: AudioListener

    private struct Player: Sendable {
        nonisolated(unsafe) weak var player: AudioPlayer?
    }

    private let players = Mutex<[Player]>([])
    private var task: Task<Void, Never>?

    public init(device: AudioDevice) {
        self.device = device
        self.listener = AudioListener(device: self.device)

        self.task = .detached(priority: .background) { [weak self] in
            let taskID = UUID()
            detachedServiceTasks.withLock { $0[taskID] = "AudioDeviceContext playback task" }
            defer {
                detachedServiceTasks.withLock { $0[taskID] = nil }
            }

            Log.info("AudioDeviceContext playback task is started.")

            var buffer: UnsafeMutableRawBufferPointer = .allocate(byteCount: 1024, alignment: 16)
            var retainedPlayers: [AudioPlayer] = []

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                let players: [AudioPlayer] = self.players.withLock {
                    let activePlayers = $0.compactMap(\.player)
                    $0 = activePlayers.map { Player(player: $0) }
                    return activePlayers
                }

                retainedPlayers.removeAll(keepingCapacity: true)

                for player in players {
                    let bufferingTime = clamp(player.maxBufferingTime, min: minBufferTime, max: maxBufferTime)
                    if player.servicePlayback(buffer: &buffer,
                                              targetBufferedTime: bufferingTime),
                       player.retainedWhilePlaying {
                        retainedPlayers.append(player)
                    }
                }

                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    break mainLoop
                }
            }

            buffer.deallocate()
            retainedPlayers.removeAll()
            Log.info("AudioDeviceContext playback task is finished.")
        }
    }

    deinit {
        self.task?.cancel()
        self.players.withLock { $0.removeAll() }
    }

    public func makePlayer(stream: AudioStream) -> AudioPlayer? {
        if let source = device.makeSource(stream: stream) {
            let player = AudioPlayer(source: source, stream: stream)
            self.players.withLock {
                $0.append(Player(player: player))
            }
            return player
        }
        return nil
    }
}

public func makeAudioDeviceContext() -> AudioDeviceContext? {
    if let device = AudioDevice() {
        return AudioDeviceContext(device: device)
    }
    return nil
}
