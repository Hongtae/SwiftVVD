//
//  File: AudioSource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import OpenAL

public final class AudioSource: Sendable {
    public enum State {
        case stopped
        case playing
        case paused
    }

    public var pitch: Scalar {
        get { getSource(AL_PITCH, 1.0) }
        set { setSource(AL_PITCH, max(newValue, 0.0)) }
    }

    public var gain: Scalar {
        get { getSource(AL_GAIN, 1.0) }
        set { setSource(AL_GAIN, max(newValue, 0.0)) }
    }

    public var maxGain: Scalar {
        get { getSource(AL_MAX_GAIN, 1.0) }
        set { setSource(AL_MAX_GAIN, clamp(newValue, min: 0.0, max: 1.0)) }
    }

    public var maxDistance: Scalar {
        get { getSource(AL_MAX_DISTANCE, .greatestFiniteMagnitude) }
        set { setSource(AL_MAX_DISTANCE, max(newValue, 0.0)) }
    }

    public var rollOffFactor: Scalar {
        get { getSource(AL_ROLLOFF_FACTOR, 1.0) }
        set { setSource(AL_ROLLOFF_FACTOR, max(newValue, 0.0)) }
    }

    public var coneOuterGain: Scalar {
        get { getSource(AL_CONE_OUTER_GAIN, 0.0) }
        set { setSource(AL_CONE_OUTER_GAIN, clamp(newValue, min: 0.0, max: 1.0)) }
    }

    public var coneInnerAngle: Scalar {
        get { getSource(AL_CONE_INNER_ANGLE, 360.0).degreeToRadian() }
        set { setSource(AL_CONE_INNER_ANGLE, clamp(newValue.radianToDegree(), min: 0.0, max: 360.0)) }
    }

    public var coneOuterAngle: Scalar {
        get { getSource(AL_CONE_OUTER_ANGLE, 360.0).degreeToRadian() }
        set { setSource(AL_CONE_OUTER_ANGLE, clamp(newValue.radianToDegree(), min: 0.0, max: 360.0)) }
    }

    public var referenceDistance: Scalar {
        get { getSource(AL_ROLLOFF_FACTOR, 1.0) }
        set { setSource(AL_ROLLOFF_FACTOR, max(newValue, 0.0)) }
    }

    public var position: Vector3 {
        get { getSource(AL_POSITION, Vector3.zero) }
        set { setSource(AL_POSITION, newValue) }
    }

    public var velocity: Vector3 {
        get { getSource(AL_VELOCITY, Vector3.zero) }
        set { setSource(AL_VELOCITY, newValue) }
    }

    public var direction: Vector3 {
        get { getSource(AL_DIRECTION, Vector3.zero) }
        set { setSource(AL_DIRECTION, newValue) }
    }

    public var state: State {
        get {
            var st: ALint = 0
            alGetSourcei(sourceID, AL_SOURCE_STATE, &st)
            switch st {
            case AL_PLAYING:    return .playing
            case AL_PAUSED:     return .paused
            default:            return .stopped
            }
        }
    }

    public func play() {
        self.buffers.withLock { _ in
            alSourcePlay(sourceID)
        }
    }

    public func pause() {
        self.buffers.withLock { _ in
            alSourcePause(sourceID)
        }
    }

    public func stop() {
        self.buffers.withLock { buffers in
            alSourceStop(sourceID)
            var buffersQueued: ALint = 0
            var buffersProcessed: ALint = 0
            alGetSourcei(sourceID, AL_BUFFERS_QUEUED, &buffersQueued)       // entire buffer
            alGetSourcei(sourceID, AL_BUFFERS_PROCESSED, &buffersProcessed) // finished buffer

            for _ in 0..<buffersProcessed {
                var bufferID: ALuint = 0
                alSourceUnqueueBuffers(sourceID, 1, &bufferID)
            }

            if buffersProcessed != buffers.count {
                Log.warn("Buffer mismatch! (\(buffers.count) allocated, \(buffersProcessed) released)")
            }

            alSourcei(sourceID, AL_LOOPING, 0)
            alSourcei(sourceID, AL_BUFFER, 0)
            alSourceRewind(sourceID)

            buffers.forEach {
                var bufferID = $0.bufferID
                alDeleteBuffers(1, &bufferID)
            }
            buffers.removeAll()

            // check error.
            let err = alGetError()
            if err != AL_NO_ERROR {
                Log.err("AudioSource Error: \(String(format: "0x%x (%s)", err, alGetString(err)))")
            }
        }
    }

