//
//  File: AudioStream.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation
import DKWrapper

@globalActor public actor AudioActor: GlobalActor {
    public static let shared = AudioActor()
}

private protocol StreamWrapper {
    var stream: DKStream { get }
}

private class DataStream: StreamWrapper {
    var stream: DKStream
    let source: Data
    var position: Int = 0

    public init(data: Data) {
        self.source = data
        self.stream = DKStream()
        self.stream.userContext = unsafeBitCast(self as AnyObject, to: DKStreamContext.self)
        self.stream.read = { (ctxt, buff, size) -> UInt64 in
            let stream = unsafeBitCast(ctxt, to: AnyObject.self) as! DataStream
            let buffer = UnsafeMutableRawBufferPointer(start: buff, count: Int(size))
            let begin = stream.position
            let end = begin + Int(size)
            let read: Int = stream.source.withUnsafeBytes { ptr in
                let range: UnsafeRawBufferPointer.SubSequence
                if end > ptr.count {
                    range = ptr[begin...]
                } else {
                    range = ptr[begin..<end]
                }
                return range.copyBytes(to: buffer)
            }
            if read < 0 { return ~UInt64(0) }
            stream.position += read
            return UInt64(read)
        }
        self.stream.write = nil // read-only stream!
        self.stream.setPosition = { (ctxt, pos) -> UInt64 in
            let stream = unsafeBitCast(ctxt, to: AnyObject.self) as! DataStream
            stream.position = clamp(Int(pos), min: 0, max: stream.source.count)
            return UInt64(stream.position) 
        }
        self.stream.getPosition = { (ctxt) -> UInt64 in
            let stream = unsafeBitCast(ctxt, to: AnyObject.self) as! DataStream
            return UInt64(stream.position) 
        }
        self.stream.remainLength = { (ctxt) -> UInt64 in
            let stream = unsafeBitCast(ctxt, to: AnyObject.self) as! DataStream
            return UInt64(stream.source.count - Int(stream.position))
        }
        self.stream.totalLength = { (ctxt) -> UInt64 in
            let stream = unsafeBitCast(ctxt, to: AnyObject.self) as! DataStream
            return UInt64(stream.source.count)
        }
    }
}

public enum AudioStreamEncodingFormat {
    case unknown
    case oggVorbis
    case oggFLAC
    case flac
    case mp3
    case wave
}

@AudioActor
public class AudioStream {
    let stream: UnsafeMutablePointer<DKAudioStream>
    private var source: StreamWrapper

    public let format: AudioStreamEncodingFormat

    public nonisolated var sampleRate: Int  { Int(stream.pointee.sampleRate) }
    public nonisolated var channels: Int    { Int(stream.pointee.channels) }
    public nonisolated var bits: Int        { Int(stream.pointee.bits) }
    public nonisolated var seekable: Bool   { stream.pointee.seekable }

    public var rawPosition: UInt64      { stream.pointee.rawPosition(stream) }
    public var pcmPosition: UInt64      { stream.pointee.pcmPosition(stream) }
    public var timePosition: Double     { stream.pointee.timePosition(stream) }

    public let rawTotal: UInt64
    public let pcmTotal: UInt64
    public let timeTotal: Double    // 0 for streaming.

    public func read(_ buffer: UnsafeMutableRawPointer, count: Int) -> Int {
        let read = stream.pointee.read(stream, buffer, count)
        if read == ~UInt64(0) { return -1 }
        return Int(read)
    }

    public func read(_ buffer: UnsafeMutableRawBufferPointer) -> Int {
        let read = stream.pointee.read(stream, buffer.baseAddress, buffer.count)
        if read == ~UInt64(0) { return -1 }
        return Int(read)
    }

    public func seek(raw: UInt64) -> UInt64 {
        return stream.pointee.seekRaw(stream, raw)
    }

    public func seek(pcm: UInt64) -> UInt64 {
        return stream.pointee.seekPcm(stream, pcm)
    }

    public func seek(time: Double) -> Double {
        return stream.pointee.seekTime(stream, time)
    }

    public init?(data: Data) {
        let source = DataStream(data: data)
        if let stream = DKAudioStreamCreate(&source.stream) {
            self.stream = stream
            self.source = source

            switch stream.pointee.mediaType {
            case DKAudioStreamEncodingFormat_OggVorbis:
                self.format = .oggVorbis
            case DKAudioStreamEncodingFormat_OggFLAC:
                self.format = .oggFLAC
            case DKAudioStreamEncodingFormat_FLAC:
                self.format = .flac
            case DKAudioStreamEncodingFormat_MP3:
                self.format = .mp3
            case DKAudioStreamEncodingFormat_Wave:
                self.format = .wave
            default:
                self.format = .unknown
            }
            
            self.rawTotal = stream.pointee.rawTotal(stream)
            self.pcmTotal = stream.pointee.pcmTotal(stream)
            self.timeTotal = stream.pointee.timeTotal(stream)

        } else { return nil }
    }

    deinit {
        DKAudioStreamDestroy(stream)
    }
}
