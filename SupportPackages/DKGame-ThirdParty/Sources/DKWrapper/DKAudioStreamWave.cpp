/*******************************************************************************
 File: DKAudioStreamWave.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include <memory.h>
#include <string.h>
#include <algorithm>
#include "DKAudioStream.h"
#include "DKEndianness.h"
#include "DKMalloc.h"
#include "DKLog.h"

#ifdef _WIN32
#define strcasecmp _stricmp
#define strncasecmp _strnicmp
#endif

#pragma pack(push, 4)
namespace {
    enum WaveFormatType
    {
        WaveFormatTypeUnknown = 0,
        WaveFormatTypePCM = 1,          // WAVE_FORMAT_PCM
        WaveFormatTypeEXT = 0xFFFE,     // WAVE_FORMAT_EXTENSIBLE
    };
    struct WaveFileHeader
    {
        char     riff[4];
        uint32_t riffSize;
        char     wave[4];
    };
    struct RiffChunk
    {
        char     name[4];
        uint32_t size;
    };
    struct WaveFormat
    {
        uint16_t formatTag;
        uint16_t channels;
        uint32_t samplesPerSec;
        uint32_t avgBytesPerSec;
        uint16_t blockAlign;
        uint16_t bitsPerSample;
        uint16_t size;
        uint16_t reserved;
        uint32_t channelMask;
        uint8_t  subformatGuid[16];
    };
    struct WaveFormatPCM
    {
        uint16_t tag;
        uint16_t channels;
        uint32_t samplesPerSec;
        uint32_t avgBytesPerSec;
        uint16_t blockAlign;
        uint16_t bitsPerSample;
    };
    struct WaveFormatEX
    {
        uint16_t tag;
        uint16_t channels;
        uint32_t samplesPerSec;
        uint32_t avgBytesPerSec;
        uint16_t blockAlign;
        uint16_t bitsPerSample;
        uint16_t size;

        uint8_t _unused[2];
    };
    struct WaveFormatExt
    {
        WaveFormatEX format;
        union
        {
            uint16_t validBitsPerSample;
            uint16_t samplesPerBlock;
            uint16_t reserved;
        } samples;
        unsigned int channelMask;

        struct
        {
            uint32_t data1;
            uint16_t data2;
            uint16_t data3;
            uint8_t  data4[8];
        } subFormatGUID;
    };
    struct WaveFileContext
    {
        DKStream*       stream;
        WaveFormatType  formatType;
        WaveFormatExt   formatExt;

        char* data;
        uint64_t dataSize;
        uint64_t dataOffset;
    };
}
#pragma pack(pop)

static_assert(sizeof(WaveFileHeader) == 12, "sizeof(WaveFileHeader) == 12");
static_assert(sizeof(RiffChunk) == 8, "sizeof(RiffChunk) == 8");
static_assert(sizeof(WaveFormat) == 40, "sizeof(WaveFormat) == 40");
static_assert(sizeof(WaveFormatPCM) == 16, "sizeof(WaveFormatPCM) == 16");
static_assert(sizeof(WaveFormatEX) == 20, "sizeof(WaveFormatEX) == 20");
static_assert(sizeof(WaveFormatExt) == 44, "sizeof(WaveFormatEX) == 44");


uint64_t DKAudioStreamWaveRead(DKAudioStream* stream, void* buffer, size_t size)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        size_t pos = DKSTREAM_GET_POSITION(context->stream);
        if (pos + size > context->dataSize)
            size = context->dataSize - pos;

        if (size > context->formatExt.format.blockAlign)
        {
            // buffer should be aligned with format.blockAlign
            if (context->formatExt.format.blockAlign > 0)
                size = size - (size % context->formatExt.format.blockAlign);

            if (size > 0)
                return DKSTREAM_READ(context->stream, buffer, size);
        }
    }
    return 0;
}

uint64_t DKAudioStreamWaveSeekRaw(DKAudioStream* stream, uint64_t pos)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        // alignment
        if (context->formatExt.format.blockAlign > 0)
            pos = pos - (pos % context->formatExt.format.blockAlign);

        pos = DKSTREAM_SET_POSITION(context->stream, context->dataOffset + std::clamp<uint64_t>(pos, 0, context->dataSize));
        return std::clamp<uint64_t>(pos - context->dataOffset, 0, context->dataSize);
    }
    return 0;
}

double DKAudioStreamWaveSeekTime(DKAudioStream* stream, double t)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        uint64_t pos = DKAudioStreamWaveSeekRaw(stream, static_cast<uint64_t>(t * static_cast<double>(context->formatExt.format.avgBytesPerSec)));
        return static_cast<double>(pos) / static_cast<double>(context->formatExt.format.avgBytesPerSec);
    }
    return 0.0;
}

uint64_t DKAudioStreamWaveRawPosition(DKAudioStream* stream)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        return DKSTREAM_GET_POSITION(context->stream) - context->dataOffset;
    }
    return 0;
}

double DKAudioStreamWaveTimePosition(DKAudioStream* stream)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        uint64_t pos = DKSTREAM_GET_POSITION(context->stream) - context->dataOffset;
        return static_cast<double>(pos) / static_cast<double>(context->formatExt.format.avgBytesPerSec);
    }
    return 0;
}

uint64_t DKAudioStreamWaveRawTotal(DKAudioStream* stream)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        return context->dataSize;
    }
    return 0;
}

double DKAudioStreamWaveTimeTotal(DKAudioStream* stream)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
    if (context->stream)
    {
        return static_cast<double>(context->dataSize) / static_cast<double>(context->formatExt.format.avgBytesPerSec);
    }
    return 0;
}

DKAudioStream* DKAudioStreamWaveCreate(DKStream* stream)
{
    if (stream == nullptr || !DKSTREAM_IS_READABLE(stream) || !DKSTREAM_IS_SEEKABLE(stream))
        return nullptr;

    WaveFileContext* context = (WaveFileContext*)DKMalloc(sizeof(WaveFileContext));
    memset(context, 0, sizeof(WaveFileContext));
    context->stream = stream;
    context->dataSize = 0;
    context->dataOffset = 0;
    context->formatType = WaveFormatTypeUnknown;

    WaveFileHeader header;
    memset(&header, 0, sizeof(WaveFileHeader));
    if (DKSTREAM_READ(stream, &header, sizeof(WaveFileHeader)) == sizeof(WaveFileHeader))
    {
        if (strncasecmp(header.riff, "RIFF", 4) == 0 && strncasecmp(header.wave, "WAVE", 4) == 0)
        {
            // swap byte order (from little-endian to system)
            header.riffSize = DKLittleEndianToSystem(header.riffSize);

            // read all chunk
            RiffChunk chunk;
            while (DKSTREAM_READ(stream, &chunk, sizeof(RiffChunk)) == sizeof(RiffChunk))
            {
                chunk.size = DKLittleEndianToSystem(chunk.size);

                if (strncasecmp(chunk.name, "fmt ", 4) == 0)
                {
                    if (chunk.size <= sizeof(WaveFormat))
                    {
                        WaveFormat format;
                        memset(&format, 0, sizeof(WaveFormat));
                        if (DKSTREAM_READ(stream, &format, chunk.size) == chunk.size)
                        {
                            // swap byte order
                            format.formatTag = DKLittleEndianToSystem(format.formatTag);
                            format.channels = DKLittleEndianToSystem(format.channels);
                            format.samplesPerSec = DKLittleEndianToSystem(format.samplesPerSec);
                            format.avgBytesPerSec = DKLittleEndianToSystem(format.avgBytesPerSec);
                            format.blockAlign = DKLittleEndianToSystem(format.blockAlign);
                            format.bitsPerSample = DKLittleEndianToSystem(format.bitsPerSample);
                            format.size = DKLittleEndianToSystem(format.size);
                            format.reserved = DKLittleEndianToSystem(format.reserved);
                            format.channelMask = DKLittleEndianToSystem(format.channelMask);

                            if (format.formatTag == WaveFormatTypePCM)
                            {
                                context->formatType = WaveFormatTypePCM;
                                memcpy(&context->formatExt.format, &format, sizeof(WaveFormatPCM));
                            }
                            else if (format.formatTag == WaveFormatTypeEXT)
                            {
                                context->formatType = WaveFormatTypeEXT;
                                memcpy(&context->formatExt, &format, sizeof(WaveFormatExt));
                            }
                            else
                            {
                                DKLogE("AudioStreamWave: Unknown format! (0x%x)\n", format.formatTag);
                            }
                        }
                        else
                        {
                            DKLogE("AudioStreamWave: Read error!\n");
                            DKFree(context);
                            return nullptr;
                        }
                    }
                    else
                    {
                        DKSTREAM_SET_POSITION(stream, DKSTREAM_GET_POSITION(stream) + chunk.size);
                    }
                }
                else if (strncasecmp(chunk.name, "data", 4) == 0)
                {
                    context->dataSize = chunk.size;
                    context->dataOffset = DKSTREAM_GET_POSITION(stream);
                    DKSTREAM_SET_POSITION(stream, DKSTREAM_GET_POSITION(stream) + chunk.size);
                }
                else
                {
                    DKSTREAM_SET_POSITION(stream, DKSTREAM_GET_POSITION(stream) + chunk.size);
                }

                if (chunk.size & 1) // byte align
                    DKSTREAM_SET_POSITION(stream, DKSTREAM_GET_POSITION(stream) + 1);
            }

            DKLog("AudioStreamWave: dataSize:%d\n", (int)context->dataSize);
            DKLog("AudioStreamWave: dataOffset:%d\n", (int)context->dataOffset);
            DKLog("AudioStreamWave: formatType:%d\n", (int)context->formatType);

            if (context->dataSize && context->dataOffset &&
                (context->formatType == WaveFormatTypePCM ||
                context->formatType == WaveFormatTypeEXT))
            {
                DKAudioStream* audioStream = (DKAudioStream*)DKMalloc(sizeof(DKAudioStream));
                memset(audioStream, 0, sizeof(DKAudioStream));

                audioStream->decoder = reinterpret_cast<void*>(context);
                audioStream->mediaType = DKAudioStreamEncodingFormat_Wave;
                audioStream->channels = context->formatExt.format.channels;
                audioStream->sampleRate = context->formatExt.format.samplesPerSec;
                audioStream->bits = context->formatExt.format.bitsPerSample;
                audioStream->seekable = true;

                audioStream->read = DKAudioStreamWaveRead;
                audioStream->seekRaw = DKAudioStreamWaveSeekRaw;
                audioStream->seekPcm = DKAudioStreamWaveSeekRaw;
                audioStream->seekTime = DKAudioStreamWaveSeekTime;
                audioStream->rawPosition = DKAudioStreamWaveRawPosition;
                audioStream->pcmPosition = DKAudioStreamWaveRawPosition;
                audioStream->timePosition = DKAudioStreamWaveTimePosition;
                audioStream->rawTotal = DKAudioStreamWaveRawTotal;
                audioStream->pcmTotal = DKAudioStreamWaveRawTotal;
                audioStream->timeTotal = DKAudioStreamWaveTimeTotal;

                return audioStream;
            }
        }
    }
    DKFree(context);
    return nullptr;
}

void DKAudioStreamWaveDestroy(DKAudioStream* stream)
{
    WaveFileContext* context = reinterpret_cast<WaveFileContext*>(stream->decoder);
#if DEBUG
    memset(context, 0, sizeof(WaveFileContext));
    memset(stream, 0, sizeof(DKAudioStream));
#endif    
    DKFree(context);
    DKFree(stream);
}