    public func numberOfBuffersInQueue() -> Int {
        self.dequeueBuffers()
        return self.buffers.withLock { buffers in
            // get number of total buffers.
            var queuedBuffers: ALint = 0
            alGetSourcei(sourceID, AL_BUFFERS_QUEUED, &queuedBuffers)
            if queuedBuffers != buffers.count {
                Log.err("AudioSource buffer count mismatch! (\(buffers.count) != \(queuedBuffers))")
            }
            return buffers.count
        }
    }

    public func dequeueBuffers() {
        self.buffers.withLock { buffers in
            var bufferProcessed: ALint = 0
            alGetSourcei(sourceID, AL_BUFFERS_PROCESSED, &bufferProcessed)
            for _ in 0..<bufferProcessed {
                var bufferID: ALuint = 0
                alSourceUnqueueBuffers(sourceID, 1, &bufferID)
                if bufferID != 0 {
                    if let index = buffers.firstIndex(where: {
                        $0.bufferID == bufferID
                    }) {
                        buffers.remove(at: index)
                    }
                    alDeleteBuffers(1, &bufferID)
                } else {
                    Log.err("AudioSource Failed to dequeue buffer! (source: \(sourceID))")
                }

                // check error.
                let err = alGetError()
                if err != AL_NO_ERROR {
                    Log.err("AudioSource Error: \(String(format: "0x%x (%s)", err, alGetString(err)))")
                }
            }

            if bufferProcessed > 0 {
                // Log.debug("AudioSource buffer dequeued. remains: \(buffers.count)")
            }
        }
    }

    public func enqueueBuffer(sampleRate: Int,
                              bits: Int,
                              channels: Int,
                              data: UnsafeRawPointer,
                              byteCount: Int,
                              timeStamp: Double) -> Bool {
        if byteCount > 0 && sampleRate > 0 {
            let format = self.device.format(bits: bits, channels: channels)
            if format != 0 {
                return self.buffers.withLock { buffers in
                    var finishedBuffers: [ALuint] = []
                    var numBuffersProcessed: ALint = 0
                    alGetSourcei(sourceID, AL_BUFFERS_PROCESSED, &numBuffersProcessed)
                    finishedBuffers.reserveCapacity(Int(numBuffersProcessed))

                    while numBuffersProcessed > 0 {
                        var bufferID: ALuint = 0
                        alSourceUnqueueBuffers(sourceID, 1, &bufferID) // collect buffer to recycle
                        if bufferID != 0 {
                            finishedBuffers.append(bufferID)
                        }
                        numBuffersProcessed -= 1
                    }

                    var bufferID: ALuint = 0
                    if finishedBuffers.isEmpty == false {
                        finishedBuffers.forEach { buffID in
                            if let index = buffers.firstIndex(where: {
                                $0.bufferID == buffID
                            }) {
                                buffers.remove(at: index);
                            }
                        }

                        bufferID = finishedBuffers[0]
                        let numBuffers = finishedBuffers.count
                        if numBuffers > 1 {
                            finishedBuffers[1...].withUnsafeBufferPointer { ptr in
                                alDeleteBuffers(ALsizei(numBuffers - 1), ptr.baseAddress)
                            }
                        }
                    }

                    if bufferID == 0 {
                        alGenBuffers(1, &bufferID)
                    }
                    // enqueue buffer.
                    let bytes = ALsizei(byteCount)
                    alBufferData(bufferID, format, data, bytes, ALsizei(sampleRate))
                    alSourceQueueBuffers(sourceID, 1, &bufferID)

                    let bytesSecond = UInt(sampleRate * channels * (bits >> 3))
                    let bufferInfo = Buffer(timeStamp: timeStamp, bytes: UInt(bytes), bytesSecond: bytesSecond, bufferID: bufferID)
                    buffers.append(bufferInfo)

                    // check error.
                    let err = alGetError()
                    if err != AL_NO_ERROR {
                        Log.err("AudioSource Error: \(String(format: "0x%x (%s)", err, alGetString(err)))")
                    }

                    return true
                }
            }
            else {
                Log.err("Unsupported audio format! (\(bits) bits, \(channels) channels)")
            }          
        }
        self.dequeueBuffers()
        return false
    }

