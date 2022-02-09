#include "DKImage.h"

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
