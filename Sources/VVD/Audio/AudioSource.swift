//
//  File: AudioSource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
private import miniaudio

public enum AudioAttenuationModel: Sendable {
    case none
    case inverse
    case linear
    case exponential
}

private func audioSampleFormat(bits: Int) -> AudioSampleFormat? {
    switch bits {
    case 8:     return .unsignedInteger
    case 16:    return .signedInteger
    case 24:    return .signedInteger
    case 32:    return .floatingPoint
    default:    return nil
    }
}

private func miniaudioFormat(bits: Int) -> ma_format {
    switch bits {
    case 8:     return ma_format_u8
    case 16:    return ma_format_s16
    case 24:    return ma_format_s24
    case 32:    return ma_format_f32
    default:    return ma_format_unknown
    }
}

private func miniaudioModel(_ model: AudioAttenuationModel) -> ma_attenuation_model {
    switch model {
    case .none:         return ma_attenuation_model_none
    case .inverse:      return ma_attenuation_model_inverse
    case .linear:       return ma_attenuation_model_linear
    case .exponential:  return ma_attenuation_model_exponential
    }
}

private func audioAttenuationModel(_ model: ma_attenuation_model) -> AudioAttenuationModel {
    switch model {
    case ma_attenuation_model_none:         return .none
    case ma_attenuation_model_linear:       return .linear
    case ma_attenuation_model_exponential:  return .exponential
    default:                                return .inverse
    }
}

private struct MiniAudioDataSourceStorage {
    var base: ma_data_source_base
    var owner: UnsafeMutableRawPointer?
}

private func miniAudioStreamDataSource(_ dataSource: UnsafeMutableRawPointer?) -> MiniAudioStreamDataSource? {
    guard let dataSource else { return nil }
    let storage = dataSource.assumingMemoryBound(to: MiniAudioDataSourceStorage.self)
    guard let owner = storage.pointee.owner else { return nil }
    return Unmanaged<MiniAudioStreamDataSource>.fromOpaque(owner).takeUnretainedValue()
}

private let audioDataSourceRead: @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?,
    ma_uint64,
    UnsafeMutablePointer<ma_uint64>?
) -> ma_result = { dataSource, framesOut, frameCount, framesRead in
    guard let source = miniAudioStreamDataSource(dataSource) else { return MA_INVALID_ARGS }
    let count = source.read(framesOut: framesOut, frameCount: frameCount)
    framesRead?.pointee = count
    if frameCount > 0 && count == 0 {
        return MA_AT_END
    }
    return MA_SUCCESS
}

private let audioDataSourceSeek: @convention(c) (
    UnsafeMutableRawPointer?,
    ma_uint64
) -> ma_result = { dataSource, frameIndex in
    guard let source = miniAudioStreamDataSource(dataSource) else { return MA_INVALID_ARGS }
    return source.seek(frameIndex: frameIndex)
}

private let audioDataSourceGetDataFormat: @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<ma_format>?,
    UnsafeMutablePointer<ma_uint32>?,
    UnsafeMutablePointer<ma_uint32>?,
    UnsafeMutablePointer<ma_channel>?,
    Int
) -> ma_result = { dataSource, format, channels, sampleRate, channelMap, channelMapCap in
    guard let source = miniAudioStreamDataSource(dataSource) else { return MA_INVALID_ARGS }
    return source.getDataFormat(format: format,
                                channels: channels,
                                sampleRate: sampleRate,
                                channelMap: channelMap,
                                channelMapCap: channelMapCap)
}

private let audioDataSourceGetCursor: @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<ma_uint64>?
) -> ma_result = { dataSource, cursor in
    guard let source = miniAudioStreamDataSource(dataSource) else { return MA_INVALID_ARGS }
    return source.getCursor(cursor)
}

private let audioDataSourceGetLength: @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<ma_uint64>?
) -> ma_result = { dataSource, length in
    guard let source = miniAudioStreamDataSource(dataSource) else { return MA_INVALID_ARGS }
    return source.getLength(length)
}

nonisolated(unsafe) private let audioDataSourceVTable: UnsafePointer<ma_data_source_vtable> = {
    let pointer = UnsafeMutablePointer<ma_data_source_vtable>.allocate(capacity: 1)
    pointer.initialize(to: ma_data_source_vtable(
        onRead: audioDataSourceRead,
        onSeek: audioDataSourceSeek,
        onGetDataFormat: audioDataSourceGetDataFormat,
        onGetCursor: audioDataSourceGetCursor,
        onGetLength: audioDataSourceGetLength,
        onSetLooping: nil,
        flags: 0))
    return UnsafePointer(pointer)
}()

