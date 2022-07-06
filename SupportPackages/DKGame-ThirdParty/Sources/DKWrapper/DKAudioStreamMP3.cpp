/*******************************************************************************
 File: DKAudioStreamMP3.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include <vector>
#define MINIMP3_IMPLEMENTATION
#include "../minimp3/minimp3_ex.h"

#include "DKAudioStream.h"
#include "DKMalloc.h"
#include "DKLog.h"

namespace {
    struct MP3Context
    {
        DKStream* stream;
        mp3dec_ex_t dec;
        mp3dec_io_t io;
        std::vector<uint8_t> buffer;
    };
}

uint64_t DKAudioStreamMP3Read(DKAudioStream* stream, void* buffer, size_t size)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    size_t numSamples = size / sizeof(mp3d_sample_t);
    size_t samples = mp3dec_ex_read(&context->dec, (mp3d_sample_t*)buffer, numSamples);
    if (samples != numSamples) /* normal eof or error condition */
    {
        if (context->dec.last_error)
        {
            /* error */
            DKLogE("AudioStreamMP3: Read error! (%x)\n", context->dec.last_error);

            if (samples == 0)
                return -1;
        }
    }
    return samples * sizeof(mp3d_sample_t);
}

uint64_t DKAudioStreamMP3SeekRaw(DKAudioStream* stream, uint64_t pos)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    pos = pos / sizeof(mp3d_sample_t);
    if (pos > context->dec.samples)
        pos = context->dec.samples;

    int result = mp3dec_ex_seek(&context->dec, pos);
    if (result)
    {
        DKLogE("AudioStreamMP3: Seek error! (%x)\n", result);
        return DKSTREAM_ERROR;
    }
    return (context->dec.offset - context->dec.start_offset);
}

uint64_t DKAudioStreamMP3SeekPcm(DKAudioStream* stream, uint64_t pos)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    if (pos > context->dec.samples)
        pos = context->dec.samples;

    int result = mp3dec_ex_seek(&context->dec, pos);
    if (result)
    {
        DKLogE("AudioStreamMP3: Seek error! (%x)\n", result);
        return DKSTREAM_ERROR;
    }
    return (context->dec.offset - context->dec.start_offset) / sizeof(mp3d_sample_t);
}

double DKAudioStreamMP3SeekTime(DKAudioStream* stream, double t)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    uint64_t pos = uint64_t(double(context->dec.info.hz) * t);
    if (pos > context->dec.samples)
        pos = context->dec.samples;

    int result = mp3dec_ex_seek(&context->dec, pos);
    if (result)
    {
        DKLogE("AudioStreamMP3: Seek error! (%x)\n", result);
        return -1.0;
    }
    return t;
}

uint64_t DKAudioStreamMP3RawPosition(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.cur_sample * sizeof(mp3d_sample_t);
}

uint64_t DKAudioStreamMP3PcmPosition(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.cur_sample;
}

double DKAudioStreamMP3TimePosition(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    double freq = double(context->dec.info.hz);
    double t = double(context->dec.cur_sample) / freq;
    return t;
}

uint64_t DKAudioStreamMP3RawTotal(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.samples * sizeof(mp3d_sample_t);
}

uint64_t DKAudioStreamMP3PcmTotal(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.samples;
}

double DKAudioStreamMP3TimeTotal(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    double freq = double(context->dec.info.hz);
    double t = double(context->dec.samples) / freq;
    return t;
}

DKAudioStream* DKAudioStreamMP3Create(DKStream* stream)
{
    if (stream && DKSTREAM_IS_READABLE(stream))
    {
        MP3Context* context = (MP3Context*)DKMalloc(sizeof(MP3Context));
        memset(context, 0, sizeof(MP3Context));
        new(context) MP3Context();

        context->stream = stream;

        int result = -1;

        if (DKSTREAM_IS_SEEKABLE(stream))
        {
            context->io.read_data = (void*)context;
            context->io.seek_data = (void*)context;
            context->io.read = [](void *buf, size_t size, void *userData)->size_t
            {
                MP3Context* context = (MP3Context*)userData;
                return DKSTREAM_READ(context->stream, buf, size);
            };
            context->io.seek = [](uint64_t position, void *userData)->int
            {
                MP3Context* context = (MP3Context*)userData;
                if (DKSTREAM_SET_POSITION(context->stream, position) == DKSTREAM_ERROR)
                    return -1;
                return 0;
            };

            result = mp3dec_ex_open_cb(&context->dec, &context->io, MP3D_SEEK_TO_SAMPLE);
        }
        else
        {
            // copy buffer
            context->buffer.reserve(DKSTREAM_TOTAL_LENGTH(stream));
            char buff[8192];
            while (true)
            {
                int read = DKSTREAM_READ(stream, buff, 8192);
                if (read <= 0)  break;
                context->buffer.insert(context->buffer.end(), buff, buff+read);
            }
            context->buffer.shrink_to_fit();

            result = mp3dec_ex_open_buf(&context->dec, context->buffer.data(), context->buffer.size(), MP3D_SEEK_TO_SAMPLE);
        }

        if (result == 0)
        {
            DKAudioStream* audioStream = (DKAudioStream*)DKMalloc(sizeof(DKAudioStream));
            memset(audioStream, 0, sizeof(DKAudioStream));

            audioStream->decoder = reinterpret_cast<void*>(context);

            audioStream->mediaType = DKAudioStreamEncodingFormat_MP3;
            audioStream->channels = context->dec.info.channels;
            audioStream->sampleRate = context->dec.info.hz;
            audioStream->bits = sizeof(mp3d_sample_t) << 3;
            audioStream->seekable = true;

            audioStream->read = DKAudioStreamMP3Read;
            audioStream->seekRaw = DKAudioStreamMP3SeekRaw;
            audioStream->seekPcm = DKAudioStreamMP3SeekPcm;
            audioStream->seekTime = DKAudioStreamMP3SeekTime;
            audioStream->rawPosition = DKAudioStreamMP3RawPosition;
            audioStream->pcmPosition = DKAudioStreamMP3PcmPosition;
            audioStream->timePosition = DKAudioStreamMP3TimePosition;
            audioStream->rawTotal = DKAudioStreamMP3RawTotal;
            audioStream->pcmTotal = DKAudioStreamMP3PcmTotal;
            audioStream->timeTotal = DKAudioStreamMP3TimeTotal;

            return audioStream; 
        }

        context->stream = nullptr;
        context->~MP3Context();
        DKFree(context);
    }
    return nullptr;
}

void DKAudioStreamMP3Destroy(DKAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    mp3dec_ex_close(&context->dec);
    context->~MP3Context();
#if DEBUG
    memset(context, 0, sizeof(MP3Context));
    memset(stream, 0, sizeof(DKAudioStream));
#endif    
    DKFree(context);
    DKFree(stream);
}
