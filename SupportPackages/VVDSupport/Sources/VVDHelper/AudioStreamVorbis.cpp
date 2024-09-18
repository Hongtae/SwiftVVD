/*******************************************************************************
 File: AudioStreamVorbis.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#include <memory.h>
#include <string.h>
#include <algorithm>

#include <ogg/ogg.h>
#include "../libvorbis/include/vorbis/codec.h"
#include "../libvorbis/include/vorbis/vorbisfile.h"

#include "AudioStream.h"
#include "Malloc.h"

#define SWAP_CHANNEL16(x, y)        {int16_t t = x; x = y ; y = t;}

namespace {
    struct VorbisStream
    {
        VVDStream* stream;
        uint64_t currentPos;
    };

    size_t VorbisStreamRead(void *ptr, size_t size, size_t nmemb, void *datasource)
    {
        VorbisStream *pSource = reinterpret_cast<VorbisStream*>(datasource);

        size_t validSize = size*nmemb;

        return VVDSTREAM_READ(pSource->stream, ptr, validSize);
    }

    int VorbisStreamSeek(void *datasource, ogg_int64_t offset, int whence)
    {
        VorbisStream *pSource = reinterpret_cast<VorbisStream*>(datasource);
        switch (whence)
        {
        case SEEK_SET:
            return VVDSTREAM_SET_POSITION(pSource->stream, offset);
            break;
        case SEEK_CUR:
            return VVDSTREAM_SET_POSITION(pSource->stream, VVDSTREAM_GET_POSITION(pSource->stream) + offset);
            break;
        case SEEK_END:
            return VVDSTREAM_SET_POSITION(pSource->stream, VVDSTREAM_TOTAL_LENGTH(pSource->stream) + offset);
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
        return VVDSTREAM_GET_POSITION(reinterpret_cast<VorbisStream*>(datasource)->stream);
    }

    struct VorbisFileContext
    {
        OggVorbis_File vorbis;
        VorbisStream* stream;
    };
}

uint64_t VVDAudioStreamVorbisRead(VVDAudioStream* stream, void* buffer, size_t size)
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

uint64_t VVDAudioStreamVorbisSeekRaw(VVDAudioStream* stream, uint64_t pos)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    ov_raw_seek(&context->vorbis, pos);
    return ov_raw_tell(&context->vorbis);
}

uint64_t VVDAudioStreamVorbisSeekPcm(VVDAudioStream* stream, uint64_t pos)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    ov_pcm_seek(&context->vorbis, pos);
    return ov_pcm_tell(&context->vorbis);
}

double VVDAudioStreamVorbisSeekTime(VVDAudioStream* stream, double t)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    ov_time_seek(&context->vorbis, t);
    return ov_time_tell(&context->vorbis);
}

uint64_t VVDAudioStreamVorbisRawPosition(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_raw_tell(&context->vorbis);
}

uint64_t VVDAudioStreamVorbisPcmPosition(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_pcm_tell(&context->vorbis);
}

double VVDAudioStreamVorbisTimePosition(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_time_tell(&context->vorbis);
}

uint64_t VVDAudioStreamVorbisRawTotal(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_raw_total(&context->vorbis, -1);
}

uint64_t VVDAudioStreamVorbisPcmTotal(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_pcm_total(&context->vorbis, -1);
}

double VVDAudioStreamVorbisTimeTotal(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource == NULL)
        return -1;

    return ov_time_total(&context->vorbis, -1);
}

VVDAudioStream* VVDAudioStreamVorbisCreate(const char* file)
{
    VorbisFileContext* context = (VorbisFileContext*)VVDMalloc(sizeof(VorbisFileContext));
    memset(context, 0, sizeof(VorbisFileContext));

    if (ov_fopen(file, &context->vorbis) == 0)
    {
        vorbis_info *info = ov_info(&context->vorbis, -1);
        if (info)
        {
            VVDAudioStream* audioStream = (VVDAudioStream*)VVDMalloc(sizeof(VVDAudioStream));
            memset(audioStream, 0, sizeof(VVDAudioStream));
            audioStream->decoder = reinterpret_cast<void*>(context);

            audioStream->mediaType = VVDAudioStreamEncodingFormat_OggVorbis;
            audioStream->channels = info->channels;
            audioStream->sampleRate = info->rate;
            audioStream->bits = 16;
            audioStream->seekable = (bool)ov_seekable(&context->vorbis);

            audioStream->read = VVDAudioStreamVorbisRead;
            audioStream->seekRaw = VVDAudioStreamVorbisSeekRaw;
            audioStream->seekPcm = VVDAudioStreamVorbisSeekPcm;
            audioStream->seekTime = VVDAudioStreamVorbisSeekTime;
            audioStream->rawPosition = VVDAudioStreamVorbisRawPosition;
            audioStream->pcmPosition = VVDAudioStreamVorbisPcmPosition;
            audioStream->timePosition = VVDAudioStreamVorbisTimePosition;
            audioStream->rawTotal = VVDAudioStreamVorbisRawTotal;
            audioStream->pcmTotal = VVDAudioStreamVorbisPcmTotal;
            audioStream->timeTotal = VVDAudioStreamVorbisTimeTotal;
            
            return audioStream;
        }
    }
    VVDFree(context);
    return nullptr;
}

VVDAudioStream* VVDAudioStreamVorbisCreate(VVDStream* stream)
{
    if (stream == nullptr ||
        !VVDSTREAM_IS_READABLE(stream) ||
        !VVDSTREAM_IS_SEEKABLE(stream) ||
        !VVDSTREAM_HAS_LENGTH(stream))
        return nullptr;

    VorbisFileContext* context = (VorbisFileContext*)VVDMalloc(sizeof(VorbisFileContext));
    memset(context, 0, sizeof(VorbisFileContext));

    VorbisStream* vorbisStream = (VorbisStream*)VVDMalloc(sizeof(VorbisStream));
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
            VVDAudioStream* audioStream = (VVDAudioStream*)VVDMalloc(sizeof(VVDAudioStream));
            memset(audioStream, 0, sizeof(VVDAudioStream));

            audioStream->decoder = reinterpret_cast<void*>(context);
            context->stream = vorbisStream;

            audioStream->mediaType = VVDAudioStreamEncodingFormat_OggVorbis;
            audioStream->channels = info->channels;
            audioStream->sampleRate = info->rate;
            audioStream->bits = 16;
            audioStream->seekable = (bool)ov_seekable(&context->vorbis);

            audioStream->read = VVDAudioStreamVorbisRead;
            audioStream->seekRaw = VVDAudioStreamVorbisSeekRaw;
            audioStream->seekPcm = VVDAudioStreamVorbisSeekPcm;
            audioStream->seekTime = VVDAudioStreamVorbisSeekTime;
            audioStream->rawPosition = VVDAudioStreamVorbisRawPosition;
            audioStream->pcmPosition = VVDAudioStreamVorbisPcmPosition;
            audioStream->timePosition = VVDAudioStreamVorbisTimePosition;
            audioStream->rawTotal = VVDAudioStreamVorbisRawTotal;
            audioStream->pcmTotal = VVDAudioStreamVorbisPcmTotal;
            audioStream->timeTotal = VVDAudioStreamVorbisTimeTotal;
            
            return audioStream;
        }
    }
    VVDFree(context);
    VVDFree(vorbisStream);
    return nullptr;
}

void VVDAudioStreamVorbisDestroy(VVDAudioStream* stream)
{
    VorbisFileContext* context = reinterpret_cast<VorbisFileContext*>(stream->decoder);
    if (context->vorbis.datasource)
        ov_clear(&context->vorbis);

    if (context->stream)
        VVDFree(context->stream);

#if DEBUG
    memset(context, 0, sizeof(VorbisFileContext));
    memset(stream, 0, sizeof(VVDAudioStream));
#endif
    VVDFree(context);
    VVDFree(stream);
}
