//
//  File: AudioPlayer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

public class AudioPlayer: @unchecked Sendable {

    public nonisolated var sampleRate: Int  { stream.sampleRate }
    public nonisolated var channels: Int    { stream.channels }
    public nonisolated var bits: Int        { stream.bits }
    public nonisolated var duration: Double { stream.timeTotal }

    public var position: Double { source.timePosition }

    public let source: AudioSource
    public let stream: AudioStream

    public var retainedWhilePlaying = false
    var maxBufferingTime = 1.0

    private struct PlayerState: Sendable {
        var playing = false
        var playbackPosition: Double = 0.0
        var playLoopCount = 1
    }

    private let playerState = Mutex(PlayerState())

    public nonisolated init(source: AudioSource, stream: AudioStream) {
        self.source = source
        self.stream = stream
    }

    deinit {
        source.stop()
    }

    public func play() {
        let wasPaused = source.state == .paused
        if wasPaused == false && source.atEnd {
            source.timePosition = 0.0
        }
        let startPosition = source.timePosition
        let shouldStart = playerState.withLock { state in
            if state.playing {
                return false
            }
            state.playing = true
            state.playLoopCount = 1
            state.playbackPosition = startPosition
            return true
        }

        if shouldStart {
            if wasPaused {
                source.play()
            }
            playbackStateChanged(true, position: startPosition)
        }
    }

    public func play(start: Double, loopCount: Int = 1) {
        let safeLoopCount = max(loopCount, 1)
        source.stop()
        source.timePosition = max(start, 0.0)

        playerState.withLock { state in
            state.playing = true
            state.playLoopCount = safeLoopCount
            state.playbackPosition = source.timePosition
        }

        playbackStateChanged(true, position: source.timePosition)
    }

    public func stop() {
        source.stop()

        playerState.withLock { state in
            state.playing = false
            state.playbackPosition = 0.0
            state.playLoopCount = 1
        }

        playbackStateChanged(false, position: 0.0)
    }

    public func pause() {
        let position = source.timePosition
        let shouldPause = playerState.withLock { state in
            if state.playing == false {
                return false
            }
            state.playing = false
            state.playbackPosition = position
            return true
        }

        if shouldPause {
            source.pause()
            playbackStateChanged(false, position: position)
        }
    }

    public var isPaused: Bool {
        source.state == .paused
    }

    open func playbackStateChanged(_: Bool, position: Double) {
    }

    func servicePlayback(buffer: inout UnsafeMutableRawBufferPointer,
                         targetBufferedTime: Double) -> Bool {
        let isPlaying = playerState.withLock { $0.playing }
        if isPlaying == false {
            return false
        }

        if source.state != .paused {
            switch source.fillBuffer(into: &buffer, targetBufferedTime: targetBufferedTime) {
            case .idle, .buffered, .endOfStream:
                break
            case .error:
                Log.err("AudioStream.read failed.")
                source.stop()
                playerState.withLock { state in
                    state.playing = false
                    state.playbackPosition = source.timePosition
                    state.playLoopCount = 1
                }
                playbackStateChanged(false, position: source.timePosition)
                return false
            }

            if source.state == .stopped && source.bufferedFrameCount > 0 {
                source.play()
            }
        }

        return monitorPlayback()
    }

    func monitorPlayback() -> Bool {
        let isPlaying = playerState.withLock { $0.playing }
        if isPlaying == false {
            return false
        }

        if source.atEnd {
            let shouldLoop = playerState.withLock { state in
                if state.playLoopCount > 1 {
                    state.playLoopCount -= 1
                    state.playbackPosition = 0.0
                    return true
                }
                state.playing = false
                state.playbackPosition = source.timePosition
                return false
            }

            if shouldLoop {
                source.timePosition = 0.0
                playbackStateChanged(true, position: 0.0)
                return retainedWhilePlaying
            }

            let position = source.timePosition
            source.markStoppedAtEnd()
            playbackStateChanged(false, position: position)
            return false
        }

        let position = source.timePosition
        let didMove = playerState.withLock { state in
            if state.playing && state.playbackPosition != position {
                state.playbackPosition = position
                return true
            }
            return false
        }

        if didMove {
            playbackStateChanged(true, position: position)
        }
        return retainedWhilePlaying
    }
}
