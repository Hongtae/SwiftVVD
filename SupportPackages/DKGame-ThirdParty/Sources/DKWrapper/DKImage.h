/*******************************************************************************
 File: DKImage.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef enum _DKImagePixelFormat
{
    DKImagePixelFormat_Invalid = 0,
    DKImagePixelFormat_R8,      /*   1 byte per pixel, uint8    */
    DKImagePixelFormat_RG8,     /*  2 bytes per pixel, uint8    */
    DKImagePixelFormat_RGB8,    /*  3 bytes per pixel, uint8    */
    DKImagePixelFormat_RGBA8,   /*  4 bytes per pixel, uint8    */
    DKImagePixelFormat_R16,     /*  2 bytes per pixel, uint16   */
    DKImagePixelFormat_RG16,    /*  4 bytes per pixel, uint16   */
    DKImagePixelFormat_RGB16,   /*  6 bytes per pixel, uint16   */
    DKImagePixelFormat_RGBA16,  /*  8 bytes per pixel, uint16   */
    DKImagePixelFormat_R32,     /*  4 bytes per pixel, uint32   */
    DKImagePixelFormat_RG32,    /*  8 bytes per pixel, uint32   */
    DKImagePixelFormat_RGB32,   /* 12 bytes per pixel, uint32   */
    DKImagePixelFormat_RGBA32,  /* 16 bytes per pixel, uint32   */
    DKImagePixelFormat_R32F,    /*  4 bytes per pixel, float32  */
    DKImagePixelFormat_RG32F,   /*  8 bytes per pixel, float32  */
    DKImagePixelFormat_RGB32F,  /* 12 bytes per pixel, float32  */
    DKImagePixelFormat_RGBA32F, /* 16 bytes per pixel, float32  */
} DKImagePixelFormat;

typedef enum _DKImageFormat
{
    DKImageFormat_Unknown = 0,
    DKImageFormat_PNG,
    DKImageFormat_JPEG,
    DKImageFormat_BMP
} DKImageFormat;

typedef enum _DKImageDecodeError
{
    DKImageDecodeError_Success = 0,
    DKImageDecodeError_DataError,
    DKImageDecodeError_UnknownFormat,
    DKImageDecodeError_PNG_Errror,
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
    DKImageEncodeError_DataError,
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
} DKImageEncodeContext;

#define DKIMAGE_IDENTIFY_FORMAT_MINIMUM_LENGTH 8

uint32_t DKImagePixelFormatBytesPerPixel(DKImagePixelFormat);
DKImageFormat DKImageIdentifyImageFormatFromHeader(const void*, size_t);
DKImageDecodeContext DKImageDecodeFromMemory(const void*, size_t);
DKImageEncodeContext DKImageEncodeFromMemory(DKImageFormat format, uint32_t width, uint32_t height, DKImagePixelFormat pixelFormat, const void*, size_t);
DKImagePixelFormat DKImagePixelFormatEncodingSupported(DKImageFormat, DKImagePixelFormat);

void DKImageReleaseDecodeContext(DKImageDecodeContext*);
void DKImageReleaseEncodeContext(DKImageEncodeContext*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
