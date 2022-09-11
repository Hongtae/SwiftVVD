/*******************************************************************************
 File: DKAudioStream.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include <memory.h>
#include "DKAudioStream.h"

extern "C" DKAudioStreamEncodingFormat
DKAudioStreamDetermineFormatFromHeader(char* data, size_t len)
{
    if (len >= 4 && memcmp(data, "OggS", 4) == 0)
    {
        // vorbis or flac.
        if (len >= 32 && memcmp(&data[29], "fLaC", 4) == 0)
        {
            return DKAudioStreamEncodingFormat_OggFLAC;
        }
        if (len >= 35 && memcmp(&data[29], "vorbis", 6) == 0)
        {
            return DKAudioStreamEncodingFormat_OggVorbis;
        }
        return DKAudioStreamEncodingFormat_Unknown;
    }
    else if (len >= 4 && memcmp(data, "fLaC", 4) == 0)
    {
        return DKAudioStreamEncodingFormat_FLAC;
    }
    else if (len >= 10 && memcmp(data, "ID3", 3) == 0 && (data[5] & 0xF) == 0 &&
        (data[6] & 0x80) == 0 && (data[7] & 0x80) == 0 &&
        (data[8] & 0x80) == 0 && (data[9] & 0x80) == 0)
    {
        return DKAudioStreamEncodingFormat_MP3;
    }
    else if (len >= 4 && memcmp(data, "RIFF", 4) == 0)
    {
        return DKAudioStreamEncodingFormat_Wave;
    }
    return DKAudioStreamEncodingFormat_Unknown;
}

DKAudioStream* DKAudioStreamVorbisCreate(const char* file);
DKAudioStream* DKAudioStreamVorbisCreate(DKStream* stream);
DKAudioStream* DKAudioStreamOggFLACCreate(DKStream* stream);
DKAudioStream* DKAudioStreamFLACCreate(DKStream* stream);
DKAudioStream* DKAudioStreamMP3Create(DKStream* stream);
DKAudioStream* DKAudioStreamWaveCreate(DKStream* stream);

void DKAudioStreamVorbisDestroy(DKAudioStream* stream);
void DKAudioStreamOggFLACDestroy(DKAudioStream* stream);
void DKAudioStreamFLACDestroy(DKAudioStream* stream);
void DKAudioStreamMP3Destroy(DKAudioStream* stream);
void DKAudioStreamWaveDestroy(DKAudioStream* stream);

#define AUDIO_FORMAT_HEADER_LENGTH      35

extern "C" DKAudioStream* DKAudioStreamCreate(DKStream* stream)
{
    if (stream && DKSTREAM_IS_READABLE(stream) && DKSTREAM_IS_SEEKABLE(stream))
    {
        DKSTREAM_SET_POSITION(stream, 0);

        // reading file header.
        char header[AUDIO_FORMAT_HEADER_LENGTH];
        memset(header, 0, AUDIO_FORMAT_HEADER_LENGTH);
        DKSTREAM_READ(stream, header, AUDIO_FORMAT_HEADER_LENGTH);
        DKSTREAM_SET_POSITION(stream, 0);

        DKAudioStreamEncodingFormat format = DKAudioStreamDetermineFormatFromHeader(header, AUDIO_FORMAT_HEADER_LENGTH);
        switch (format)
        {
        case DKAudioStreamEncodingFormat_OggVorbis:
            return DKAudioStreamVorbisCreate(stream);
        case DKAudioStreamEncodingFormat_OggFLAC:
            return DKAudioStreamOggFLACCreate(stream);
        case DKAudioStreamEncodingFormat_FLAC:
            return DKAudioStreamFLACCreate(stream);
        case DKAudioStreamEncodingFormat_MP3:
            return DKAudioStreamMP3Create(stream);
        case DKAudioStreamEncodingFormat_Wave:
            return DKAudioStreamWaveCreate(stream);
        default:
            break;
        }
    }
    return nullptr;
}

extern "C" void DKAudioStreamDestroy(DKAudioStream* stream)
{
    switch (stream->mediaType)
    {
    case DKAudioStreamEncodingFormat_OggVorbis:
        DKAudioStreamVorbisDestroy(stream);
        break;
    case DKAudioStreamEncodingFormat_OggFLAC:
        DKAudioStreamOggFLACDestroy(stream);
        break;
    case DKAudioStreamEncodingFormat_FLAC:
        DKAudioStreamFLACDestroy(stream);
        break;
    case DKAudioStreamEncodingFormat_MP3:
        DKAudioStreamMP3Destroy(stream);
        break;
    case DKAudioStreamEncodingFormat_Wave:
        DKAudioStreamWaveDestroy(stream);
        break;
    default:
        break;
    }
}