    public var timePosition: Double {
        get {
            self.dequeueBuffers()
            return self.buffers.withLock { buffers in
                if let buffer = buffers.first {
                    assert(buffer.bufferID != 0)
                    assert(buffer.bytes != 0)
                    assert(buffer.bytesSecond != 0)

                    var bytesOffset: ALint = 0
                    alGetSourcei(sourceID, AL_BYTE_OFFSET, &bytesOffset)
                    // If last buffer is too small, playing over next buffer before unqueue.
                    // This can be time accuracy problem.
                    bytesOffset = clamp(bytesOffset, min: 0, max: ALint(buffer.bytes))

                    let position = buffer.timeStamp + Double(bytesOffset) / Double(buffer.bytesSecond)
                    return position
                }
                return 0.0
            }
        }
        set {
            self.dequeueBuffers()
            self.buffers.withLock { buffers in
                if let buffer = buffers.first {
                    assert(buffer.bufferID != 0)
                    assert(buffer.bytes != 0)
                    assert(buffer.bytesSecond != 0)

                    if newValue > buffer.timeStamp {
                        let t = newValue - buffer.timeStamp

                        let bytesOffset: ALint = clamp(ALint(Double(buffer.bytesSecond) * t), min: 0, max: ALint(buffer.bytes))
                        alSourcei(sourceID, AL_BYTE_OFFSET, bytesOffset)

                        // check error.
                        let err = alGetError()
                        if err != AL_NO_ERROR {
                            Log.err("AudioSource Error: \(String(format: "0x%x (%s)", err, alGetString(err)))")
                        }
                    }
                }
            }
        }
    }

    public var timeOffset: Double {
        get {
            self.dequeueBuffers()
            return self.buffers.withLock { buffers in
                if let buffer = buffers.first {
                    assert(buffer.bufferID != 0)
                    assert(buffer.bytes != 0)
                    assert(buffer.bytesSecond != 0)

                    var bytesOffset: ALint = 0
                    alGetSourcei(sourceID, AL_BYTE_OFFSET, &bytesOffset)
                    // If last buffer is too small, playing over next buffer before unqueue.
                    // This can be time accuracy problem.
                    bytesOffset = clamp(bytesOffset, min: 0, max: ALint(buffer.bytes))

                    return Double(bytesOffset) / Double(buffer.bytesSecond)
                }
                return 0.0
            }
        }
        set {
            self.dequeueBuffers()
            self.buffers.withLock { buffers in
                if let buffer = buffers.first {
                    assert(buffer.bufferID != 0)
                    assert(buffer.bytes != 0)
                    assert(buffer.bytesSecond != 0)

                    if newValue > buffer.timeStamp {
                        let t = newValue
                        let bytesOffset: ALint = clamp(ALint(Double(buffer.bytesSecond) * t), min: 0, max: ALint(buffer.bytes))
                        alSourcei(sourceID, AL_BYTE_OFFSET, bytesOffset)

                        // check error.
                        let err = alGetError()
                        if err != AL_NO_ERROR {
                            Log.err("AudioSource Error: \(String(format: "0x%x (%s)", err, alGetString(err)))")
                        }
                    }
                }
            }
        }
    }

    public let device: AudioDevice
    public let sourceID: UInt32

    private struct Buffer {
        let timeStamp: Double
        let bytes: UInt
        let bytesSecond: UInt
        let bufferID: ALuint
    }

    private let buffers = Mutex<[Buffer]>([])

    init(device: AudioDevice, sourceID: UInt32) {
        assert(sourceID != 0)

        self.device = device
        self.sourceID = sourceID
    }

    deinit {
        assert(alIsSource(sourceID) != 0)

        self.stop()
        let buffers = self.buffers.withLock { $0 }
        assert(buffers.isEmpty)

        var sourceID = self.sourceID
        alDeleteSources(1, &sourceID)

        // check error.
        let err = alGetError()
        if err != AL_NO_ERROR {
            Log.err("AudioSource.\(#function) Error: \(String(format: "0x%x (%s)", err, alGetString(err)))")
        }      
    }

    private func getSource(_ param: ALenum, _ value: Scalar) -> Scalar {
        var value = ALfloat(value)
        alGetSourcef(sourceID, param, &value)
        return Scalar(value)
    }

    private func getSource(_ param: ALenum, _ vector: Vector3) -> Vector3 {
        var v = vector.float3
        alGetSource3f(sourceID, param, &v.0, &v.1, &v.2)
        return Vector3(v)
    }

    private func setSource(_ param: ALenum, _ value: Scalar) {
        alSourcef(sourceID, param, ALfloat(value))
    }

    private func setSource(_ param: ALenum, _ vector: Vector3) {
        let v = vector.float3
        alSource3f(sourceID, param, v.0, v.1, v.2)
    }  
}
