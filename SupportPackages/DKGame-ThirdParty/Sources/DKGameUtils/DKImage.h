#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef enum _DKImagePixelFormat
{
    DKImagePixelFormat_Invalid = 0,
    DKImagePixelFormat_R8,      ///< 1 byte per pixel, uint8
    DKImagePixelFormat_RG8,     ///< 2 bytes per pixel, uint8
    DKImagePixelFormat_RGB8,    ///< 3 bytes per pixel, uint8
    DKImagePixelFormat_RGBA8,   ///< 4 bytes per pixel, uint8
    DKImagePixelFormat_R16,     ///< 2 byte per pixel, uint16
    DKImagePixelFormat_RG16,    ///< 4 bytes per pixel, uint16
    DKImagePixelFormat_RGB16,   ///< 6 bytes per pixel, uint16
    DKImagePixelFormat_RGBA16,  ///< 8 bytes per pixel, uint16
    DKImagePixelFormat_R32,     ///< 4 byte per pixel, uint32
    DKImagePixelFormat_RG32,    ///< 8 bytes per pixel, uint32
    DKImagePixelFormat_RGB32,   ///< 12 bytes per pixel, uint32
    DKImagePixelFormat_RGBA32,  ///< 16 bytes per pixel, uint32
    DKImagePixelFormat_R32F,    ///< 4 bytes per pixel, float32
    DKImagePixelFormat_RG32F,   ///< 8 bytes per pixel, float32
    DKImagePixelFormat_RGB32F,  ///< 12 bytes per pixel, float32
    DKImagePixelFormat_RGBA32F, ///< 16 bytes per pixel, float32
} DKImagePixelFormat;

typedef enum _DKImageFormat
{
    DKImageFormatUnknown = 0,
    DKImageFormatPNG,
    DKImageFormatJPEG,
    DKImageFormatBMP
} DKImageFormat;

typedef enum _DKImageDecodeError
{
    DKImageDecodeError_Success = 0,
    DKImageDecodeError_UnknownFormat,
    DKImageDecodeError_PNG_BufferErrror,
    DKImageDecodeError_JPEG_Error,
    DKImageDecodeError_BMP_DataOverflow,
    DKImageDecodeError_BMP_Unsupported,
    DKImageDecodeError_BMP_InvalidFormat,
    DKImageDecodeError_BMP_DataTooSmall,
    DKImageDecodeError_OutOfMemory,
} DKImageDecodeError;

typedef struct _DKImageDecodeContext
{
    DKImageDecodeError error;
    const char* errorDescription;
    const void* decodedData;
    size_t decodedDataLength;
    DKImageFormat imageFormat;
    DKImagePixelFormat pixelFormat;
    uint32_t width;
    uint32_t height;
} DKImageDecodeContext;

typedef enum _DKImageEncodeError
{
    DKImageEncodeError_Success = 0,
    DKImageEncodeError_InvalidFormat,
    DKImageEncodeError_ImageIsTooLarge,
    DKImageEncodeError_UnknownFormat,
    DKImageEncodeError_UnsupportedPixelFormat,
    DKImageEncodeError_OutOfMemory,
    DKImageEncodeError_PNG_WriteError,
    DKImageEncodeError_JPG_Error,
} DKImageEncodeError;

typedef struct _DKImageEncodeContext
{
    DKImageEncodeError error;
    const char* errorDescription;
    const void* encodedData;
    size_t encodedDataLength;
    DKImageFormat imageFormat;
    DKImagePixelFormat pixelFormat;
    uint32_t width;
    uint32_t height;
} DKImageEncodeContext;

#define DKIMAGE_IDENTIFY_FORMAT_MINIMUM_LENGTH 8

DKImageFormat DKImageIdentifyImageFormatFromHeader(const void*, size_t);
DKImageDecodeContext* DKImageDecodeFromMemory(const void*, size_t);
DKImageEncodeContext* DKImageEncodeFromMemory(DKImageFormat format, uint32_t width, uint32_t height, DKImagePixelFormat pixelFormat, const void*, size_t);

void DKImageReleaseDecodeContext(DKImageDecodeContext*);
void DKImageReleaseEncodeContext(DKImageEncodeContext*);

#ifdef __cplusplus
}
#endif /* __cplusplus */