private final class LockedAudioEffects: @unchecked Sendable {
    private let effectLock = NSLock()
    private let realtimeEffectLock = NSLock()
    private var effectValue: (any AudioSourceEffect)?
    private var realtimeEffectValue: (any AudioSourceEffect)?

    var effect: (any AudioSourceEffect)? {
        get {
            effectLock.lock()
            defer { effectLock.unlock() }
            return effectValue
        }
        set {
            effectLock.lock()
            defer { effectLock.unlock() }
            effectValue = newValue
        }
    }

    var realtimeEffect: (any AudioSourceEffect)? {
        get {
            realtimeEffectLock.lock()
            defer { realtimeEffectLock.unlock() }
            return realtimeEffectValue
        }
        set {
            realtimeEffectLock.lock()
            defer { realtimeEffectLock.unlock() }
            realtimeEffectValue = newValue
        }
    }

    func processEffect(buffer: UnsafeMutableRawBufferPointer,
                       format: AudioPCMFormat,
                       frameCount: Int,
                       timeStamp: Double) {
        effectLock.lock()
        defer { effectLock.unlock() }

        if var effect = effectValue {
            effect.processAudio(buffer: buffer,
                                format: format,
                                frameCount: frameCount,
                                timeStamp: timeStamp)
            effectValue = effect
        }
    }

    func processRealtimeEffect(buffer: UnsafeMutableRawBufferPointer,
                               format: AudioPCMFormat,
                               frameCount: Int,
                               timeStamp: Double) {
        realtimeEffectLock.lock()
        defer { realtimeEffectLock.unlock() }

        if var realtimeEffect = realtimeEffectValue {
            realtimeEffect.processAudio(buffer: buffer,
                                        format: format,
                                        frameCount: frameCount,
                                        timeStamp: timeStamp)
            realtimeEffectValue = realtimeEffect
        }
    }
}

private final class MiniAudioStreamDataSource: @unchecked Sendable {
    private struct BufferState {
        var buffer: [UInt8]
        var readOffset = 0
        var writeOffset = 0
        var readableBytes = 0
        var cursorFrame: ma_uint64 = 0
        var endOfStream = false
        var generation: UInt64 = 0

        init(capacity: Int) {
            self.buffer = [UInt8](repeating: 0, count: capacity)
        }

        mutating func clear(cursorFrame: ma_uint64) {
            readOffset = 0
            writeOffset = 0
            readableBytes = 0
            self.cursorFrame = cursorFrame
            endOfStream = false
            generation &+= 1
        }
    }

    let stream: AudioStream
    let format: ma_format
    let pcmFormat: AudioPCMFormat
    let bytesPerFrame: Int
    let lengthFrames: ma_uint64?

    private let streamLock = Mutex<Void>(())
    private let bufferState: Mutex<BufferState>
    private let effects = LockedAudioEffects()
    private var storage: UnsafeMutablePointer<MiniAudioDataSourceStorage>?

    init?(stream: AudioStream) {
        let bytesPerSample = stream.bits >> 3
        let bytesPerFrame = stream.channels * bytesPerSample
        let format = miniaudioFormat(bits: stream.bits)
        let sampleFormat = audioSampleFormat(bits: stream.bits)

        guard bytesPerFrame > 0,
              stream.sampleRate > 0,
              stream.channels > 0,
              let sampleFormat,
              format != ma_format_unknown else {
            Log.err("Unsupported audio stream format. bits: \(stream.bits), channels: \(stream.channels), sampleRate: \(stream.sampleRate)")
            return nil
        }

        self.stream = stream
        self.format = format
        self.pcmFormat = AudioPCMFormat(sampleFormat: sampleFormat,
                                        sampleRate: stream.sampleRate,
                                        channels: stream.channels,
                                        bits: stream.bits,
                                        bytesPerFrame: bytesPerFrame)
        self.bytesPerFrame = bytesPerFrame
        if stream.timeTotal > 0 {
            self.lengthFrames = ma_uint64(stream.timeTotal * Double(stream.sampleRate))
        } else {
            self.lengthFrames = nil
        }
        self.bufferState = Mutex(BufferState(capacity: max(bytesPerFrame, bytesPerFrame * stream.sampleRate * 10)))

        let storage = UnsafeMutablePointer<MiniAudioDataSourceStorage>.allocate(capacity: 1)
        storage.initialize(to: MiniAudioDataSourceStorage(
            base: ma_data_source_base(),
            owner: Unmanaged.passUnretained(self).toOpaque()))

        var config = ma_data_source_config_init()
        config.vtable = audioDataSourceVTable

        let result = ma_data_source_init(&config, UnsafeMutableRawPointer(storage))
        guard result == MA_SUCCESS else {
            storage.deinitialize(count: 1)
            storage.deallocate()
            Log.err("ma_data_source_init failed. result: \(result)")
            return nil
        }
        self.storage = storage
    }

