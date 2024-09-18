/*******************************************************************************
 File: Image.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef enum _VVDImagePixelFormat
{
    VVDImagePixelFormat_Invalid = 0,
    VVDImagePixelFormat_R8,      /*   1 byte per pixel, uint8    */
    VVDImagePixelFormat_RG8,     /*  2 bytes per pixel, uint8    */
    VVDImagePixelFormat_RGB8,    /*  3 bytes per pixel, uint8    */
    VVDImagePixelFormat_RGBA8,   /*  4 bytes per pixel, uint8    */
    VVDImagePixelFormat_R16,     /*  2 bytes per pixel, uint16   */
    VVDImagePixelFormat_RG16,    /*  4 bytes per pixel, uint16   */
    VVDImagePixelFormat_RGB16,   /*  6 bytes per pixel, uint16   */
    VVDImagePixelFormat_RGBA16,  /*  8 bytes per pixel, uint16   */
    VVDImagePixelFormat_R32,     /*  4 bytes per pixel, uint32   */
    VVDImagePixelFormat_RG32,    /*  8 bytes per pixel, uint32   */
    VVDImagePixelFormat_RGB32,   /* 12 bytes per pixel, uint32   */
    VVDImagePixelFormat_RGBA32,  /* 16 bytes per pixel, uint32   */
    VVDImagePixelFormat_R32F,    /*  4 bytes per pixel, float32  */
    VVDImagePixelFormat_RG32F,   /*  8 bytes per pixel, float32  */
    VVDImagePixelFormat_RGB32F,  /* 12 bytes per pixel, float32  */
    VVDImagePixelFormat_RGBA32F, /* 16 bytes per pixel, float32  */
} VVDImagePixelFormat;

typedef enum _VVDImageFormat
{
    VVDImageFormat_Unknown = 0,
    VVDImageFormat_PNG,
    VVDImageFormat_JPEG,
    VVDImageFormat_BMP
} VVDImageFormat;

typedef enum _VVDImageDecodeError
{
    VVDImageDecodeError_Success = 0,
    VVDImageDecodeError_DataError,
    VVDImageDecodeError_UnknownFormat,
    VVDImageDecodeError_PNG_Errror,
    VVDImageDecodeError_JPEG_Error,
    VVDImageDecodeError_BMP_DataOverflow,
    VVDImageDecodeError_BMP_Unsupported,
    VVDImageDecodeError_BMP_InvalidFormat,
    VVDImageDecodeError_BMP_DataTooSmall,
    VVDImageDecodeError_OutOfMemory,
} VVDImageDecodeError;

typedef struct _VVDImageDecodeContext
{
    VVDImageDecodeError error;
    const char* errorDescription;
    const void* decodedData;
    size_t decodedDataLength;
    VVDImageFormat imageFormat;
    VVDImagePixelFormat pixelFormat;
    uint32_t width;
    uint32_t height;
} VVDImageDecodeContext;

typedef enum _VVDImageEncodeError
{
    VVDImageEncodeError_Success = 0,
    VVDImageEncodeError_DataError,
    VVDImageEncodeError_InvalidFormat,
    VVDImageEncodeError_ImageIsTooLarge,
    VVDImageEncodeError_UnknownFormat,
    VVDImageEncodeError_UnsupportedPixelFormat,
    VVDImageEncodeError_OutOfMemory,
    VVDImageEncodeError_PNG_WriteError,
    VVDImageEncodeError_JPG_Error,
} VVDImageEncodeError;

typedef struct _VVDImageEncodeContext
{
    VVDImageEncodeError error;
    const char* errorDescription;
    const void* encodedData;
    size_t encodedDataLength;
    VVDImageFormat imageFormat;
    VVDImagePixelFormat pixelFormat;
} VVDImageEncodeContext;

#define VVDIMAGE_IDENTIFY_FORMAT_MINIMUM_LENGTH 8

uint32_t VVDImagePixelFormatBytesPerPixel(VVDImagePixelFormat);
VVDImageFormat VVDImageIdentifyImageFormatFromHeader(const void*, size_t);
VVDImageDecodeContext VVDImageDecodeFromMemory(const void*, size_t);
VVDImageEncodeContext VVDImageEncodeFromMemory(VVDImageFormat format, uint32_t width, uint32_t height, VVDImagePixelFormat pixelFormat, const void*, size_t);
VVDImagePixelFormat VVDImagePixelFormatEncodingSupported(VVDImageFormat, VVDImagePixelFormat);

void VVDImageReleaseDecodeContext(VVDImageDecodeContext*);
void VVDImageReleaseEncodeContext(VVDImageEncodeContext*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
