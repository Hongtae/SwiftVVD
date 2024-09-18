//
//  File: AudioPlayer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

@AudioActor
public class AudioPlayer {

    public nonisolated var sampleRate: Int  { stream.sampleRate }
    public nonisolated var channels: Int    { stream.channels }
    public nonisolated var bits: Int        { stream.bits }
    public nonisolated var duration: Double { stream.timeTotal }

    public var position: Double { stream.timePosition }

    public let source: AudioSource
    public let stream: AudioStream

    var playing = false
    var buffering = false
    var bufferedPosition: Double = 0.0
    var playbackPosition: Double = 0.0
    var playLoopCount = 0
    var maxBufferingTime = 1.0

    public var retainedWhilePlaying = false

    public nonisolated init(source: AudioSource, stream: AudioStream) {
        self.source = source
        self.stream = stream
    }

    deinit {
        source.stop()
        source.dequeueBuffers()
    }

    public func play() {
        if self.playing == false {
            self.playing = true
            self.buffering = true
            self.playLoopCount = 1
        }
    }

    public func play(start: Double, loopCount: Int = 1) {
        if self.playing == false {
            self.source.stop()
            self.source.dequeueBuffers()

            self.playing = true
            self.buffering = true
            self.playLoopCount = loopCount
            _=self.stream.seek(time: start)
            self.playbackPosition = self.stream.timePosition
        }
    }

    public func stop() {
        _=self.stream.seek(pcm: 0)
        self.source.stop()
        self.source.dequeueBuffers()
        
        self.playing = false
        self.playbackPosition = 0
        self.bufferedPosition = 0
    }

    public func pause() {
        if self.playing {
            self.source.pause()
        }
    }

    public var isPaused: Bool {
        return self.source.state == .paused
    }

    open func bufferingStateChanged(_: Bool, timeStamp: Double) {
    }

    open func playbackStateChanged(_: Bool, position: Double) {
    }

    open func processStream(data: UnsafeRawPointer, byteCount: Int, timeStamp: Double) {        
    }
}