    deinit {
        if let storage {
            ma_data_source_uninit(UnsafeMutableRawPointer(storage))
            storage.deinitialize(count: 1)
            storage.deallocate()
        }
    }

    var base: UnsafeMutableRawPointer? {
        if let storage {
            return UnsafeMutableRawPointer(storage)
        }
        return nil
    }

    var effect: (any AudioSourceEffect)? {
        get { effects.effect }
        set { effects.effect = newValue }
    }

    var realtimeEffect: (any AudioSourceEffect)? {
        get { effects.realtimeEffect }
        set { effects.realtimeEffect = newValue }
    }

    var bufferedFrames: Int {
        bufferState.withLock { $0.readableBytes / bytesPerFrame }
    }

    var playbackFinished: Bool {
        bufferState.withLock { $0.endOfStream && $0.readableBytes == 0 }
    }

    private func readBytes(into destination: UnsafeMutableRawPointer,
                           byteCount: Int,
                           state: inout BufferState) -> Int {
        let byteCount = min(byteCount, state.readableBytes)
        guard byteCount > 0 else { return 0 }

        let bufferCount = state.buffer.count
        let readOffset = state.readOffset
        let firstByteCount = min(byteCount, bufferCount - readOffset)
        let secondByteCount = byteCount - firstByteCount

        let copiedBytes = state.buffer.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress else { return 0 }
            destination.copyMemory(from: sourceBase.advanced(by: readOffset),
                                   byteCount: firstByteCount)

            if secondByteCount > 0 {
                destination.advanced(by: firstByteCount)
                    .copyMemory(from: sourceBase, byteCount: secondByteCount)
            }

            return byteCount
        }

