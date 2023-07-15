/*******************************************************************************
 File: DKImage.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.

 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include <cstring>
#include <algorithm>
#include <vector>
#include "../libpng/png.h"
#include "../jpeg/jpeglib.h"
#include "DKImage.h"
#include "DKMalloc.h"
#include "DKEndianness.h"
#include "DKLog.h"

#define JPEG_BUFFER_SIZE 4096
#define BMP_DEFAULT_PPM 96

#pragma pack(push, 1)
enum BMPCompression : uint32_t
{
    BMPCompressionRGB = 0U,
    BMPCompressionRLE8 = 1U,
    BMPCompressionRLE4 = 2U,
    BMPCompressionBITFIELDS = 3U,
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

struct JpegErrorMgr
{
    struct jpeg_error_mgr pub;
    jmp_buf setjmpBuffer;
    char buffer[JMSG_LENGTH_MAX];
};

extern "C"
uint32_t DKImagePixelFormatBytesPerPixel(DKImagePixelFormat format)
{
    switch (format)
    {
    case DKImagePixelFormat_R8:       return 1;
    case DKImagePixelFormat_RG8:      return 2;
    case DKImagePixelFormat_RGB8:     return 3;
    case DKImagePixelFormat_RGBA8:    return 4;
    case DKImagePixelFormat_R16:      return 2;
    case DKImagePixelFormat_RG16:     return 4;
    case DKImagePixelFormat_RGB16:    return 6;
    case DKImagePixelFormat_RGBA16:   return 8;
    case DKImagePixelFormat_R32:      return 4;
    case DKImagePixelFormat_RG32:     return 8;
    case DKImagePixelFormat_RGB32:    return 12;
    case DKImagePixelFormat_RGBA32:   return 16;
    case DKImagePixelFormat_R32F:     return 4;
    case DKImagePixelFormat_RG32F:    return 8;
    case DKImagePixelFormat_RGB32F:   return 12;
    case DKImagePixelFormat_RGBA32F:  return 16;
    default:
        break;
    }
    return 0;
}

extern "C"
DKImageFormat DKImageIdentifyImageFormatFromHeader(const void * p, size_t s)
{
    if (p && s > 1)
    {
        const uint8_t* data = reinterpret_cast<const uint8_t*>(p);
        if (s >= sizeof(BMPFileHeader))
        {
            if (data[0] == 'B' && data[1] == 'M')
            {
                return DKImageFormat_BMP;
            }
        }
        if (s >= 8)
        {
            constexpr png_byte png_signature[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };
            bool png = true;
            for (int i = 0; i < 8; ++i)
            {
                if (png_signature[i] != data[i])
                {
                    png = false;
                    break;
                }
            }
            if (png)
            {
                return DKImageFormat_PNG;
            }
        }
        if (s > 3)
        {
            if (data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff)
            {
                return DKImageFormat_JPEG;
            }
        }
    }
    return DKImageFormat_Unknown;
}

extern "C"
DKImagePixelFormat DKImagePixelFormatEncodingSupported(DKImageFormat format,
                                                       DKImagePixelFormat pixelFormat)
{
    switch (format)
    {
    case DKImageFormat_PNG:
        switch (pixelFormat)
        {
        case DKImagePixelFormat_R8:
        case DKImagePixelFormat_RG8:
        case DKImagePixelFormat_RGB8:
        case DKImagePixelFormat_RGBA8:
        case DKImagePixelFormat_R16:
        case DKImagePixelFormat_RG16:
        case DKImagePixelFormat_RGB16:
        case DKImagePixelFormat_RGBA16:
            return pixelFormat;
            /* below formats are not able to encode directly, resample required */
        case DKImagePixelFormat_R32:
        case DKImagePixelFormat_R32F:
            return DKImagePixelFormat_R8;
        case DKImagePixelFormat_RG32:
        case DKImagePixelFormat_RG32F:
            return DKImagePixelFormat_RG8;
        case DKImagePixelFormat_RGB32:
        case DKImagePixelFormat_RGB32F:
            return DKImagePixelFormat_RGB8;
        case DKImagePixelFormat_RGBA32:
        case DKImagePixelFormat_RGBA32F:
            return DKImagePixelFormat_RGBA8;
        default:
            return DKImagePixelFormat_RGBA8;
        }
        break;
    case DKImageFormat_JPEG:
        switch (pixelFormat)
        {
        case DKImagePixelFormat_R8:
        case DKImagePixelFormat_R16:
        case DKImagePixelFormat_R32:
        case DKImagePixelFormat_R32F:
            return DKImagePixelFormat_R8;
        default:
            return DKImagePixelFormat_RGB8;
        }
        break;
    case DKImageFormat_BMP:
        switch (pixelFormat)
        {
        case DKImagePixelFormat_RGBA8:
        case DKImagePixelFormat_RGBA16:
        case DKImagePixelFormat_RGBA32:
        case DKImagePixelFormat_RGBA32F:
            return DKImagePixelFormat_RGBA8;
        default:
            return DKImagePixelFormat_RGB8;
        }
        break;
    default:
        break;
    }
    return DKImagePixelFormat_Invalid;
}

inline char* CopyString(const char* text)
{
    if (text && text[0])
    {
        size_t len = strlen(text);
        char* mesg = (char*)DKMalloc(len+2);
        if (mesg)
            return std::strncpy(mesg, text, len+2);
        if (mesg)
            DKFree((void*)mesg);
    }
    return nullptr;
}

