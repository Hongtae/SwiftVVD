//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation
import DKWrapper

public enum ImagePixelFormat {
    case invalid            
    case r8             //  1 byte  per pixel, uint8
    case rg8            //  2 bytes per pixel, uint8
    case rgb8           //  3 bytes per pixel, uint8
    case rgba8          //  4 bytes per pixel, uint8
    case r16            //  2 bytes per pixel, uint16
    case rg16           //  4 bytes per pixel, uint16
    case rgb16          //  6 bytes per pixel, uint16
    case rgba16         //  8 bytes per pixel, uint16
    case r32            //  4 bytes per pixel, uint32
    case rg32           //  8 bytes per pixel, uint32
    case rgb32          // 12 bytes per pixel, uint32
    case rgba32         // 16 bytes per pixel, uint32
    case r32f           //  4 bytes per pixel, float32
    case rg32f          //  8 bytes per pixel, float32
    case rgb32f         // 12 bytes per pixel, float32
    case rgba32f        // 16 bytes per pixel, float32
}

fileprivate extension ImagePixelFormat {
    static func from(dkImagePixelFormat pf: DKImagePixelFormat) -> ImagePixelFormat {
        switch pf {
        case DKImagePixelFormat_R8:         return .r8
        case DKImagePixelFormat_RG8:        return .rg8
        case DKImagePixelFormat_RGB8:       return .rgb8
        case DKImagePixelFormat_RGBA8:      return .rgba8
        case DKImagePixelFormat_R16:        return .r16
        case DKImagePixelFormat_RG16:       return .rg16
        case DKImagePixelFormat_RGB16:      return .rgb16
        case DKImagePixelFormat_RGBA16:     return .rgba16
        case DKImagePixelFormat_R32:        return .r32
        case DKImagePixelFormat_RG32:       return .rg32
        case DKImagePixelFormat_RGB32:      return .rgb32
        case DKImagePixelFormat_RGBA32:     return .rgba32
        case DKImagePixelFormat_R32F:       return .r32f
        case DKImagePixelFormat_RG32F:      return .rg32f
        case DKImagePixelFormat_RGB32F:     return .rgb32f
        case DKImagePixelFormat_RGBA32F:    return .rgba32f
        default:
            return .invalid 
        }
    }

    func dkImagePixelFormat() -> DKImagePixelFormat {
        switch self {
        case .r8:               return DKImagePixelFormat_R8
        case .rg8:              return DKImagePixelFormat_RG8
        case .rgb8:             return DKImagePixelFormat_RGB8
        case .rgba8:            return DKImagePixelFormat_RGBA8
        case .r16:              return DKImagePixelFormat_R16
        case .rg16:             return DKImagePixelFormat_RG16
        case .rgb16:            return DKImagePixelFormat_RGB16
        case .rgba16:           return DKImagePixelFormat_RGBA16
        case .r32:              return DKImagePixelFormat_R32
        case .rg32:             return DKImagePixelFormat_RG32
        case .rgb32:            return DKImagePixelFormat_RGB32
        case .rgba32:           return DKImagePixelFormat_RGBA32
        case .r32f:             return DKImagePixelFormat_R32F
        case .rg32f:            return DKImagePixelFormat_RG32F
        case .rgb32f:           return DKImagePixelFormat_RGB32F
        case .rgba32f:          return DKImagePixelFormat_RGBA32
        default:
            return DKImagePixelFormat_Invalid
        }
    }
}

public enum ImageFormat {
    case unknown
    case png
    case jpeg
    case bmp
}

fileprivate extension ImageFormat {
    static func from(dkImageFormat f: DKImageFormat) -> ImageFormat {
        switch f {
        case DKImageFormat_PNG:     return .png   
        case DKImageFormat_JPEG:    return .jpeg
        case DKImageFormat_BMP:     return .bmp
        default:
            return .unknown
        }
    }
    func dkImageFormat() -> DKImageFormat {
        switch self {
        case .png:      return DKImageFormat_PNG
        case .jpeg:     return DKImageFormat_JPEG
        case .bmp:      return DKImageFormat_BMP
        default:
            return DKImageFormat_Unknown
        }
    }
}

public enum ImageInterpolation {
    case nearest
    case bilinear
    case bicubic
    case spline
    case lanczos
    case gaussian
    case quadratic
}

public class Image {
    public let width: Int
    public let height: Int
    public let depth: Int

    public let pixelFormat: ImagePixelFormat
    public let bytesPerPixel: Int

    private let data: UnsafeRawPointer

    public init?(data: UnsafeRawBufferPointer) {
        var result = DKImageDecodeFromMemory(data.baseAddress, data.count)
        defer { DKImageReleaseDecodeContext(&result) }
        if result.error == DKImageDecodeError_Success {
            self.width = Int(result.width)
            self.height = Int(result.height)
            self.depth = 1
            self.pixelFormat = .from(dkImagePixelFormat: result.pixelFormat)
            self.bytesPerPixel = Int(DKImagePixelFormatBytesPerPixel(result.pixelFormat))

            // let byteCount = self.bytesPerPixel * self.width * self.height
            let byteCount = Int(result.decodedDataLength)
            assert(byteCount == self.bytesPerPixel * self.width * self.height)
            let buffer: UnsafeMutableRawPointer = .allocate(byteCount: byteCount, alignment: 1)
            buffer.copyMemory(from: result.decodedData, byteCount: byteCount)
            self.data = UnsafeRawPointer(buffer)
        } else {
            Log.err("Image DecodeError: \(String(cString: result.errorDescription))")
        }
        return nil
    }

    public func canEncode(toImageFormat imageFormat: ImageFormat) -> Bool {
        let dkImageFormat = imageFormat.dkImageFormat()
        let dkPixelFormat = self.pixelFormat.dkImagePixelFormat()
        let supportFormat = DKImagePixelFormatEncodingSupported(dkImageFormat, dkPixelFormat)
        let pf: ImagePixelFormat = .from(dkImagePixelFormat: supportFormat)
        if pf == self.pixelFormat {
            return true
        }
        return false
    }

    public func encode(format: ImageFormat) -> Data? {
        let imageFormat = format.dkImageFormat()
        let pixelFormat = self.pixelFormat.dkImagePixelFormat()
        let byteCount = self.bytesPerPixel * self.width * self.height

        var result = DKImageEncodeFromMemory(imageFormat,
                                             UInt32(self.width),
                                             UInt32(self.height),
                                             pixelFormat, self.data, byteCount)
        defer { DKImageReleaseEncodeContext(&result) }
        if result.error == DKImageEncodeError_Success {
            return .init(bytes: result.encodedData, count: result.encodedDataLength)
        } else {
            Log.err("Image EncodeError: \(String(cString: result.errorDescription))")
        }
        return nil
    }

    public func resample(width: Int, height: Int, format: ImagePixelFormat, interpolation: ImageInterpolation) -> Image? {
        return nil
    }

    deinit {
        self.data.deallocate()
    }
}