        state.readOffset = (readOffset + copiedBytes) % bufferCount
        state.readableBytes -= copiedBytes
        return copiedBytes
    }

    private func discardBytes(byteCount: Int, state: inout BufferState) -> Int {
        let byteCount = min(byteCount, state.readableBytes)
        guard byteCount > 0 else { return 0 }
        state.readOffset = (state.readOffset + byteCount) % state.buffer.count
        state.readableBytes -= byteCount
        return byteCount
    }

    private func writeBytes(from source: UnsafeRawPointer,
                            byteCount: Int,
                            state: inout BufferState) -> Int {
        let byteCount = min(byteCount, state.buffer.count - state.readableBytes)
        guard byteCount > 0 else { return 0 }

        let bufferCount = state.buffer.count
        let writeOffset = state.writeOffset
        let firstByteCount = min(byteCount, bufferCount - writeOffset)
        let secondByteCount = byteCount - firstByteCount

        let copiedBytes = state.buffer.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.baseAddress else { return 0 }
            destinationBase.advanced(by: writeOffset)
                .copyMemory(from: source, byteCount: firstByteCount)

            if secondByteCount > 0 {
                destinationBase.copyMemory(from: source.advanced(by: firstByteCount),
                                           byteCount: secondByteCount)
            }

            return byteCount
        }

        state.writeOffset = (writeOffset + copiedBytes) % bufferCount
        state.readableBytes += copiedBytes
        return copiedBytes
    }

    func read(framesOut: UnsafeMutableRawPointer?, frameCount: ma_uint64) -> ma_uint64 {
        let requestedBytes = Int(frameCount) * bytesPerFrame
        if requestedBytes <= 0 {
            return 0
        }

        let result = bufferState.withLock { state -> (frames: ma_uint64, copiedFrames: Int, timeStamp: Double) in
            let cursorFrame = state.cursorFrame
            let copiedBytes: Int

            if let framesOut {
                copiedBytes = readBytes(into: framesOut,
                                        byteCount: requestedBytes,
                                        state: &state)
                if copiedBytes < requestedBytes && state.endOfStream == false {
                    framesOut.advanced(by: copiedBytes)
                        .initializeMemory(as: UInt8.self,
                                          repeating: 0,
                                          count: requestedBytes - copiedBytes)
                    let copiedFrames = copiedBytes / bytesPerFrame
                    state.cursorFrame += ma_uint64(copiedFrames)
                    return (frameCount, copiedFrames, Double(cursorFrame) / Double(pcmFormat.sampleRate))
                }
            } else {
                copiedBytes = discardBytes(byteCount: requestedBytes, state: &state)
            }

            let copiedFrames = copiedBytes / bytesPerFrame
            state.cursorFrame += ma_uint64(copiedFrames)
            return (ma_uint64(copiedFrames), copiedFrames, Double(cursorFrame) / Double(pcmFormat.sampleRate))
        }

        if result.frames > 0, let framesOut {
            let frameCount = Int(result.frames)
            effects.processRealtimeEffect(buffer: UnsafeMutableRawBufferPointer(start: framesOut,
                                                                                count: frameCount * bytesPerFrame),
                                          format: pcmFormat,
                                          frameCount: frameCount,
                                          timeStamp: result.timeStamp)
        }
        return result.frames
    }

    func seek(frameIndex: ma_uint64) -> ma_result {
        guard stream.seekable else {
            return MA_NOT_IMPLEMENTED
        }

        let position = streamLock.withLock { _ in
            let time = Double(frameIndex) / Double(stream.sampleRate)
            return max(stream.seek(time: time), 0.0)
        }

        bufferState.withLock {
            $0.clear(cursorFrame: ma_uint64(position * Double(stream.sampleRate)))
        }

        return MA_SUCCESS
    }

    var dataFormat: (format: ma_format, channels: ma_uint32, sampleRate: ma_uint32) {
        (format, ma_uint32(stream.channels), ma_uint32(stream.sampleRate))
    }

    func getDataFormat(format: UnsafeMutablePointer<ma_format>?,
                       channels: UnsafeMutablePointer<ma_uint32>?,
                       sampleRate: UnsafeMutablePointer<ma_uint32>?,
                       channelMap: UnsafeMutablePointer<ma_channel>?,
                       channelMapCap: Int) -> ma_result {
        let dataFormat = self.dataFormat
        format?.pointee = dataFormat.format
        channels?.pointee = dataFormat.channels
        sampleRate?.pointee = dataFormat.sampleRate
        if let channelMap {
            ma_channel_map_init_standard(ma_standard_channel_map_default,
                                         channelMap,
                                         channelMapCap,
                                         dataFormat.channels)
        }
        return MA_SUCCESS
    }

    func getCursor(_ cursor: UnsafeMutablePointer<ma_uint64>?) -> ma_result {
        guard let cursor else { return MA_INVALID_ARGS }
        return bufferState.withLock {
            cursor.pointee = $0.cursorFrame
            return MA_SUCCESS
        }
    }

    func getLength(_ length: UnsafeMutablePointer<ma_uint64>?) -> ma_result {
        guard let length else { return MA_INVALID_ARGS }
        guard let lengthFrames else {
            length.pointee = 0
            return MA_NOT_IMPLEMENTED
        }
        length.pointee = lengthFrames
        return MA_SUCCESS
    }

    func fillBuffer(into buffer: inout UnsafeMutableRawBufferPointer,
                    targetBufferedFrames: Int) -> AudioSourceBufferingResult {
        let targetBufferedFrames = max(targetBufferedFrames, 1)
        let request = bufferState.withLock { state -> (frames: Int, generation: UInt64) in
            if state.endOfStream {
                return (0, state.generation)
            }
            let targetBytes = targetBufferedFrames * bytesPerFrame
            let desiredBytes = max(targetBytes - state.readableBytes, 0)
            let freeBytes = state.buffer.count - state.readableBytes
            return (min(desiredBytes, freeBytes) / bytesPerFrame, state.generation)
        }
        let availableFrames = request.frames
        guard availableFrames > 0 else { return .idle }

        let byteCount = availableFrames * bytesPerFrame
        if buffer.count < byteCount {
            buffer.deallocate()
            buffer = .allocate(byteCount: byteCount, alignment: 16)
        }

        var timeStamp = 0.0
        let bytesRead = streamLock.withLock { _ in
            timeStamp = stream.timePosition
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return stream.read(baseAddress, count: byteCount)
        }

        if bytesRead > 0 {
            let alignedBytes = (bytesRead / bytesPerFrame) * bytesPerFrame
            guard alignedBytes > 0 else { return .idle }
            let framesRead = alignedBytes / bytesPerFrame

            effects.processEffect(buffer: UnsafeMutableRawBufferPointer(start: buffer.baseAddress,
                                                                        count: alignedBytes),
                                  format: pcmFormat,
                                  frameCount: framesRead,
                                  timeStamp: timeStamp)

            let bytesWritten = bufferState.withLock { state in
                guard state.generation == request.generation else { return 0 }
                return writeBytes(from: UnsafeRawPointer(buffer.baseAddress!),
                                  byteCount: alignedBytes,
                                  state: &state)
            }
            return bytesWritten > 0 ? .buffered(byteCount: bytesWritten, timeStamp: timeStamp) : .idle
        }

        let canMarkEndOfStream = bufferState.withLock { state in
            guard state.generation == request.generation else { return false }
            state.endOfStream = true
            return true
        }
        guard canMarkEndOfStream else { return .idle }

        if bytesRead == 0 {
            return .endOfStream(timeStamp: timeStamp)
        }
        return .error
    }
}