static DKImageDecodeContext DecodePng(const void* p, size_t s)
{
    DKImageDecodeContext ctx = {DKImageDecodeError_DataError};

    png_image image = {};
    image.version = PNG_IMAGE_VERSION;
    if (png_image_begin_read_from_memory(&image, p, s))
    {
        DKImagePixelFormat pixelFormat = DKImagePixelFormat_Invalid;
        bool rgb = image.format & PNG_FORMAT_FLAG_COLOR;
        bool alpha = image.format & (PNG_FORMAT_FLAG_ALPHA | PNG_FORMAT_FLAG_AFIRST);
        bool linear = image.format & PNG_FORMAT_FLAG_LINEAR;

        if (linear)
        {
            if (alpha)
            {
                image.format = PNG_FORMAT_LINEAR_RGB_ALPHA;
                pixelFormat = DKImagePixelFormat_RGBA16;
            }
            else if (rgb)
            {
                image.format = PNG_FORMAT_LINEAR_RGB;
                pixelFormat = DKImagePixelFormat_RGB16;
            }
            else // gray
            {
                image.format = PNG_FORMAT_LINEAR_Y;
                pixelFormat = DKImagePixelFormat_R16;
            }
        }
        else
        {
            if (alpha)
            {
                image.format = PNG_FORMAT_RGBA;
                pixelFormat = DKImagePixelFormat_RGBA8;
            }
            else if (rgb)
            {
                image.format = PNG_FORMAT_RGB;
                pixelFormat = DKImagePixelFormat_RGB8;
            }
            else // gray
            {
                image.format = PNG_FORMAT_GRAY;
                pixelFormat = DKImagePixelFormat_R8;
            }
        }
        if (pixelFormat == DKImagePixelFormat_Invalid)
        {
            image.format = PNG_FORMAT_RGBA;
            pixelFormat = DKImagePixelFormat_RGBA8;
        }

        // bytes per channel
        size_t bpc = PNG_IMAGE_PIXEL_COMPONENT_SIZE(image.format);
        // bytes per pixel
        size_t bpp = PNG_IMAGE_PIXEL_CHANNELS(image.format) * bpc;

        size_t imageSize = PNG_IMAGE_SIZE(image);

        void* data = DKMalloc(imageSize);
        if (data == nullptr)
        {
            ctx.error = DKImageDecodeError_OutOfMemory;
        }
        else if (png_image_finish_read(&image, nullptr, data, 0, nullptr))
        {
            ctx.error = DKImageDecodeError_Success;
            ctx.decodedData = data;
            ctx.decodedDataLength = imageSize;
            ctx.imageFormat = DKImageFormat_PNG;
            ctx.pixelFormat = pixelFormat;
            ctx.width = image.width;
            ctx.height = image.height;
            return ctx;          
        }
        else 
        {
            ctx.errorDescription = CopyString(image.message);
            ctx.error = DKImageDecodeError_PNG_Errror;
        }
        DKFree(data);
        // failed!
        png_image_free(&image);
    }
    return ctx;
}

static DKImageDecodeContext DecodeJpeg(const void* p, size_t s)
{
    DKImageDecodeContext ctx = {DKImageDecodeError_DataError};

    jpeg_decompress_struct cinfo = {};
    JpegErrorMgr err = {};
    struct JpegSource
    {
        struct jpeg_source_mgr pub;
        const uint8_t* data;
        size_t length;
        uint8_t eofMarker[2];
    };
    JpegSource source;
    source.data = reinterpret_cast<const uint8_t*>(p);
    source.length = s;
    source.pub.bytes_in_buffer = 0;
    source.pub.next_input_byte = NULL;
    source.pub.init_source = [](j_decompress_ptr cinfo) {};
    source.pub.fill_input_buffer = [](j_decompress_ptr cinfo)->boolean
    {
        JpegSource* src = reinterpret_cast<JpegSource*>(cinfo->src);
        if (src->length > 0)
        {
            src->pub.next_input_byte = (const JOCTET*)src->data;
            size_t s = std::min(src->length, size_t(JPEG_BUFFER_SIZE));
            src->pub.bytes_in_buffer = s;
            src->length -= s;
            src->data += s;
        }
        else
        {
            src->pub.next_input_byte = (const JOCTET*)src->eofMarker;
            src->eofMarker[0] = 0xff;
            src->eofMarker[1] = JPEG_EOI;
            src->pub.bytes_in_buffer = 2;
        }
        return TRUE;
    };
    source.pub.skip_input_data = [](j_decompress_ptr cinfo, long numBytes)
    {
        if (numBytes > 0)
        {
            JpegSource* src = reinterpret_cast<JpegSource*>(cinfo->src);
            while (numBytes > (long)src->pub.bytes_in_buffer)
            {
                numBytes -= (long)src->pub.bytes_in_buffer;
                src->pub.fill_input_buffer(cinfo);
            }
            src->pub.next_input_byte += (size_t)numBytes;
            src->pub.bytes_in_buffer -= (size_t)numBytes;

        }
    };
    source.pub.term_source = [](j_decompress_ptr cinfo) {};

    cinfo.err = jpeg_std_error(&err.pub);
    err.pub.error_exit = [](j_common_ptr cinfo)
    {
        JpegErrorMgr* err = (JpegErrorMgr*)cinfo->err;
        err->pub.format_message(cinfo, err->buffer);
        longjmp(err->setjmpBuffer, 1);
    };

    if (setjmp(err.setjmpBuffer))
    {
        ctx.error = DKImageDecodeError_JPEG_Error;
        ctx.errorDescription = CopyString(err.buffer);
        jpeg_destroy_decompress(&cinfo);
        return ctx;
    }
    jpeg_create_decompress(&cinfo);
    cinfo.src = (jpeg_source_mgr*)&source;
    jpeg_read_header(&cinfo, TRUE);

    int32_t bytesPerPixel;
    if (cinfo.out_color_space == JCS_CMYK || cinfo.out_color_space == JCS_YCCK)
    {
        cinfo.out_color_space = JCS_CMYK;
        bytesPerPixel = 4;
    }
    else
    {
        cinfo.out_color_space = JCS_RGB;
        bytesPerPixel = 3;
    }
    jpeg_start_decompress(&cinfo);

    uint32_t rowStride = cinfo.image_width * 3; /* RGB8 = 3 (packed) */
    size_t imageSize = size_t(rowStride) * cinfo.image_height; 
    uint8_t* data = (uint8_t*)DKMalloc(imageSize);
    if (data)
    {
        uint8_t* ptr = data;
        if (cinfo.out_color_space == JCS_RGB)
        {
            JSAMPARRAY buffer = (*cinfo.mem->alloc_sarray)
                ((j_common_ptr)&cinfo, JPOOL_IMAGE, rowStride, 1);
            while (cinfo.output_scanline < cinfo.output_height)
            {
                jpeg_read_scanlines(&cinfo, buffer, 1);
                memcpy(ptr, buffer[0], rowStride);
                ptr += rowStride;
            }
        }
        else
        {
            JSAMPARRAY buffer = (*cinfo.mem->alloc_sarray)
                ((j_common_ptr)&cinfo, JPOOL_IMAGE, cinfo.image_width * 4, 1);
            auto CmykToRgb = [](uint8_t* rgb, uint8_t* cmyk)
            {
                uint32_t k1 = 255 - cmyk[3];
                uint32_t k2 = cmyk[3];
                for (int i = 0; i < 3; ++i)
                {
                    uint32_t c = k1 + k2 * (255 - cmyk[i]) / 255;
                    rgb[i] = (c > 255) ? 0 : (255 - c);
                }
            };
            while (cinfo.output_scanline < cinfo.output_height)
            {
                jpeg_read_scanlines(&cinfo, buffer, 1);
                uint8_t* input = (uint8_t*)buffer[0];
                for (size_t i = 0; i < cinfo.output_width; ++i)
                {
                    CmykToRgb(ptr, input);
                    ptr += 3;
                    input += 4;
                }
            }
        }
        ctx.error = DKImageDecodeError_Success;
        ctx.decodedData = data;
        ctx.decodedDataLength = imageSize;
        ctx.imageFormat = DKImageFormat_JPEG;
        ctx.pixelFormat = DKImagePixelFormat_RGB8;
        ctx.width = cinfo.image_width;
        ctx.height = cinfo.image_height;
    }
    else
    {
        ctx.error = DKImageDecodeError_OutOfMemory;
    }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    return ctx;
}

