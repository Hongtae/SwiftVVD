/*******************************************************************************
 File: DKAudioStreamWave.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include "DKAudioStream.h"

#pragma pack(push, 4)

enum WaveFormatType
{
    WaveFormatTypeUnknown = 0,
    WaveFormatTypePCM = 1,			// WAVE_FORMAT_PCM
    WaveFormatTypeEXT = 0xFFFE,		// WAVE_FORMAT_EXTENSIBLE
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
    size_t dataSize;
    size_t dataOffset;
};

#pragma pack(pop)