enum AudioSourceBufferingResult {
    case idle
    case buffered(byteCount: Int, timeStamp: Double)
    case endOfStream(timeStamp: Double)
    case error
}

public final class AudioSource: @unchecked Sendable {
    public enum State: Sendable {
        case stopped
        case playing
        case paused
    }

    public var pitch: Scalar {
        get { Scalar(ma_sound_get_pitch(sound)) }
        set { ma_sound_set_pitch(sound, max(Float(newValue), 0.0)) }
    }

    public var gain: Scalar {
        get { Scalar(ma_sound_get_volume(sound)) }
        set { ma_sound_set_volume(sound, max(Float(newValue), 0.0)) }
    }

    public var maxGain: Scalar {
        get { Scalar(ma_sound_get_max_gain(sound)) }
        set { ma_sound_set_max_gain(sound, clamp(Float(newValue), min: 0.0, max: 1.0)) }
    }

    public var maxDistance: Scalar {
        get { Scalar(ma_sound_get_max_distance(sound)) }
        set { ma_sound_set_max_distance(sound, max(Float(newValue), 0.0)) }
    }

    public var rollOffFactor: Scalar {
        get { Scalar(ma_sound_get_rolloff(sound)) }
        set { ma_sound_set_rolloff(sound, max(Float(newValue), 0.0)) }
    }

    public var coneOuterGain: Scalar {
        get {
            var inner: Float = 0
            var outer: Float = 0
            var gain: Float = 0
            ma_sound_get_cone(sound, &inner, &outer, &gain)
            return Scalar(gain)
        }
        set {
            ma_sound_set_cone(sound,
                              Float(coneInnerAngle),
                              Float(coneOuterAngle),
                              clamp(Float(newValue), min: 0.0, max: 1.0))
        }
    }

    public var coneInnerAngle: Scalar {
        get {
            var inner: Float = 0
            var outer: Float = 0
            var gain: Float = 0
            ma_sound_get_cone(sound, &inner, &outer, &gain)
            return Scalar(inner)
        }
        set {
            ma_sound_set_cone(sound,
                              clamp(Float(newValue), min: 0.0, max: .pi * 2.0),
                              Float(coneOuterAngle),
                              Float(coneOuterGain))
        }
    }

    public var coneOuterAngle: Scalar {
        get {
            var inner: Float = 0
            var outer: Float = 0
            var gain: Float = 0
            ma_sound_get_cone(sound, &inner, &outer, &gain)
            return Scalar(outer)
        }
        set {
            ma_sound_set_cone(sound,
                              Float(coneInnerAngle),
                              clamp(Float(newValue), min: 0.0, max: .pi * 2.0),
                              Float(coneOuterGain))
        }
    }

    public var referenceDistance: Scalar {
        get { Scalar(ma_sound_get_min_distance(sound)) }
        set { ma_sound_set_min_distance(sound, max(Float(newValue), 0.0)) }
    }

    public var spatializationEnabled: Bool {
        get { ma_sound_is_spatialization_enabled(sound) != 0 }
        set { ma_sound_set_spatialization_enabled(sound, newValue ? 1 : 0) }
    }

    public var dopplerFactor: Scalar {
        get { Scalar(ma_sound_get_doppler_factor(sound)) }
        set { ma_sound_set_doppler_factor(sound, max(Float(newValue), 0.0)) }
    }

