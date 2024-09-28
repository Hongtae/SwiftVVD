//
//  File: Compression.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVDHelper

public enum CompressionAlgorithm: Sendable {
    case zlib
    case zstd
    case lz4
    case lzma
    case automatic // Default method for compression, Auto-detected method for decompression.
}

public struct CompressionMethod: Sendable {
    public var algorithm: CompressionAlgorithm
    public var level: Int

    public static let fastest   = CompressionMethod(algorithm:.lz4, level:0)
    public static let fast      = CompressionMethod(algorithm:.lz4, level:9)
    public static let best      = CompressionMethod(algorithm:.lzma, level:9)
    public static let balance   = CompressionMethod(algorithm: .zstd, level:3)
    public static let automatic = CompressionMethod(algorithm: .automatic, level:0)    
}

public enum CompressionResult {
    case success
    case unknownError
    case outOfMemory
    case inputStreamError
    case outputStreamError
    case dataError
    case invalidParameter
    case unknownFormat
}

private extension CompressionResult {
    static func from(_ r:VVDCompressionResult) -> CompressionResult {
        switch r {
        case VVDCompressionResult_Success:           return .success
        case VVDCompressionResult_UnknownError:      return .unknownError
        case VVDCompressionResult_OutOfMemory:       return .outOfMemory
        case VVDCompressionResult_InputStreamError:  return .inputStreamError
        case VVDCompressionResult_OutputStreamError: return .outputStreamError
        case VVDCompressionResult_DataError:         return .dataError
        case VVDCompressionResult_InvalidParameter:  return .invalidParameter
        case VVDCompressionResult_UnknownFormat:     return .unknownFormat
        default:
            break
        }
        return .unknownError
    }
}

public func compress(input: InputStream, inputBytes: Int,
                     output: OutputStream,
                     method: CompressionMethod = .automatic) -> CompressionResult {

    class InputContext {
        let input: InputStream
        let inputBytes: Int
        var position: Int = 0
        init(input: InputStream, inputBytes: Int) {
            self.input = input
            self.inputBytes = inputBytes
        }
    }
    let inputContext = InputContext(input: input, inputBytes: inputBytes)

    var inStream = VVDStream()
    inStream.userContext = unsafeBitCast(inputContext as AnyObject, to: VVDStreamContext.self)
    inStream.read = { ctxt, data, size in
        let input = unsafeBitCast(ctxt, to: AnyObject.self) as! InputContext
        let read = input.input.read(data!.assumingMemoryBound(to: UInt8.self), maxLength: size)
        if read < 0 { return ~UInt64(0) }
        input.position += read
        return UInt64(read)
    }
    inStream.remainLength = { ctxt in 
        let input = unsafeBitCast(ctxt, to: AnyObject.self) as! InputContext
        return UInt64(input.inputBytes - input.position)
    }

    var outStream = VVDStream()
    outStream.userContext = unsafeBitCast(output as AnyObject, to: VVDStreamContext.self)
    outStream.write = { ctxt, data, size in
        let output = unsafeBitCast(ctxt, to: AnyObject.self) as! OutputStream
        let written = output.write(data!.assumingMemoryBound(to: UInt8.self), maxLength: size)
        if written < 0 { return ~UInt64(0) }
        return UInt64(written)
    }

    var level = method.level
    var algo: VVDCompressionAlgorithm
    switch method.algorithm {
        case .zlib: algo = VVDCompressionAlgorithm_Zlib
        case .zstd: algo = VVDCompressionAlgorithm_Zstd
        case .lz4:  algo = VVDCompressionAlgorithm_Lz4
        case .lzma: algo = VVDCompressionAlgorithm_Lzma
        case .automatic:
            algo = VVDCompressionAlgorithm_Zstd
            level = 3
    }
    let inputStreamOpen = input.streamStatus == .notOpen
    let outputStreamOpen = output.streamStatus == .notOpen
    if inputStreamOpen { input.open() }
    if outputStreamOpen { output.open() }

    let result = VVDCompressionEncode(algo, &inStream, &outStream, Int32(level))

    if inputStreamOpen { input.close() }
    if outputStreamOpen { output.close() }

    return .from(result)
}

public func decompress(input: InputStream,
                       output: OutputStream,
                       algorithm: CompressionAlgorithm = .automatic) -> CompressionResult {

    var inStream = VVDStream()
    inStream.userContext = unsafeBitCast(input as AnyObject, to: VVDStreamContext.self)
    inStream.read = { ctxt, data, size in
        let input = unsafeBitCast(ctxt, to: AnyObject.self) as! InputStream
        let read = input.read(data!.assumingMemoryBound(to: UInt8.self), maxLength: size)
        if read < 0 { return ~UInt64(0) }
        return UInt64(read)
    }
    
    var outStream = VVDStream()
    outStream.userContext = unsafeBitCast(output as AnyObject, to: VVDStreamContext.self)
    outStream.write = { ctxt, data, size in
        let output = unsafeBitCast(ctxt, to: AnyObject.self) as! OutputStream
        let written = output.write(data!.assumingMemoryBound(to: UInt8.self), maxLength: size)
        if written < 0 { return ~UInt64(0) }
        return UInt64(written)
    }

    let inputStreamOpen = input.streamStatus == .notOpen
    let outputStreamOpen = output.streamStatus == .notOpen
    if inputStreamOpen { input.open() }
    if outputStreamOpen { output.open() }

    var result: VVDCompressionResult
    if algorithm == .automatic {
        var algo = VVDCompressionAlgorithm(0)
        result = VVDCompressionDecodeAutoDetect(&inStream, &outStream, &algo)
    } else {
        var algo = VVDCompressionAlgorithm(0)
        switch algorithm {
        case .zlib: algo = VVDCompressionAlgorithm_Zlib
        case .zstd: algo = VVDCompressionAlgorithm_Zstd
        case .lz4:  algo = VVDCompressionAlgorithm_Lz4
        case .lzma: algo = VVDCompressionAlgorithm_Lzma
        default:
            break
        }
        result = VVDCompressionDecode(algo, &inStream, &outStream)
    }
    if inputStreamOpen { input.close() }
    if outputStreamOpen { output.close() }

    return .from(result)
}
