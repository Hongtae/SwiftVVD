/*******************************************************************************
 File: DKImage.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include "../libpng/png.h"
#include "../jpeg/jpeglib.h"
#include "DKImage.h"


#define JPEG_BUFFER_SIZE	4096
#define BMP_DEFAULT_PPM		96

#pragma pack(push, 1)
enum BMPCompression : uint32_t
{
    BMPCompressionRGB = 0L,
    BMPCompressionRLE8 = 1L,
    BMPCompressionRLE4 = 2L,
    BMPCompressionBITFIELDS = 3L,
};
struct BMPFileHeader // little-endian
{
    uint8_t b; // = 'B'
    uint8_t m; // = 'M'
    uint32_t size;
    uint16_t reserved1;
    uint16_t reserved2;
    uint32_t offBits;
};
struct BMPCoreHeader
{
    uint32_t size;
    uint16_t width;
    uint16_t height;
    uint16_t planes;
    uint16_t bitCount;
};
static_assert(sizeof(BMPFileHeader) == 14, "Wrong BMP header!");
static_assert(sizeof(BMPCoreHeader) == 12, "Wrong BMP header!");

struct BMPInfoHeader
{
    uint32_t size;
    int32_t width;
    int32_t height;
    uint16_t planes;
    uint16_t bitCount;
    uint32_t compression;
    uint32_t sizeImage;
    int32_t xPelsPerMeter;
    int32_t yPelsPerMeter;
    uint32_t clrUsed;
    uint32_t clrImportant;
};
#pragma pack(pop)

extern "C"
DKImageFormat DKImageIdentifyImageFormatFromHeader(const void*, size_t)
{
    return DKImageFormatUnknown;
}

extern "C"
DKImageDecodeContext* DKImageDecodeFromMemory(const void*, size_t)
{
    return nullptr;
}

extern "C"
DKImageEncodeContext* DKImageEncodeFromMemory(DKImageFormat format,
                                              uint32_t width,
                                              uint32_t height,
                                              DKImagePixelFormat pixelFormat,
                                              const void*,
                                              size_t)
{
    return nullptr;
}

extern "C"
void DKImageReleaseDecodeContext(DKImageDecodeContext* p)
{

}

extern "C"
void DKImageReleaseEncodeContext(DKImageEncodeContext* p)
{

}