    public var attenuationModel: AudioAttenuationModel {
        get { audioAttenuationModel(ma_sound_get_attenuation_model(sound)) }
        set { ma_sound_set_attenuation_model(sound, miniaudioModel(newValue)) }
    }

    public var position: Vector3 {
        get {
            let v = ma_sound_get_position(sound)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.float3
            ma_sound_set_position(sound, v.0, v.1, v.2)
        }
    }

    public var velocity: Vector3 {
        get {
            let v = ma_sound_get_velocity(sound)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.float3
            ma_sound_set_velocity(sound, v.0, v.1, v.2)
        }
    }

    public var direction: Vector3 {
        get {
            let v = ma_sound_get_direction(sound)
            return Vector3(Scalar(v.x), Scalar(v.y), Scalar(v.z))
        }
        set {
            let v = newValue.normalized().float3
            ma_sound_set_direction(sound, v.0, v.1, v.2)
        }
    }

    public var state: State {
        let current = stateLock.withLock { $0 }
        if current == .playing && (ma_sound_at_end(sound) != 0 || streamDataSource.playbackFinished) {
            return .stopped
        }
        return current
    }

    public var timePosition: Double {
        get {
            var cursor: Float = 0
            if ma_sound_get_cursor_in_seconds(sound, &cursor) == MA_SUCCESS {
                return Double(cursor)
            }
            return 0.0
        }
        set {
            _ = ma_sound_seek_to_second(sound, Float(max(newValue, 0.0)))
        }
    }

    public var timeOffset: Double {
        get { timePosition }
        set { timePosition = newValue }
    }

    public var effect: (any AudioSourceEffect)? {
        get { streamDataSource.effect }
        set { streamDataSource.effect = newValue }
    }

    public var realtimeEffect: (any AudioSourceEffect)? {
        get { streamDataSource.realtimeEffect }
        set { streamDataSource.realtimeEffect = newValue }
    }

    public let device: AudioDevice

    private let streamDataSource: MiniAudioStreamDataSource
    private let sound: UnsafeMutablePointer<ma_sound>
    private let stateLock = Mutex<State>(.stopped)

    init?(device: AudioDevice, stream: AudioStream) {
        guard let streamDataSource = MiniAudioStreamDataSource(stream: stream),
              let base = streamDataSource.base else {
            return nil
        }

        let sound = UnsafeMutablePointer<ma_sound>.allocate(capacity: 1)
        let engine = device.engineRawPointer.assumingMemoryBound(to: ma_engine.self)
        let result = ma_sound_init_from_data_source(engine,
                                                    base,
                                                    0,
                                                    nil,
                                                    sound)
        guard result == MA_SUCCESS else {
            sound.deallocate()
            Log.err("ma_sound_init_from_data_source failed. result: \(result)")
            return nil
        }

        self.device = device
        self.streamDataSource = streamDataSource
        self.sound = sound

        self.spatializationEnabled = true
        self.dopplerFactor = 1.0
        self.attenuationModel = .inverse
        self.direction = Vector3(0, 0, -1)
    }

    deinit {
        ma_sound_uninit(sound)
        sound.deallocate()
    }

    public func play() {
        if (ma_sound_at_end(sound) != 0 || streamDataSource.playbackFinished) &&
            streamDataSource.bufferedFrames == 0 {
            self.timePosition = 0
        }

        if ma_sound_start(sound) == MA_SUCCESS {
            stateLock.withLock { $0 = .playing }
        }
    }

    public func pause() {
        if ma_sound_stop(sound) == MA_SUCCESS {
            stateLock.withLock { $0 = .paused }
        }
    }

    public func stop() {
        _ = ma_sound_stop(sound)
        self.timePosition = 0
        stateLock.withLock { $0 = .stopped }
    }

    var atEnd: Bool {
        ma_sound_at_end(sound) != 0 || streamDataSource.playbackFinished
    }

    var bufferedFrameCount: Int {
        streamDataSource.bufferedFrames
    }

    func fillBuffer(into buffer: inout UnsafeMutableRawBufferPointer,
                    targetBufferedTime: Double) -> AudioSourceBufferingResult {
        let targetFrames = Int(max(targetBufferedTime, 0.0) * Double(streamDataSource.pcmFormat.sampleRate))
        return streamDataSource.fillBuffer(into: &buffer, targetBufferedFrames: targetFrames)
    }

    func markStoppedAtEnd() {
        stateLock.withLock { state in
            if state == .playing {
                state = .stopped
            }
        }
    }
}
