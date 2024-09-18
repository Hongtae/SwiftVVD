/*******************************************************************************
 File: AudioStreamMP3.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#include <vector>
#define MINIMP3_IMPLEMENTATION
#include "../minimp3/minimp3_ex.h"

#include "AudioStream.h"
#include "Malloc.h"
#include "Log.h"

namespace {
    struct MP3Context
    {
        VVDStream* stream;
        mp3dec_ex_t dec;
        mp3dec_io_t io;
        std::vector<uint8_t> buffer;
    };
}

uint64_t VVDAudioStreamMP3Read(VVDAudioStream* stream, void* buffer, size_t size)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    size_t numSamples = size / sizeof(mp3d_sample_t);
    size_t samples = mp3dec_ex_read(&context->dec, (mp3d_sample_t*)buffer, numSamples);
    if (samples != numSamples) /* normal eof or error condition */
    {
        if (context->dec.last_error)
        {
            /* error */
            VVDLogE("AudioStreamMP3: Read error! (%x)\n", context->dec.last_error);

            if (samples == 0)
                return -1;
        }
    }
    return samples * sizeof(mp3d_sample_t);
}

uint64_t VVDAudioStreamMP3SeekRaw(VVDAudioStream* stream, uint64_t pos)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    pos = pos / sizeof(mp3d_sample_t);
    if (pos > context->dec.samples)
        pos = context->dec.samples;

    int result = mp3dec_ex_seek(&context->dec, pos);
    if (result)
    {
        VVDLogE("AudioStreamMP3: Seek error! (%x)\n", result);
        return VVDSTREAM_ERROR;
    }
    return (context->dec.offset - context->dec.start_offset);
}

uint64_t VVDAudioStreamMP3SeekPcm(VVDAudioStream* stream, uint64_t pos)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    if (pos > context->dec.samples)
        pos = context->dec.samples;

    int result = mp3dec_ex_seek(&context->dec, pos);
    if (result)
    {
        VVDLogE("AudioStreamMP3: Seek error! (%x)\n", result);
        return VVDSTREAM_ERROR;
    }
    return (context->dec.offset - context->dec.start_offset) / sizeof(mp3d_sample_t);
}

double VVDAudioStreamMP3SeekTime(VVDAudioStream* stream, double t)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    uint64_t pos = uint64_t(double(context->dec.info.hz) * t);
    if (pos > context->dec.samples)
        pos = context->dec.samples;

    int result = mp3dec_ex_seek(&context->dec, pos);
    if (result)
    {
        VVDLogE("AudioStreamMP3: Seek error! (%x)\n", result);
        return -1.0;
    }
    return t;
}

uint64_t VVDAudioStreamMP3RawPosition(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.cur_sample * sizeof(mp3d_sample_t);
}

uint64_t VVDAudioStreamMP3PcmPosition(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.cur_sample;
}

double VVDAudioStreamMP3TimePosition(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    double freq = double(context->dec.info.hz);
    double t = double(context->dec.cur_sample) / freq;
    return t;
}

uint64_t VVDAudioStreamMP3RawTotal(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.samples * sizeof(mp3d_sample_t);
}

uint64_t VVDAudioStreamMP3PcmTotal(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    return context->dec.samples;
}

double VVDAudioStreamMP3TimeTotal(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    double freq = double(context->dec.info.hz);
    double t = double(context->dec.samples) / freq;
    return t;
}

VVDAudioStream* VVDAudioStreamMP3Create(VVDStream* stream)
{
    if (stream && VVDSTREAM_IS_READABLE(stream))
    {
        MP3Context* context = (MP3Context*)VVDMalloc(sizeof(MP3Context));
        memset(context, 0, sizeof(MP3Context));
        new(context) MP3Context();

        context->stream = stream;

        int result = -1;

        if (VVDSTREAM_IS_SEEKABLE(stream))
        {
            context->io.read_data = (void*)context;
            context->io.seek_data = (void*)context;
            context->io.read = [](void *buf, size_t size, void *userData)->size_t
            {
                MP3Context* context = (MP3Context*)userData;
                return VVDSTREAM_READ(context->stream, buf, size);
            };
            context->io.seek = [](uint64_t position, void *userData)->int
            {
                MP3Context* context = (MP3Context*)userData;
                if (VVDSTREAM_SET_POSITION(context->stream, position) == VVDSTREAM_ERROR)
                    return -1;
                return 0;
            };

            result = mp3dec_ex_open_cb(&context->dec, &context->io, MP3D_SEEK_TO_SAMPLE);
        }
        else
        {
            // copy buffer
            context->buffer.reserve(VVDSTREAM_TOTAL_LENGTH(stream));
            char buff[8192];
            while (true)
            {
                int read = VVDSTREAM_READ(stream, buff, 8192);
                if (read <= 0)  break;
                context->buffer.insert(context->buffer.end(), buff, buff+read);
            }
            context->buffer.shrink_to_fit();

            result = mp3dec_ex_open_buf(&context->dec, context->buffer.data(), context->buffer.size(), MP3D_SEEK_TO_SAMPLE);
        }

        if (result == 0)
        {
            VVDAudioStream* audioStream = (VVDAudioStream*)VVDMalloc(sizeof(VVDAudioStream));
            memset(audioStream, 0, sizeof(VVDAudioStream));

            audioStream->decoder = reinterpret_cast<void*>(context);

            audioStream->mediaType = VVDAudioStreamEncodingFormat_MP3;
            audioStream->channels = context->dec.info.channels;
            audioStream->sampleRate = context->dec.info.hz;
            audioStream->bits = sizeof(mp3d_sample_t) << 3;
            audioStream->seekable = true;

            audioStream->read = VVDAudioStreamMP3Read;
            audioStream->seekRaw = VVDAudioStreamMP3SeekRaw;
            audioStream->seekPcm = VVDAudioStreamMP3SeekPcm;
            audioStream->seekTime = VVDAudioStreamMP3SeekTime;
            audioStream->rawPosition = VVDAudioStreamMP3RawPosition;
            audioStream->pcmPosition = VVDAudioStreamMP3PcmPosition;
            audioStream->timePosition = VVDAudioStreamMP3TimePosition;
            audioStream->rawTotal = VVDAudioStreamMP3RawTotal;
            audioStream->pcmTotal = VVDAudioStreamMP3PcmTotal;
            audioStream->timeTotal = VVDAudioStreamMP3TimeTotal;

            return audioStream; 
        }

        context->stream = nullptr;
        context->~MP3Context();
        VVDFree(context);
    }
    return nullptr;
}

void VVDAudioStreamMP3Destroy(VVDAudioStream* stream)
{
    MP3Context* context = reinterpret_cast<MP3Context*>(stream->decoder);
    mp3dec_ex_close(&context->dec);
    context->~MP3Context();
#if DEBUG
    memset(context, 0, sizeof(MP3Context));
    memset(stream, 0, sizeof(VVDAudioStream));
#endif    
    VVDFree(context);
    VVDFree(stream);
}
