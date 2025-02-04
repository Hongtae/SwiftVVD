//
//  File: AudioDeviceContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import OpenAL

private let maxBufferCount = 3
private let minBufferTime = 0.4
private let maxBufferTime = 10.0

public final class AudioDeviceContext: @unchecked Sendable {
    public let device: AudioDevice
    public let listener: AudioListener

    struct Player: Sendable {
        nonisolated(unsafe) weak var player: AudioPlayer?
    }
    private let players = Mutex<[Player]>([])
    private let lock = NSLock()

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

            var buffer: UnsafeMutableRawBufferPointer = .allocate(byteCount: 1024, alignment: 1)

            var retainedPlayers: [AudioPlayer] = []

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                let players: [AudioPlayer] = self.players.withLock {
                    let r = $0.compactMap(\.player)
                    $0 = r.map { Player(player: $0) }
                    return r
                }

                retainedPlayers.removeAll(keepingCapacity: true)

                // update all active audio streams!
                for player in players {
                    if player.playing {
                        let source = player.source
                        source.dequeueBuffers()

                        if player.buffering && source.numberOfBuffersInQueue() < maxBufferCount {
                            // buffering!                            
                            let stream = player.stream
                            let bufferingTime = clamp(player.maxBufferingTime, min: minBufferTime, max: maxBufferTime)
                            let sampleAlignment = stream.channels * stream.bits >> 3
                            let bufferSize = Int(bufferingTime * Double(stream.sampleRate)) * sampleAlignment

                            if bufferSize > buffer.count {  // resize buffer
                                buffer.deallocate()
                                buffer = .allocate(byteCount: bufferSize, alignment: 1)
                            }

                            let bufferPos = stream.timePosition
                            let bytesRead = stream.read(buffer.baseAddress!, count: bufferSize)
                            if bytesRead > 0 {
                                player.processStream(data: buffer.baseAddress!, byteCount: bytesRead, timeStamp: bufferPos)
                                if source.enqueueBuffer(sampleRate: stream.sampleRate,
                                                        bits: stream.bits,
                                                        channels: stream.channels,
                                                        data: buffer.baseAddress!,
                                                        byteCount: bufferSize,
                                                        timeStamp: bufferPos) {
                                    player.playing = true
                                    player.bufferedPosition = stream.timePosition

                                    player.bufferingStateChanged(true, timeStamp: bufferPos)
                                } else {    // error
                                    Log.err("AudioSource.enqueueBuffer failed")

                                    player.buffering = false
                                    player.playing = false
                                }
                            } else if bytesRead == 0 {  // EOF
                                if player.playLoopCount > 1 {
                                    player.playLoopCount -= 1
                                    _=stream.seek(pcm: 0) // rewind
                                } else {
                                    player.buffering = false
                                }
                            } else {    // error!
                                Log.err("AudioStream.read failed.")
                                player.playing = false
                                player.buffering = false
                                source.stop()
                                source.dequeueBuffers()
                            }

                            if player.buffering == false {
                                player.bufferingStateChanged(false, timeStamp: bufferPos)
                            }
                        }

                        // update state
                        if player.playing {
                            if source.state == .stopped {
                                if source.numberOfBuffersInQueue() > 0 {
                                    source.play()
                                } else {
                                    // done.
                                    player.playing = false
                                }
                            }
                        }

                        if player.playing {
                            let pos = source.timePosition
                            if player.playbackPosition != pos {
                                player.playbackPosition = pos
                                player.playbackStateChanged(true, position: player.playbackPosition)
                            }
                            if player.retainedWhilePlaying {
                                retainedPlayers.append(player)
                            }
                        } else {
                            player.playbackStateChanged(false, position: player.playbackPosition)
                        }
                    }
                }

                //await Task.yield()
                do {
                    try await Task.sleep(nanoseconds: 200_000_000) // 200ms
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
        if let source = device.makeSource() {
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
    let devices = availableALDevices()
    if devices.count > 0 {
        if let device = AudioDevice(deviceName: devices[0].name) {
            return AudioDeviceContext(device: device)
        }
    }
    return nil
}
