//
//  File: AudioEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum AudioSampleFormat: Sendable {
    case unsignedInteger
    case signedInteger
    case floatingPoint
}

public struct AudioPCMFormat: Sendable {
    public let sampleFormat: AudioSampleFormat
    public let sampleRate: Int
    public let channels: Int
    public let bits: Int
    public let bytesPerFrame: Int
}

public protocol AudioSourceEffect {
    mutating func processAudio(buffer: UnsafeMutableRawBufferPointer,
                               format: AudioPCMFormat,
                               frameCount: Int,
                               timeStamp: Double)
}
