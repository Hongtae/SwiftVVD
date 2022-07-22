/*******************************************************************************
 File: DKAudioStreamVorbis.cpp
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

#include <ogg/ogg.h>
#include "../libvorbis/include/vorbis/codec.h"
#include "../libvorbis/include/vorbis/vorbisfile.h"

#include "DKAudioStream.h"
#include "DKMalloc.h"

#define SWAP_CHANNEL16(x, y)        {int16_t t = x; x = y ; y = t;}

namespace {
    struct VorbisStream
    {
        DKStream* stream;
        uint64_t currentPos;
    };

    size_t VorbisStreamRead(void *ptr, size_t size, size_t nmemb, void *datasource)
    {
        VorbisStream *pSource = reinterpret_cast<VorbisStream*>(datasource);

        size_t validSize = size*nmemb;

        return DKSTREAM_READ(pSource->stream, ptr, validSize);
    }

    int VorbisStreamSeek(void *datasource, ogg_int64_t offset, int whence)
    {
        VorbisStream *pSource = reinterpret_cast<VorbisStream*>(datasource);
        switch (whence)
        {
        case SEEK_SET:
            return DKSTREAM_SET_POSITION(pSource->stream, offset);
            break;
        case SEEK_CUR:
            return DKSTREAM_SET_POSITION(pSource->stream, DKSTREAM_GET_POSITION(pSource->stream) + offset);
            break;
        case SEEK_END:
            return DKSTREAM_SET_POSITION(pSource->stream, DKSTREAM_TOTAL_LENGTH(pSource->stream) + offset);
            break;
        }
        return -1;
    }

    int VorbisStreamClose(void *datasource)
    {
        VorbisStream *pSource = reinterpret_cast<VorbisStream*>(datasource);
        pSource->stream = nullptr;
        return 0;
    }

    long VorbisStreamTell(void *datasource)
    {
        return DKSTREAM_GET_POSITION(reinterpret_cast<VorbisStream*>(datasource)->stream);
    }

    struct VorbisFileContext
    {
        OggVorbis_File vorbis;
        VorbisStream* stream;
    };
}

uint64_t DKAudioStreamVorbisRead(DKAudioStream* stream, void* buffer, size_t size)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);

    if (context->vorbis.datasource == NULL)
        return -1;
    if (size == 0)
        return 0;

    int current_section;
    int nDecoded = 0;
    while (nDecoded < size)
    {
        int nDec = ov_read(&context->vorbis, (char*)buffer + nDecoded, size - nDecoded, 0,2,1, &current_section);
        if (nDec <= 0)
        {
            // error or eof.
            break;
        }
        nDecoded += nDec;
    }

    if (stream->channels == 6)
    {
        short *p = (short*)buffer;
        for ( int i = 0; i < nDecoded / 2; i+=6)
        {
            SWAP_CHANNEL16(p[i+1], p[i+2]);
            SWAP_CHANNEL16(p[i+3], p[i+5]);
            SWAP_CHANNEL16(p[i+4], p[i+5]);
        }
    }
    return nDecoded;
}

uint64_t DKAudioStreamVorbisSeekRaw(DKAudioStream* stream, uint64_t pos)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    ov_raw_seek(&context->vorbis, pos);
    return ov_raw_tell(&context->vorbis);
}

uint64_t DKAudioStreamVorbisSeekPcm(DKAudioStream* stream, uint64_t pos)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    ov_pcm_seek(&context->vorbis, pos);
    return ov_pcm_tell(&context->vorbis);
}

double DKAudioStreamVorbisSeekTime(DKAudioStream* stream, double t)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    ov_time_seek(&context->vorbis, t);
    return ov_time_tell(&context->vorbis);
}

uint64_t DKAudioStreamVorbisRawPosition(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_raw_tell(&context->vorbis);
}

uint64_t DKAudioStreamVorbisPcmPosition(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_pcm_tell(&context->vorbis);
}

double DKAudioStreamVorbisTimePosition(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_time_tell(&context->vorbis);
}

uint64_t DKAudioStreamVorbisRawTotal(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_raw_total(&context->vorbis, -1);
}

uint64_t DKAudioStreamVorbisPcmTotal(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_pcm_total(&context->vorbis, -1);
}

double DKAudioStreamVorbisTimeTotal(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_time_total(&context->vorbis, -1);
}

DKAudioStream* DKAudioStreamVorbisCreate(const char* file)
{
    VorbisFileContext* context = (VorbisFileContext*)DKMalloc(sizeof(VorbisFileContext));
    memset(context, 0, sizeof(VorbisFileContext));

    if (ov_fopen(file, &context->vorbis) == 0)
    {
        vorbis_info *info = ov_info(&context->vorbis, -1);
        if (info)
        {
            DKAudioStream* audioStream = (DKAudioStream*)DKMalloc(sizeof(DKAudioStream));
            memset(audioStream, 0, sizeof(DKAudioStream));
            audioStream->decoder = reinterpret_cast<void*>(context);

            audioStream->mediaType = DKAudioStreamEncodingFormat_OggVorbis;
            audioStream->channels = info->channels;
            audioStream->sampleRate = info->rate;
            audioStream->bits = 16;
            audioStream->seekable = (bool)ov_seekable(&context->vorbis);

            audioStream->read = DKAudioStreamVorbisRead;
            audioStream->seekRaw = DKAudioStreamVorbisSeekRaw;
            audioStream->seekPcm = DKAudioStreamVorbisSeekPcm;
            audioStream->seekTime = DKAudioStreamVorbisSeekTime;
            audioStream->rawPosition = DKAudioStreamVorbisRawPosition;
            audioStream->pcmPosition = DKAudioStreamVorbisPcmPosition;
            audioStream->timePosition = DKAudioStreamVorbisTimePosition;
            audioStream->rawTotal = DKAudioStreamVorbisRawTotal;
            audioStream->pcmTotal = DKAudioStreamVorbisPcmTotal;
            audioStream->timeTotal = DKAudioStreamVorbisTimeTotal;
            
            return audioStream;
        }
    }
    DKFree(context);
    return nullptr;
}

DKAudioStream* DKAudioStreamVorbisCreate(DKStream* stream)
{
    if (stream == nullptr ||
        !DKSTREAM_IS_READABLE(stream) ||
        !DKSTREAM_IS_SEEKABLE(stream) ||
        !DKSTREAM_HAS_LENGTH(stream))
        return nullptr;

    VorbisFileContext* context = (VorbisFileContext*)DKMalloc(sizeof(VorbisFileContext));
    memset(context, 0, sizeof(VorbisFileContext));

    VorbisStream* vorbisStream = (VorbisStream*)DKMalloc(sizeof(VorbisStream));
    memset(vorbisStream, 0, sizeof(VorbisStream));
    vorbisStream->stream = stream;

    ov_callbacks ogg_callbacks;
    ogg_callbacks.read_func = VorbisStreamRead;
    ogg_callbacks.seek_func = VorbisStreamSeek;
    ogg_callbacks.tell_func = VorbisStreamTell;
    ogg_callbacks.close_func = VorbisStreamClose;

    if (ov_open_callbacks(vorbisStream, &context->vorbis, 0, 0, ogg_callbacks) == 0)
    {
        vorbis_info *info = ov_info(&context->vorbis, -1);
        if (info)
        {
            DKAudioStream* audioStream = (DKAudioStream*)DKMalloc(sizeof(DKAudioStream));
            memset(audioStream, 0, sizeof(DKAudioStream));

            audioStream->decoder = reinterpret_cast<void*>(context);
            context->stream = vorbisStream;

            audioStream->mediaType = DKAudioStreamEncodingFormat_OggVorbis;
            audioStream->channels = info->channels;
            audioStream->sampleRate = info->rate;
            audioStream->bits = 16;
            audioStream->seekable = (bool)ov_seekable(&context->vorbis);

            audioStream->read = DKAudioStreamVorbisRead;
            audioStream->seekRaw = DKAudioStreamVorbisSeekRaw;
            audioStream->seekPcm = DKAudioStreamVorbisSeekPcm;
            audioStream->seekTime = DKAudioStreamVorbisSeekTime;
            audioStream->rawPosition = DKAudioStreamVorbisRawPosition;
            audioStream->pcmPosition = DKAudioStreamVorbisPcmPosition;
            audioStream->timePosition = DKAudioStreamVorbisTimePosition;
            audioStream->rawTotal = DKAudioStreamVorbisRawTotal;
            audioStream->pcmTotal = DKAudioStreamVorbisPcmTotal;
            audioStream->timeTotal = DKAudioStreamVorbisTimeTotal;
            
            return audioStream;
        }
    }
    DKFree(context);
    DKFree(vorbisStream);
    return nullptr;
}

void DKAudioStreamVorbisDestroy(DKAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource)
        ov_clear(&context->vorbis);

    if (context->stream)
        DKFree(context->stream);

#if DEBUG
    memset(context, 0, sizeof(VorbisFileContext));
    memset(stream, 0, sizeof(DKAudioStream));
#endif
    DKFree(context);
    DKFree(stream);
}
