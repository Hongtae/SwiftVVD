/*******************************************************************************
 File: AudioStream.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#include <memory.h>
#include "AudioStream.h"

extern "C" VVDAudioStreamEncodingFormat
VVDAudioStreamDetermineFormatFromHeader(char* data, size_t len)
{
    if (len >= 4 && memcmp(data, "OggS", 4) == 0)
    {
        // vorbis or flac.
        if (len >= 32 && memcmp(&data[29], "fLaC", 4) == 0)
        {
            return VVDAudioStreamEncodingFormat_OggFLAC;
        }
        if (len >= 35 && memcmp(&data[29], "vorbis", 6) == 0)
        {
            return VVDAudioStreamEncodingFormat_OggVorbis;
        }
        return VVDAudioStreamEncodingFormat_Unknown;
    }
    else if (len >= 4 && memcmp(data, "fLaC", 4) == 0)
    {
        return VVDAudioStreamEncodingFormat_FLAC;
    }
    else if (len >= 10 && memcmp(data, "ID3", 3) == 0 && (data[5] & 0xF) == 0 &&
        (data[6] & 0x80) == 0 && (data[7] & 0x80) == 0 &&
        (data[8] & 0x80) == 0 && (data[9] & 0x80) == 0)
    {
        return VVDAudioStreamEncodingFormat_MP3;
    }
    else if (len >= 4 && memcmp(data, "RIFF", 4) == 0)
    {
        return VVDAudioStreamEncodingFormat_Wave;
    }
    return VVDAudioStreamEncodingFormat_Unknown;
}

VVDAudioStream* VVDAudioStreamVorbisCreate(const char* file);
VVDAudioStream* VVDAudioStreamVorbisCreate(VVDStream* stream);
VVDAudioStream* VVDAudioStreamOggFLACCreate(VVDStream* stream);
VVDAudioStream* VVDAudioStreamFLACCreate(VVDStream* stream);
VVDAudioStream* VVDAudioStreamMP3Create(VVDStream* stream);
VVDAudioStream* VVDAudioStreamWaveCreate(VVDStream* stream);

void VVDAudioStreamVorbisDestroy(VVDAudioStream* stream);
void VVDAudioStreamOggFLACDestroy(VVDAudioStream* stream);
void VVDAudioStreamFLACDestroy(VVDAudioStream* stream);
void VVDAudioStreamMP3Destroy(VVDAudioStream* stream);
void VVDAudioStreamWaveDestroy(VVDAudioStream* stream);

#define AUDIO_FORMAT_HEADER_LENGTH      35

extern "C" VVDAudioStream* VVDAudioStreamCreate(VVDStream* stream)
{
    if (stream && VVDSTREAM_IS_READABLE(stream) && VVDSTREAM_IS_SEEKABLE(stream))
    {
        VVDSTREAM_SET_POSITION(stream, 0);

        // reading file header.
        char header[AUDIO_FORMAT_HEADER_LENGTH];
        memset(header, 0, AUDIO_FORMAT_HEADER_LENGTH);
        VVDSTREAM_READ(stream, header, AUDIO_FORMAT_HEADER_LENGTH);
        VVDSTREAM_SET_POSITION(stream, 0);

        VVDAudioStreamEncodingFormat format = VVDAudioStreamDetermineFormatFromHeader(header, AUDIO_FORMAT_HEADER_LENGTH);
        switch (format)
        {
        case VVDAudioStreamEncodingFormat_OggVorbis:
            return VVDAudioStreamVorbisCreate(stream);
        case VVDAudioStreamEncodingFormat_OggFLAC:
            return VVDAudioStreamOggFLACCreate(stream);
        case VVDAudioStreamEncodingFormat_FLAC:
            return VVDAudioStreamFLACCreate(stream);
        case VVDAudioStreamEncodingFormat_MP3:
            return VVDAudioStreamMP3Create(stream);
        case VVDAudioStreamEncodingFormat_Wave:
            return VVDAudioStreamWaveCreate(stream);
        default:
            break;
        }
    }
    return nullptr;
}

extern "C" void VVDAudioStreamDestroy(VVDAudioStream* stream)
{
    switch (stream->mediaType)
    {
    case VVDAudioStreamEncodingFormat_OggVorbis:
        VVDAudioStreamVorbisDestroy(stream);
        break;
    case VVDAudioStreamEncodingFormat_OggFLAC:
        VVDAudioStreamOggFLACDestroy(stream);
        break;
    case VVDAudioStreamEncodingFormat_FLAC:
        VVDAudioStreamFLACDestroy(stream);
        break;
    case VVDAudioStreamEncodingFormat_MP3:
        VVDAudioStreamMP3Destroy(stream);
        break;
    case VVDAudioStreamEncodingFormat_Wave:
        VVDAudioStreamWaveDestroy(stream);
        break;
    default:
        break;
    }
}