static DKImageDecodeContext DecodeBmp(const void* p, size_t s)
{
    DKImageDecodeContext ctx = {DKImageDecodeError_DataError};

    if (s > sizeof(BMPFileHeader) + sizeof(BMPCoreHeader))
    {
        auto CheckOverflow = [s](size_t pos)->bool
        {
            if (s < pos)
            {
                DKLogE("[DKImage::Create] Error: BMP data overflow!\n");
                return false;
            }
            return true;
        };

        const uint8_t* data = reinterpret_cast<const uint8_t*>(p);
        size_t pos = 0;
        BMPFileHeader fileHeader = *reinterpret_cast<const BMPFileHeader*>(data);
        fileHeader.size = DKLittleEndianToSystem(fileHeader.size);
        fileHeader.offBits = DKLittleEndianToSystem(fileHeader.offBits);
        if (!CheckOverflow(fileHeader.size) || !CheckOverflow(fileHeader.offBits))
        {
            ctx.error = DKImageDecodeError_BMP_DataOverflow;
            return ctx;
        }

        pos += sizeof(BMPFileHeader);
        size_t headerSize = DKLittleEndianToSystem(reinterpret_cast<const BMPCoreHeader*>(&data[pos])->size);

        if (!CheckOverflow(pos + headerSize))
        {
            ctx.error = DKImageDecodeError_BMP_DataOverflow;
            return ctx;            
        }

        size_t colorTableEntrySize;
        BMPInfoHeader info = {};
        if (headerSize >= sizeof(BMPInfoHeader))
        {
            info = *reinterpret_cast<const BMPInfoHeader*>(&data[pos]);
            info.size = DKLittleEndianToSystem(info.size);
            info.width = DKLittleEndianToSystem(info.width);
            info.height = DKLittleEndianToSystem(info.height);
            info.planes = DKLittleEndianToSystem(info.planes);
            info.bitCount = DKLittleEndianToSystem(info.bitCount);
            info.compression = DKLittleEndianToSystem(info.compression);
            info.sizeImage = DKLittleEndianToSystem(info.sizeImage);
            info.xPelsPerMeter = DKLittleEndianToSystem(info.xPelsPerMeter);
            info.yPelsPerMeter = DKLittleEndianToSystem(info.yPelsPerMeter);
            info.clrUsed = DKLittleEndianToSystem(info.clrUsed);
            info.clrImportant = DKLittleEndianToSystem(info.clrImportant);
            colorTableEntrySize = 4; // RGBA
        }
        else if (headerSize >= sizeof(BMPCoreHeader))
        {
            const BMPCoreHeader& core = *reinterpret_cast<const BMPCoreHeader*>(&data[pos]);
            info.size = DKLittleEndianToSystem(core.size);
            info.width = DKLittleEndianToSystem(core.width);
            info.height = DKLittleEndianToSystem(core.height);
            info.planes = DKLittleEndianToSystem(core.planes);
            info.bitCount = DKLittleEndianToSystem(core.bitCount);
            info.compression = BMPCompressionRGB;
            info.sizeImage = 0;
            info.xPelsPerMeter = BMP_DEFAULT_PPM;
            info.yPelsPerMeter = BMP_DEFAULT_PPM;
            info.clrUsed = 0;
            info.clrImportant = 0;
            colorTableEntrySize = 3; // old-style
        }
        else
        {
            ctx.error = DKImageDecodeError_BMP_Unsupported;
            return ctx;
        }
        if (info.bitCount != 1 && info.bitCount != 4 && info.bitCount != 8 &&
            info.bitCount != 16 && info.bitCount != 24 && info.bitCount != 32)
        {
            ctx.error = DKImageDecodeError_BMP_Unsupported;
            return ctx;
        }
        if ((info.compression == BMPCompressionRLE4 && info.bitCount != 4) ||
            (info.compression == BMPCompressionRLE8 && info.bitCount != 8) ||
            (info.compression == BMPCompressionBITFIELDS && (info.bitCount != 16 && info.bitCount != 32)))
        {
            ctx.error = DKImageDecodeError_BMP_InvalidFormat;
            return ctx;
        }
        bool topDown = info.height < 0;
        if (topDown)
            info.height = -info.height;

        if (info.width <= 0 || info.height <= 0)
        {
            ctx.error = DKImageDecodeError_BMP_InvalidFormat;
            return ctx;
        }
        pos += info.size; // set position to color-table map (if available)

        if ((info.compression == BMPCompressionRLE8) || (info.compression == BMPCompressionRLE4))
        {
            size_t imageSize = size_t(info.width) * size_t(info.height) * 3; /* RGB8 = 3 */
            uint8_t* output = (uint8_t*)DKMalloc(imageSize);
            if (output == nullptr)
            {
                ctx.error = DKImageDecodeError_OutOfMemory;
                return ctx;
            }   

            const uint8_t* colorTableEntries = &data[pos];

            // set background color to first color-table entry
            for (size_t i = 0, n = info.width * info.height * 3; i < n; ++i)
                output[i] = colorTableEntries[2 - (i % 3)];

            auto SetPixelAtPosition = [&](int32_t x, int32_t y, uint8_t index)
            {
                if (x < info.width && y < info.height)
                {
                    if (!topDown)
                        y = info.height - y - 1;

                    // DKASSERT_DEBUG(index < (1 << info.bitCount));
                    uint8_t* data = &output[(y * info.width + x) * 3];
                    const uint8_t* cm = &colorTableEntries[uint32_t(4) * uint32_t(index)];
                    data[0] = cm[2];
                    data[1] = cm[1];
                    data[2] = cm[0];
                }
            };
            // set position to bitmap data
            pos = fileHeader.offBits;
            int32_t x = 0;
            int32_t y = 0;
            while ((pos + 1) < s && y < info.height)
            {
                uint32_t first = data[pos++];
                uint32_t second = data[pos++];
                if (first == 0)
                {
                    switch (second)
                    {
                    case 0:     // end of line
                        x = 0;
                        y++;
                        break;
                    case 1:     // end of bitmap
                        y = info.height;
                        break;
                    case 2:     // move position 
                        if (pos + 1 < s)
                        {
                            uint8_t deltaX = data[pos++];
                            uint8_t deltaY = data[pos++];
                            x += deltaX / (8 / info.bitCount);
                            y += deltaY;
                        }
                        break;
                    default:    // absolute mode.
                        if (info.compression == BMPCompressionRLE8)
                        {
                            for (uint32_t i = 0; i < second && pos < s && x < info.width; ++i)
                            {
                                uint8_t index = data[pos++];
                                SetPixelAtPosition(x++, y, index);
                            }
                            if (second & 1)
                                pos++;
                        }
                        else
                        {
                            uint8_t nibble[2];
                            uint32_t bytesRead = 0;
                            for (uint32_t i = 0; i < second && pos < s && x < info.width; ++i)
                            {
                                if (!(i % 2))
                                {
                                    bytesRead++;
                                    uint8_t index = data[pos++];
                                    nibble[0] = (index >> 4) & 0xf;
                                    nibble[1] = index & 0xf;
                                }
                                SetPixelAtPosition(x++, y, nibble[i % 2]);
                            }
                            if (bytesRead & 1)
                                pos++;
                        }
                        break;
                    }
                }
                else
                {
                    if (info.compression == BMPCompressionRLE8)
                    {
                        while (first > 0 && x < info.width)
                        {
                            SetPixelAtPosition(x++, y, second);
                            first--;
                        }
                    }
                    else
                    {
                        while (first > 0 && x < info.width)
                        {
                            uint8_t h = (second >> 4) & 0xf;
                            SetPixelAtPosition(x++, y, h);
                            first--;
                            if (first > 1)
                            {
                                uint8_t l = second & 0xf;
                                SetPixelAtPosition(x++, y, l);
                                first--;
                            }
                        }
                    }
                }
            }
            ctx.error = DKImageDecodeError_Success;
            ctx.decodedData = output;
            ctx.decodedDataLength = imageSize;
            ctx.imageFormat = DKImageFormat_BMP;
            ctx.pixelFormat = DKImagePixelFormat_RGB8;
            ctx.width = info.width;
            ctx.height = info.height;
            return ctx;
        }
        else
        {
            uint32_t rowBytes = info.width * info.bitCount;
            if (rowBytes % 8)
                rowBytes = rowBytes / 8 + 1;
            else
                rowBytes = rowBytes / 8;
            // each row must be align of 4-bytes
            size_t rowBytesAligned = (rowBytes % 4) ? (rowBytes | 0x3) + 1 : rowBytes;

            size_t requiredBytes = rowBytesAligned * (info.height - 1) + rowBytes;

            if (!CheckOverflow(fileHeader.offBits + requiredBytes))
            {
                ctx.error = DKImageDecodeError_BMP_DataOverflow;
                return ctx;                
            }

            const uint8_t* bitmapData = &data[fileHeader.offBits];

            if (info.compression == BMPCompressionBITFIELDS)
            {
                uint32_t bitMask[3] = {
                    DKLittleEndianToSystem(reinterpret_cast<const uint32_t*>(&data[pos])[0]),
                    DKLittleEndianToSystem(reinterpret_cast<const uint32_t*>(&data[pos])[1]),
                    DKLittleEndianToSystem(reinterpret_cast<const uint32_t*>(&data[pos])[2])
                };
                uint32_t bitShift[3] = { 0, 0, 0 };
                uint32_t numBits[3] = { 0, 0, 0 };

                for (int bit = 31; bit >= 0; --bit)
                {
                    for (int i = 0; i < 3; ++i)
                    {
                        if (bitMask[i] & (1U << bit))
                            bitShift[i] = bit;
                    }
                }
                for (int i = 0; i < 3; ++i)
                    bitMask[i] = bitMask[i] >> bitShift[i];

                for (int bit = 0; bit < 32; ++bit)
                {
                    for (int i = 0; i < 3; ++i)
                    {
                        if (bitMask[i] & (1U << bit))
                            numBits[i] = bit + 1;
                    }
                }
                if (numBits[0] <= 8 && numBits[1] <= 8 && numBits[2] <= 8) // RGB8
                {
                    uint32_t lshift[3] = { 8 - numBits[0], 8 - numBits[1], 8 - numBits[2] };

                    size_t imageSize = size_t(info.width) * size_t(info.height) * 3;
                    uint8_t* output = (uint8_t*)DKMalloc(imageSize);
                    if (output == nullptr)
                    {
                        ctx.error = DKImageDecodeError_OutOfMemory;
                        return ctx;
                    }

                    if (info.bitCount == 32)
                    {
                        auto SetRowPixels = [&](uint8_t*& output, const uint32_t* input, uint32_t width)
                        {
                            for (uint32_t x = 0; x < width; ++x)
                            {
                                uint32_t rgb = DKLittleEndianToSystem(*input);
                                for (int i = 0; i < 3; ++i)
                                {
                                    output[0] = ((rgb >> bitShift[i]) & bitMask[i]) << lshift[i];
                                    output++;
                                }
                                input++;
                            }
                        };
                        if (topDown)
                        {
                            for (int32_t y = 0; y < info.height; ++y)
                            {
                                const uint32_t* row = reinterpret_cast<const uint32_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                        else
                        {
                            for (int32_t y = info.height - 1; y >= 0; --y)
                            {
                                const uint32_t* row = reinterpret_cast<const uint32_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                    }
                    else // 16
                    {
                        auto SetRowPixels = [&](uint8_t*& output, const uint16_t* input, uint32_t width)
                        {
                            for (uint32_t x = 0; x < width; ++x)
                            {
                                uint16_t rgb = DKLittleEndianToSystem(*input);
                                for (int i = 0; i < 3; ++i)
                                {
                                    output[0] = ((rgb >> bitShift[i]) & bitMask[i]) << lshift[i];
                                    output++;
                                }
                                input++;
                            }
                        };
                        if (topDown)
                        {
                            for (int32_t y = 0; y < info.height; ++y)
                            {
                                const uint16_t* row = reinterpret_cast<const uint16_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                        else
                        {
                            for (int32_t y = info.height - 1; y >= 0; --y)
                            {
                                const uint16_t* row = reinterpret_cast<const uint16_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                    }
                    ctx.error = DKImageDecodeError_Success;
                    ctx.decodedData = output;
                    ctx.decodedDataLength = imageSize;
                    ctx.imageFormat = DKImageFormat_BMP;
                    ctx.pixelFormat = DKImagePixelFormat_RGB8;
                    ctx.width = info.width;
                    ctx.height = info.height;
                    return ctx;
                }
                else // RGB32F
                {
                    size_t bytesPerPixel = DKImagePixelFormatBytesPerPixel(DKImagePixelFormat_RGB32F);
                    size_t imageSize = size_t(info.width) * size_t(info.height) * bytesPerPixel;
                    float* output = (float*)DKMalloc(imageSize);
                    if (output == nullptr)
                    {
                        ctx.error = DKImageDecodeError_OutOfMemory;
                        return ctx;
                    }

                    float denum[3] = {
                        static_cast<float>(bitMask[0]),
                        static_cast<float>(bitMask[1]),
                        static_cast<float>(bitMask[2])
                    };

                    if (info.bitCount == 32)
                    {
                        auto SetRowPixels = [&](float*& output, const uint32_t* input, uint32_t width)
                        {
                            for (uint32_t x = 0; x < width; ++x)
                            {
                                uint32_t rgb = DKLittleEndianToSystem(*input);
                                for (int i = 0; i < 3; ++i)
                                {
                                    if (denum[i] != 0.0f)
                                        output[0] = static_cast<float>((rgb >> bitShift[i]) & bitMask[i]) / denum[i];
                                    else
                                        output[0] = 0.0f;
                                    output++;
                                }
                                input++;
                            }
                        };
                        if (topDown)
                        {
                            for (int32_t y = 0; y < info.height; ++y)
                            {
                                const uint32_t* row = reinterpret_cast<const uint32_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                        else
                        {
                            for (int32_t y = info.height - 1; y >= 0; --y)
                            {
                                const uint32_t* row = reinterpret_cast<const uint32_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                    }
                    else // 16
                    {
                        auto SetRowPixels = [&](float*& output, const uint16_t* input, uint32_t width)
                        {
                            for (uint32_t x = 0; x < width; ++x)
                            {
                                uint16_t rgb = DKLittleEndianToSystem(*input);
                                for (int i = 0; i < 3; ++i)
                                {
                                    if (denum[i] != 0.0f)
                                        output[0] = static_cast<float>((rgb >> bitShift[i]) & bitMask[i]) / denum[i];
                                    else
                                        output[0] = 0.0f;
                                    output++;
                                }
                                input++;
                            }
                        };
                        if (topDown)
                        {
                            for (int32_t y = 0; y < info.height; ++y)
                            {
                                const uint16_t* row = reinterpret_cast<const uint16_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                        else
                        {
                            for (int32_t y = info.height - 1; y >= 0; --y)
                            {
                                const uint16_t* row = reinterpret_cast<const uint16_t*>(&bitmapData[rowBytesAligned * y]);
                                SetRowPixels(output, row, info.width);
                            }
                        }
                    }
                    ctx.error = DKImageDecodeError_Success;
                    ctx.decodedData = output;
                    ctx.decodedDataLength = imageSize;
                    ctx.imageFormat = DKImageFormat_BMP;
                    ctx.pixelFormat = DKImagePixelFormat_RGB32F;
                    ctx.width = info.width;
                    ctx.height = info.height;
                    return ctx;
                }
            }
            else if (info.bitCount == 32 || info.bitCount == 24)
            {
                DKImagePixelFormat pixelFormat = DKImagePixelFormat_RGB8;
                if (info.bitCount == 32)
                    pixelFormat = DKImagePixelFormat_RGBA8;
                // size_t bpp = DKImagePixelFormatBytesPerPixel(pixelFormat);
                int32_t bpp = info.bitCount / 8;
                size_t imageSize = size_t(info.width) * size_t(info.height) * bpp;
                uint8_t* output = (uint8_t*)DKMalloc(imageSize);
                if (output == nullptr)
                {
                    ctx.error = DKImageDecodeError_OutOfMemory;
                    return ctx;
                }
                const uint32_t colorIndices[] = { 2, 1, 0, 3 }; // BGRA -> RGBA

                auto SetRowPixels = [&](uint8_t*& output, const uint8_t* input, uint32_t width, uint8_t bpp)
                {
                    for (uint32_t x = 0; x < width; ++x)
                    {
                        for (int32_t i = 0; i < bpp; ++i)
                            output[i] = input[colorIndices[i]];
                        output += bpp;
                        input += bpp;
                    }
                };

                if (topDown)
                {
                    for (int32_t y = 0; y < info.height; ++y)
                    {
                        const uint8_t* row = &bitmapData[rowBytesAligned * y];
                        SetRowPixels(output, row, info.width, bpp);
                    }
                }
                else
                {
                    for (int32_t y = info.height - 1; y >= 0; --y)
                    {
                        const uint8_t* row = &bitmapData[rowBytesAligned * y];
                        SetRowPixels(output, row, info.width, bpp);
                    }
                }
                ctx.error = DKImageDecodeError_Success;
                ctx.decodedData = output;
                ctx.decodedDataLength = imageSize;
                ctx.imageFormat = DKImageFormat_BMP;
                ctx.pixelFormat = pixelFormat;
                ctx.width = info.width;
                ctx.height = info.height;
                return ctx;
            }
            else if (info.bitCount == 16)
            {
                size_t imageSize = size_t(info.width) * size_t(info.height) * 3;
                uint8_t* output = (uint8_t*)DKMalloc(imageSize);
                if (output == nullptr)
                {
                    ctx.error = DKImageDecodeError_OutOfMemory;
                    return ctx;
                }

                auto SetRowPixels = [&](uint8_t*& output, const uint16_t* input, uint32_t width)
                {
                    for (uint32_t x = 0; x < width; ++x)
                    {
                        uint16_t pixel = DKLittleEndianToSystem(*input);
                        uint16_t r = (pixel & 0x7c00) >> 10;
                        uint16_t g = (pixel & 0x03e0) >> 5;
                        uint16_t b = (pixel & 0x001f);

                        output[0] = static_cast<uint8_t>((r << 3) & 0xff);
                        output[1] = static_cast<uint8_t>((g << 3) & 0xff);
                        output[2] = static_cast<uint8_t>((b << 3) & 0xff);

                        output += 3;
                        input++;
                    }
                };
                if (topDown)
                {
                    for (int32_t y = 0; y < info.height; ++y)
                    {
                        const uint16_t* row = reinterpret_cast<const uint16_t*>(&bitmapData[rowBytesAligned * y]);
                        SetRowPixels(output, row, info.width);
                    }
                }
                else
                {
                    for (int32_t y = info.height - 1; y >= 0; --y)
                    {
                        const uint16_t* row = reinterpret_cast<const uint16_t*>(&bitmapData[rowBytesAligned * y]);
                        SetRowPixels(output, row, info.width);
                    }
                }
                ctx.error = DKImageDecodeError_Success;
                ctx.decodedData = output;
                ctx.decodedDataLength = imageSize;
                ctx.imageFormat = DKImageFormat_BMP;
                ctx.pixelFormat = DKImagePixelFormat_RGB8;
                ctx.width = info.width;
                ctx.height = info.height;
                return ctx;
            }
            else // 1, 4, 8
            {
                size_t imageSize = size_t(info.width) * size_t(info.height) * 3;
                uint8_t* output = (uint8_t*)DKMalloc(imageSize);
                if (output == nullptr)
                {
                    ctx.error = DKImageDecodeError_OutOfMemory;
                    return ctx;
                }

                auto SetPixelFromCMap = [&](uint8_t index, uint8_t* output)
                {
                    const uint8_t* colorTableEntries = &data[pos];
                    // DKASSERT_DEBUG(index < (1 << info.bitCount));
                    const uint8_t* c = &colorTableEntries[uint32_t(colorTableEntrySize) * uint32_t(index)];
                    output[0] = c[2];
                    output[1] = c[1];
                    output[2] = c[0];
                };
                auto SetRowPixels = [&](uint8_t*& output, const uint8_t* input, size_t width, uint16_t bits, uint8_t mask)
                {
                    int32_t x = 0;
                    while (x < width)
                    {
                        uint8_t c = *input;
                        for (int32_t bit = 0; bit < 8 && x < width; ++x)
                        {
                            bit += bits;
                            uint8_t index = (c >> (8 - bit)) & mask;
                            SetPixelFromCMap(index, output);
                            output += 3; //RGB8
                        }
                        input++;
                    }
                    // DKASSERT_DEBUG(x == width);
                };

                uint8_t pixelMask = (1 << info.bitCount) - 1;

                if (topDown)
                {
                    for (int32_t y = 0; y < info.height;++y)
                    {
                        const uint8_t* row = &bitmapData[rowBytesAligned * y];
                        SetRowPixels(output, row, info.width, info.bitCount, pixelMask);
                    }
                }
                else
                {
                    for (int32_t y = info.height - 1; y >= 0; --y)
                    {
                        const uint8_t* row = &bitmapData[rowBytesAligned * y];
                        SetRowPixels(output, row, info.width, info.bitCount, pixelMask);
                    }
                }
                ctx.error = DKImageDecodeError_Success;
                ctx.decodedData = output;
                ctx.decodedDataLength = imageSize;
                ctx.imageFormat = DKImageFormat_BMP;
                ctx.pixelFormat = DKImagePixelFormat_RGB8;
                ctx.width = info.width;
                ctx.height = info.height;
                return ctx;
            }
        }
    }
    else
    {
        ctx.error = DKImageDecodeError_BMP_DataTooSmall;
    }
    return ctx;
}

static DKImageEncodeContext EncodePng(uint32_t width,
                                      uint32_t height,
                                      DKImagePixelFormat pixelFormat,
                                      const void* data)
{
    DKImageEncodeContext ctx = {DKImageEncodeError_DataError};

    if (DKImagePixelFormatEncodingSupported(DKImageFormat_PNG, pixelFormat) != pixelFormat)
    {
        // resample required
        ctx.error = DKImageEncodeError_UnsupportedPixelFormat;
        return ctx;
    }

    png_uint_32 pngFormat;
    switch (pixelFormat)
    {
    case DKImagePixelFormat_R8:
        pngFormat = PNG_FORMAT_GRAY;
        break;
    case DKImagePixelFormat_RG8:
        pngFormat = PNG_FORMAT_GA;
        break;
    case DKImagePixelFormat_RGB8:
        pngFormat = PNG_FORMAT_RGB;
        break;
    case DKImagePixelFormat_RGBA8:
        pngFormat = PNG_FORMAT_RGBA;
        break;
    case DKImagePixelFormat_R16:
        pngFormat = PNG_FORMAT_LINEAR_Y;
        break;
    case DKImagePixelFormat_RG16:
        pngFormat = PNG_FORMAT_LINEAR_Y_ALPHA;
        break;
    case DKImagePixelFormat_RGB16:
        pngFormat = PNG_FORMAT_LINEAR_RGB;
        break;
    case DKImagePixelFormat_RGBA16:
        pngFormat = PNG_FORMAT_LINEAR_RGB_ALPHA;
        break;
    default:
        ctx.error = DKImageEncodeError_UnsupportedPixelFormat;
        return ctx;
    }

    png_image image = {};
    image.version = PNG_IMAGE_VERSION;
    image.width = width;
    image.height = height;
    image.format = pngFormat;

    png_alloc_size_t bufferSize = 0;
    if (png_image_write_get_memory_size(image, bufferSize, 0, data, 0, nullptr) &&
        bufferSize > 0)
    {
        void* output = DKMalloc(bufferSize);
        if (output)
        {
            if (png_image_write_to_memory(&image, output, &bufferSize, 0, data, 0, nullptr))
            {
                ctx.encodedData = output;
                ctx.encodedDataLength = bufferSize;
                ctx.imageFormat = DKImageFormat_PNG;
                ctx.pixelFormat = pixelFormat;
                return ctx;
            }
            else 
            {
                DKFree(output);
                ctx.error = DKImageEncodeError_PNG_WriteError;
                ctx.errorDescription = CopyString(image.message);
            }
        }
        else
        {
            ctx.error = DKImageEncodeError_OutOfMemory;
        }
    }
    return ctx;
}

static DKImageEncodeContext EncodeJpeg(uint32_t width,
                                       uint32_t height,
                                       DKImagePixelFormat pixelFormat,
                                       const void* data)
{
    DKImageEncodeContext ctx = {DKImageEncodeError_DataError};

    if (DKImagePixelFormatEncodingSupported(DKImageFormat_JPEG, pixelFormat) != pixelFormat)
    {
        // resample required
        ctx.error = DKImageEncodeError_UnsupportedPixelFormat;
        return ctx;
    }

    switch (pixelFormat)
    {
    case DKImagePixelFormat_R8:
    case DKImagePixelFormat_RGB8:
        break;
    default:
        ctx.error = DKImageEncodeError_UnsupportedPixelFormat;
        return ctx;
    }

    struct JpegDestination
    {
        struct jpeg_destination_mgr pub;
        JOCTET* buffer;
        std::vector<uint8_t> encoded;
    };

    jpeg_compress_struct cinfo = {};
    JpegErrorMgr err = {};
    JpegDestination dest;

    dest.pub.init_destination = [](j_compress_ptr cinfo)
    {
        JpegDestination* dest = reinterpret_cast<JpegDestination*>(cinfo->dest);
        dest->buffer = (JOCTET*)(*cinfo->mem->alloc_small)((j_common_ptr)cinfo,
                                                            JPOOL_IMAGE,
                                                            JPEG_BUFFER_SIZE * sizeof(JOCTET));
        dest->pub.next_output_byte = dest->buffer;
        dest->pub.free_in_buffer = JPEG_BUFFER_SIZE;
    };
    dest.pub.empty_output_buffer = [](j_compress_ptr cinfo)->boolean
    {
        JpegDestination* dest = reinterpret_cast<JpegDestination*>(cinfo->dest);
        dest->encoded.insert(dest->encoded.end(), &dest->buffer[0], &dest->buffer[JPEG_BUFFER_SIZE]);
        dest->pub.next_output_byte = dest->buffer;
        dest->pub.free_in_buffer = JPEG_BUFFER_SIZE;
        return TRUE;
    };
    dest.pub.term_destination = [](j_compress_ptr cinfo)
    {
        JpegDestination* dest = reinterpret_cast<JpegDestination*>(cinfo->dest);
        size_t length = JPEG_BUFFER_SIZE - dest->pub.free_in_buffer;
        if (length > 0)
            dest->encoded.insert(dest->encoded.end(), &dest->buffer[0], &dest->buffer[length]);
    };

    JSAMPLE* buffer;
    int32_t rowStride;

    cinfo.err = jpeg_std_error(&err.pub);
    err.pub.error_exit = [](j_common_ptr cinfo)
    {
        JpegErrorMgr* err = (JpegErrorMgr*)cinfo->err;
        err->pub.format_message(cinfo, err->buffer);
        longjmp(err->setjmpBuffer, 1);
    };

    if (setjmp(err.setjmpBuffer))
    {
        ctx.error = DKImageEncodeError_JPG_Error;
        ctx.errorDescription = CopyString(err.buffer);
        jpeg_destroy_compress(&cinfo);
        return ctx;
    }

    jpeg_create_compress(&cinfo);

    cinfo.dest = (jpeg_destination_mgr*)&dest;

    cinfo.image_width = width;
    cinfo.image_height = height;
    if (pixelFormat == DKImagePixelFormat_RGB8)
    {
        cinfo.input_components = 3;
        cinfo.in_color_space = JCS_RGB;
        rowStride = width * 3; // bytesPerPixel = 3
    }
    else // DKImagePixelFormat_R8
    {
        cinfo.input_components = 1;
        cinfo.in_color_space = JCS_GRAYSCALE;
        rowStride = width * 1; // bytesPerPixel = 1
    }

    jpeg_set_defaults(&cinfo);
    //jpeg_set_quality(&cinfo, 75, true);

    jpeg_start_compress(&cinfo, TRUE);
    buffer = (JSAMPLE*)(data);
    JSAMPROW row[1];
    while (cinfo.next_scanline < cinfo.image_height)
    {
        row[0] = &buffer[cinfo.next_scanline * rowStride];
        jpeg_write_scanlines(&cinfo, row, 1);
    }
    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);

    void* output = DKMalloc(dest.encoded.size());
    if (output)
    {
        memcpy(output, dest.encoded.data(), dest.encoded.size());
        ctx.error = DKImageEncodeError_Success;
        ctx.encodedData = output;
        ctx.encodedDataLength = dest.encoded.size();
        ctx.imageFormat = DKImageFormat_JPEG;
        ctx.pixelFormat = pixelFormat;
        return ctx;
    }
    ctx.error = DKImageEncodeError_OutOfMemory;
    return ctx;
}

static DKImageEncodeContext EncodeBmp(uint32_t width,
                                      uint32_t height,
                                      DKImagePixelFormat pixelFormat,
                                      const void* data)
{
    DKImageEncodeContext ctx = {DKImageEncodeError_DataError};

    if (DKImagePixelFormatEncodingSupported(DKImageFormat_BMP, pixelFormat) != pixelFormat)
    {
        // resample required
        ctx.error = DKImageEncodeError_UnsupportedPixelFormat;
        return ctx;
    }

    switch (pixelFormat)
    {
    case DKImagePixelFormat_RGB8:
    case DKImagePixelFormat_RGBA8:
        break;
    default:
        ctx.error = DKImageEncodeError_UnsupportedPixelFormat;
        return ctx;
    }

    size_t bytesPerPixel = DKImagePixelFormatBytesPerPixel(pixelFormat);
    // DKASSERT_DEBUG(bytesPerPixel == 3 || bytesPerPixel == 4);

    size_t rowBytes = bytesPerPixel * width;
    if (rowBytes % 4)
        rowBytes = (rowBytes | 0x3) + 1;
    size_t imageSize = rowBytes * height;
    size_t dataSize = sizeof(BMPFileHeader) + sizeof(BMPInfoHeader) + imageSize;

    void* output = DKMalloc(dataSize);
    if (output)
    {
        uint16_t bitCount = uint16_t(bytesPerPixel) * 8;

        uint8_t* buffer = reinterpret_cast<uint8_t*>(output);
        BMPFileHeader* header = reinterpret_cast<BMPFileHeader*>(buffer);   buffer += sizeof(BMPFileHeader);
        BMPInfoHeader* info = reinterpret_cast<BMPInfoHeader*>(buffer);     buffer += sizeof(BMPInfoHeader);

        size_t fileSize = sizeof(BMPFileHeader) + sizeof(BMPInfoHeader) + imageSize;
        header->b = 'B'; header->m = 'M';
        header->size = DKSystemToLittleEndian<uint32_t>(uint32_t(fileSize));
        header->reserved1 = 0;
        header->reserved2 = 0;
        header->offBits = DKSystemToLittleEndian<uint32_t>(sizeof(BMPFileHeader) + sizeof(BMPInfoHeader));

        info->size = DKSystemToLittleEndian<uint32_t>(sizeof(BMPInfoHeader));
        info->width = DKSystemToLittleEndian<int32_t>(static_cast<int32_t>(width));
        info->height = DKSystemToLittleEndian<int32_t>(static_cast<int32_t>(height));
        info->planes = DKSystemToLittleEndian<uint16_t>(1);
        info->bitCount = DKSystemToLittleEndian<uint16_t>(bitCount);
        info->compression = DKSystemToLittleEndian<uint32_t>(BMPCompressionRGB);
        info->sizeImage = 0;
        info->xPelsPerMeter = DKSystemToLittleEndian<int32_t>(BMP_DEFAULT_PPM);
        info->yPelsPerMeter = DKSystemToLittleEndian<int32_t>(BMP_DEFAULT_PPM);
        info->clrUsed = 0;
        info->clrImportant = 0;

        const uint32_t colorIndices[] = { 2, 1, 0, 3 }; // BGRA -> RGBA

        for (int32_t y = height -1; y >= 0; --y)
        {
            const uint8_t* pixelData = &reinterpret_cast<const uint8_t*>(data)[width * y * bytesPerPixel];
            size_t bytesPerRow = 0;
            for (uint32_t x = 0; x < width; ++x)
            {
                for (uint32_t i = 0; i < bytesPerPixel; ++i)
                    buffer[i] = pixelData[colorIndices[i]]; // BGR(A)

                buffer += bytesPerPixel;
                pixelData += bytesPerPixel;
                bytesPerRow += bytesPerPixel;
            }
            while (bytesPerRow < rowBytes)
            {
                buffer[0] = 0;
                buffer++;
                bytesPerRow++;
            }
        }
        ctx.error = DKImageEncodeError_Success;
        ctx.encodedData = output;
        ctx.encodedDataLength = dataSize;
        ctx.imageFormat = DKImageFormat_BMP;
        ctx.pixelFormat = pixelFormat;
        return ctx;
    }
    ctx.error = DKImageEncodeError_OutOfMemory;
    return ctx;
}

extern "C"
DKImageDecodeContext DKImageDecodeFromMemory(const void * p, size_t s)
{    
    DKImageDecodeContext ctx = {DKImageDecodeError_DataError};

    if (p && s)
    {
        DKImageFormat format = DKImageIdentifyImageFormatFromHeader(p, s);
        switch (format)
        {
        case DKImageFormat_PNG:
            return DecodePng(p, s);
        case DKImageFormat_JPEG:
            return DecodeJpeg(p, s);
        case DKImageFormat_BMP:
            return DecodeBmp(p, s);
        default:
            ctx.error = DKImageDecodeError_UnknownFormat;
        }
    }
    return ctx;
}

extern "C"
DKImageEncodeContext DKImageEncodeFromMemory(DKImageFormat format,
                                             uint32_t width,
                                             uint32_t height,
                                             DKImagePixelFormat pixelFormat,
                                             const void* p,
                                             size_t s)
{
    DKImageEncodeContext ctx = {DKImageEncodeError_DataError};

    size_t bpp = DKImagePixelFormatBytesPerPixel(pixelFormat);
    size_t dataSize = bpp * size_t(width) * size_t(height);
    if (p && dataSize > 0 && s >= dataSize)
    {
        switch (format)
        {
        case DKImageFormat_PNG:
            return EncodePng(width, height, pixelFormat, p);
        case DKImageFormat_JPEG:
            return EncodeJpeg(width, height, pixelFormat, p);
        case DKImageFormat_BMP:
            return EncodeBmp(width, height, pixelFormat, p);
        default:
            ctx.error = DKImageEncodeError_UnknownFormat;
        }
    }
    return ctx;
}

extern "C"
void DKImageReleaseDecodeContext(DKImageDecodeContext* ctx)
{
    if (ctx->errorDescription)
        DKFree((void*)ctx->errorDescription);
    if (ctx->decodedData)
        DKFree((void*)ctx->decodedData);

    ctx->errorDescription = nullptr;
    ctx->decodedData = nullptr;
    ctx->decodedDataLength = 0;
}

extern "C" void DKImageReleaseEncodeContext(DKImageEncodeContext* ctx)
{
    if (ctx->errorDescription)
        DKFree((void*)ctx->errorDescription);
    if (ctx->encodedData)
        DKFree((void*)ctx->encodedData);
    
    ctx->errorDescription = nullptr;
    ctx->encodedData = nullptr;
    ctx->encodedDataLength = 0;
}
