//
//  File: Compression.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKWrapper

public enum CompressionAlgorithm {
    case zlib
    case zstd
    case lz4
    case lzma
    case automatic // Default method for compression, Auto-detected method for decompression.
}

public struct CompressionMethod {
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
    static func from(_ r:DKCompressionResult) -> CompressionResult {
        switch r {
        case DKCompressionResult_Success:           return .success
        case DKCompressionResult_UnknownError:      return .unknownError
        case DKCompressionResult_OutOfMemory:       return .outOfMemory
        case DKCompressionResult_InputStreamError:  return .inputStreamError
        case DKCompressionResult_OutputStreamError: return .outputStreamError
        case DKCompressionResult_DataError:         return .dataError
        case DKCompressionResult_InvalidParameter:  return .invalidParameter
        case DKCompressionResult_UnknownFormat:     return .unknownFormat
        default:
            break
        }
        return .unknownError
    }
}

public func compress(input: InputStream,
                     output: OutputStream,
                     method: CompressionMethod = .automatic) -> CompressionResult {

    var inStream = DKStream()
    inStream.userContext = unsafeBitCast(input as AnyObject, to: DKStreamContext.self)
    inStream.read = { ctxt, data, size in
        let input = unsafeBitCast(ctxt, to: AnyObject.self) as! InputStream
        return UInt64(input.read(data!.assumingMemoryBound(to: UInt8.self), maxLength: size))
    }
    var outStream = DKStream()
    outStream.userContext = unsafeBitCast(output as AnyObject, to: DKStreamContext.self)
    inStream.write = { ctxt, data, size in
        let output = unsafeBitCast(ctxt, to: AnyObject.self) as! OutputStream
        return UInt64(output.write(data!.assumingMemoryBound(to: UInt8.self), maxLength: size))
    }

    var level = method.level
    var algo: DKCompressionAlgorithm
    switch method.algorithm {
        case .zlib: algo = DKCompressionAlgorithm_Zlib
        case .zstd: algo = DKCompressionAlgorithm_Zstd
        case .lz4:  algo = DKCompressionAlgorithm_Lz4
        case .lzma: algo = DKCompressionAlgorithm_Lzma
        case .automatic:
            algo = DKCompressionAlgorithm_Zstd
            level = 3
    }
    let inputStreamOpen = input.streamStatus == .notOpen
    let outputStreamOpen = output.streamStatus == .notOpen
    if inputStreamOpen { input.open() }
    if outputStreamOpen { output.open() }

    let result = DKCompressionEncode(algo, &inStream, &outStream, Int32(level))

    if inputStreamOpen { input.close() }
    if outputStreamOpen { output.close() }

    return .from(result)
}

public func decompress(input: InputStream,
                       output: OutputStream,
                       algorithm: CompressionAlgorithm = .automatic) -> CompressionResult {

    var inStream = DKStream()
    inStream.userContext = unsafeBitCast(input as AnyObject, to: DKStreamContext.self)
    inStream.read = { ctxt, data, size in
        let input = unsafeBitCast(ctxt, to: AnyObject.self) as! InputStream
        let read = input.read(data!.assumingMemoryBound(to: UInt8.self), maxLength: size)
        if read < 0 { return ~UInt64(0) }
        return UInt64(read)
    }
    var outStream = DKStream()
    outStream.userContext = unsafeBitCast(output as AnyObject, to: DKStreamContext.self)
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

    var result: DKCompressionResult
    if algorithm == .automatic {
        var algo = DKCompressionAlgorithm(0)
        result = DKCompressionDecodeAutoDetect(&inStream, &outStream, &algo)
    } else {
        var algo = DKCompressionAlgorithm(0)
        switch algorithm {
        case .zlib: algo = DKCompressionAlgorithm_Zlib
        case .zstd: algo = DKCompressionAlgorithm_Zstd
        case .lz4:  algo = DKCompressionAlgorithm_Lz4
        case .lzma: algo = DKCompressionAlgorithm_Lzma
        default:
            break
        }
        result = DKCompressionDecode(algo, &inStream, &outStream)
    }
    if inputStreamOpen { input.close() }
    if outputStreamOpen { output.close() }

    return .from(result)
}
