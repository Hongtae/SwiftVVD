/*******************************************************************************
 File: DKAudioStreamFLAC.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include <vector>
#include <algorithm>
#include <string.h>
#include "../libFLAC/include/FLAC/stream_decoder.h"

#include "DKAudioStream.h"
#include "DKMalloc.h"
#include "DKLog.h"

namespace {
    struct FLAC_Context
    {
        FLAC__StreamDecoder* decoder;
        DKStream* stream;

        FLAC__uint64 totalSamples;
        FLAC__uint64 sampleNumber;
        unsigned int sampleRate;
        unsigned int channels;
        unsigned int bps;

        std::vector<FLAC__int32> buffer;
    };

    FLAC__StreamDecoderReadStatus FLAC_Read(const FLAC__StreamDecoder *decoder, FLAC__byte buffer[], size_t *bytes, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        if (ctxt->stream)
        {
            if (*bytes > 0)
            {
                *bytes = DKSTREAM_READ(ctxt->stream, buffer, *bytes);
                if (*bytes == (size_t)-1)
                return FLAC__STREAM_DECODER_READ_STATUS_ABORT;
                else if (*bytes == 0)
                return FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM;
                else
                return FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
            }
        }
        return FLAC__STREAM_DECODER_READ_STATUS_ABORT;
    }

    FLAC__StreamDecoderSeekStatus FLAC_Seek(const FLAC__StreamDecoder *decoder, FLAC__uint64 absolute_byte_offset, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        if (ctxt->stream)
        {
            if (DKSTREAM_IS_SEEKABLE(ctxt->stream))
            {
                uint64_t pos = DKSTREAM_SET_POSITION(ctxt->stream, absolute_byte_offset);
                if (pos == absolute_byte_offset)
                return FLAC__STREAM_DECODER_SEEK_STATUS_OK;
                return FLAC__STREAM_DECODER_SEEK_STATUS_ERROR;
            }
            return FLAC__STREAM_DECODER_SEEK_STATUS_UNSUPPORTED;
        }
        return FLAC__STREAM_DECODER_SEEK_STATUS_ERROR;
    }

    FLAC__StreamDecoderTellStatus FLAC_Tell(const FLAC__StreamDecoder *decoder, FLAC__uint64 *absolute_byte_offset, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        if (ctxt->stream)
        {
            if (DKSTREAM_IS_SEEKABLE(ctxt->stream))
            {
                *absolute_byte_offset = (FLAC__uint64)DKSTREAM_GET_POSITION(ctxt->stream);
                return FLAC__STREAM_DECODER_TELL_STATUS_OK;
            }
            return FLAC__STREAM_DECODER_TELL_STATUS_UNSUPPORTED;
        }
        return FLAC__STREAM_DECODER_TELL_STATUS_ERROR;
    }

    FLAC__StreamDecoderLengthStatus FLAC_Length(const FLAC__StreamDecoder *decoder, FLAC__uint64 *stream_length, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        if (ctxt->stream)
        {
            if (DKSTREAM_IS_SEEKABLE(ctxt->stream) && DKSTREAM_HAS_LENGTH(ctxt->stream))
            {
                *stream_length = (FLAC__uint64)DKSTREAM_TOTAL_LENGTH(ctxt->stream);
                return FLAC__STREAM_DECODER_LENGTH_STATUS_OK;
            }
            return FLAC__STREAM_DECODER_LENGTH_STATUS_UNSUPPORTED;
        }
        return FLAC__STREAM_DECODER_LENGTH_STATUS_ERROR;
    }

    FLAC__bool FLAC_IsEOF(const FLAC__StreamDecoder *decoder, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        if (ctxt->stream)
        {
            if (DKSTREAM_HAS_LENGTH(ctxt->stream))
                return (DKSTREAM_REMAIN_LENGTH(ctxt->stream) > 0) ? false : true;
        }
        return false;
    }

    FLAC__StreamDecoderWriteStatus FLAC_Write(const FLAC__StreamDecoder *decoder, const FLAC__Frame *frame, const FLAC__int32 *const buffer[], void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        if (ctxt->channels == frame->header.channels && ctxt->bps == frame->header.bits_per_sample && ctxt->sampleRate == frame->header.sample_rate)
        {
            // add to audio buffer.
            size_t blockSize = frame->header.blocksize;
            size_t buffSize = ctxt->buffer.size();

            ctxt->sampleNumber = frame->header.number.sample_number;
            ctxt->buffer.reserve(buffSize + (blockSize * frame->header.channels));
            for (unsigned int i = 0; i < frame->header.blocksize; ++i)
            {
                for (unsigned int ch = 0; ch < frame->header.channels; ++ch)
                {
                    ctxt->buffer.push_back(buffer[ch][i]);
                }
            }
            return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
        }
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }

    void FLAC_Metadata(const FLAC__StreamDecoder *decoder, const FLAC__StreamMetadata *metadata, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        //DKASSERT_DEBUG(ctxt != NULL);

        DKLog("FLAC_Metadata (contxt:%p):%s \n", ctxt, FLAC__MetadataTypeString[metadata->type]);

        if(metadata->type == FLAC__METADATA_TYPE_STREAMINFO)
        {
            ctxt->totalSamples = metadata->data.stream_info.total_samples;
            ctxt->sampleRate = metadata->data.stream_info.sample_rate;
            ctxt->channels = metadata->data.stream_info.channels;
            ctxt->bps = metadata->data.stream_info.bits_per_sample;

            DKLog("FLAC_Metadata total samples: %llu\n", (unsigned long long)ctxt->totalSamples);
            DKLog("FLAC_Metadata sample rate: %u Hz\n", ctxt->sampleRate);
            DKLog("FLAC_Metadata channels: %u\n", ctxt->channels);
            DKLog("FLAC_Metadata bits per sample: %u\n", ctxt->bps);
        }
    }

    void FLAC_Error(const FLAC__StreamDecoder *decoder, FLAC__StreamDecoderErrorStatus status, void *client_data)
    {
        FLAC_Context* ctxt = reinterpret_cast<FLAC_Context*>(client_data);
        DKLogE("FLAC_Error (context:%p): %s\n", ctxt, FLAC__StreamDecoderErrorStatusString[status]);
    }

    bool FLAC_InitMetadata(DKAudioStream* stream, FLAC_Context* context)
    {
        // DKASSERT_DEBUG(context);
        // DKASSERT_DEBUG(context->decoder);

        if (FLAC__stream_decoder_process_until_end_of_metadata(context->decoder))
        {
            if ((context->bps == 8 || context->bps == 16 || context->bps == 24) &&
                (context->totalSamples > 0 && context->sampleRate > 0 && context->channels > 0))
            {
                stream->channels = context->channels;
                stream->sampleRate = context->sampleRate;
                stream->seekable = DKSTREAM_IS_SEEKABLE(context->stream);

                switch (context->bps)
                {
                case 8:
                case 16:
                    stream->bits = context->bps;
                case 24:
                    stream->bits = 16; // convert to 16 bits internally.
                    break;
                default:
                    DKLogE("FLAC Unsupported bps:%u.\n", context->bps);
                    return false;
                }
                return true;
            }
            else
            {
                DKLogE("FLAC Unsupported stream! (bps:%u, freq:%u, channels:%u)\n", context->bps, context->sampleRate, context->channels);
            }
        }
        else
        {
            FLAC__StreamDecoderState st = FLAC__stream_decoder_get_state(context->decoder);
            DKLogE("FLAC__stream_decoder_process_until_end_of_metadata failed. (state:%s)\n", FLAC__StreamDecoderStateString[st]);
        }
        return false;
    }
}

uint64_t DKAudioStreamFLACRead(DKAudioStream* stream, void* buffer, size_t size)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        // reading until buffer become full
        while ( context->buffer.size() < size )
        {
            if (FLAC__stream_decoder_process_single(context->decoder))
            {
                FLAC__StreamDecoderState st = FLAC__stream_decoder_get_state(context->decoder);
                if (st == FLAC__STREAM_DECODER_END_OF_STREAM || st == FLAC__STREAM_DECODER_ABORTED)
                {
                    DKLog("FLAC State:%s\n", FLAC__StreamDecoderStateString[st]);
                    break;
                }
            }
            else
            {
                FLAC__StreamDecoderState st = FLAC__stream_decoder_get_state(context->decoder);
                DKLog("FLAC__stream_decoder_process_single failed. (state:%s)\n", FLAC__StreamDecoderStateString[st]);
                break;
            }
        }

        size_t numSamples = context->buffer.size();
        if (numSamples > 0)
        {
            size_t copiedSamples = 0;
            size_t bytesCopied = 0;

            FLAC__int32* p = (FLAC__int32*)context->buffer.data();

            if (context->bps == 8)
            {
                for (copiedSamples = 0; (bytesCopied + 1) < size && copiedSamples < numSamples ; ++copiedSamples)
                {
                    reinterpret_cast<FLAC__int8*>(buffer)[copiedSamples] = static_cast<FLAC__int8>(p[copiedSamples]);
                    bytesCopied += 1;
                }
            }
            else if (context->bps == 16)
            {
                for (copiedSamples = 0; (bytesCopied + 2) <= size && copiedSamples < numSamples ; ++copiedSamples)
                {
                    reinterpret_cast<FLAC__int16*>(buffer)[copiedSamples] = static_cast<FLAC__int16>(p[copiedSamples]);
                    bytesCopied += 2;
                }
            }
            else if (context->bps == 24)
            {
                static_assert(sizeof(FLAC__int16) == sizeof(short), "size mismatch?");

                for (copiedSamples = 0; (bytesCopied + 2) <= size && copiedSamples < numSamples; ++copiedSamples)
                {
                    // float has 23bits fraction (on IEEE754)
                    // which can have int24(23+1) without loss.
                    float sig = static_cast<float>(p[copiedSamples]);
                    sig = (sig / float(1<<23)) * float(1<<15);      // int24 -> float -> int16.
                    FLAC__int16 sample = (FLAC__int16)std::clamp<int>( (sig+0.5), -32768, 32767);
                    reinterpret_cast<FLAC__int16*>(buffer)[copiedSamples] = sample;
                    bytesCopied += 2;
                }
            }
            else
            {
                //DKERROR_THROW_DEBUG("Unsupported bps!");
                DKLogE("FLAC: Unsupported bps!\n");
                context->buffer.clear();
                return -1;
            }
            context->buffer.erase(context->buffer.begin(), context->buffer.begin() + copiedSamples);
            return bytesCopied;
        }
    }
    return -1;
}

uint64_t DKAudioStreamFLACSeekRaw(DKAudioStream* stream, uint64_t pos)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        pos = (pos / context->channels) / (context->bps / 8);   // raw to pcm(sample)
        pos = std::clamp<uint64_t>(pos, 0, context->totalSamples);
        if (FLAC__stream_decoder_seek_absolute(context->decoder, pos))
        {
            FLAC__stream_decoder_process_single(context->decoder);
            return pos * context->channels * (context->bps / 8);
        }
        else
        {
            FLAC__StreamDecoderState st = FLAC__stream_decoder_get_state(context->decoder);
            DKLog("FLAC__stream_decoder_process_until_end_of_metadata failed:%s\n", FLAC__StreamDecoderStateString[st]);
            if (st == FLAC__STREAM_DECODER_SEEK_ERROR)
                FLAC__stream_decoder_flush(context->decoder);
        }
    }
    return 0;
}

uint64_t DKAudioStreamFLACSeekPcm(DKAudioStream* stream, uint64_t pos)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        pos = std::clamp<uint64_t>(pos, 0, context->totalSamples);
        if (FLAC__stream_decoder_seek_absolute(context->decoder, pos))
        {
            FLAC__stream_decoder_process_single(context->decoder);
            return pos;
        }
        else
        {
            FLAC__StreamDecoderState st = FLAC__stream_decoder_get_state(context->decoder);
            DKLog("FLAC__stream_decoder_process_until_end_of_metadata failed:%s\n", FLAC__StreamDecoderStateString[st]);
            if (st == FLAC__STREAM_DECODER_SEEK_ERROR)
                FLAC__stream_decoder_flush(context->decoder);
        }
    }
    return 0;
}

double DKAudioStreamFLACSeekTime(DKAudioStream* stream, double t)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        FLAC__uint64 pos = t * context->sampleRate;
        pos = std::clamp<uint64_t>(pos, 0, context->totalSamples);
        if (FLAC__stream_decoder_seek_absolute(context->decoder, pos))
        {
            FLAC__stream_decoder_process_single(context->decoder);
            return static_cast<double>(pos) / context->sampleRate;
        }
        else
        {
            FLAC__StreamDecoderState st = FLAC__stream_decoder_get_state(context->decoder);
            DKLogE("FLAC__stream_decoder_process_until_end_of_metadata failed:%s\n", FLAC__StreamDecoderStateString[st]);
            if (st == FLAC__STREAM_DECODER_SEEK_ERROR)
                FLAC__stream_decoder_flush(context->decoder);
        }
    }
    return 0;
}

uint64_t DKAudioStreamFLACRawPosition(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        uint64_t pos = context->sampleNumber;
        uint64_t samplesRemain = context->buffer.size() / context->channels;
        if (pos >= samplesRemain)
            pos -= samplesRemain;
        return pos * context->channels * (context->bps / 8);
    }
    return 0;
}

uint64_t DKAudioStreamFLACPcmPosition(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        uint64_t pos = context->sampleNumber;
        uint64_t samplesRemain = context->buffer.size() / context->channels;
        if (pos >= samplesRemain)
            pos -= samplesRemain;
        return pos;
    }
    return 0;
}

double DKAudioStreamFLACTimePosition(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        uint64_t pos = context->sampleNumber;
        uint64_t samplesRemain = context->buffer.size() / context->channels;
        if (pos >= samplesRemain)
            pos -= samplesRemain;
        return static_cast<double>(pos) / static_cast<double>(context->sampleRate);
    }
    return 0;
}

uint64_t DKAudioStreamFLACRawTotal(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        return context->totalSamples * context->channels * (context->bps / 8);
    }
    return 0;
}

uint64_t DKAudioStreamFLACPcmTotal(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        return context->totalSamples;
    }
    return 0;
}

double DKAudioStreamFLACTimeTotal(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        return static_cast<double>(context->totalSamples) / static_cast<double>(context->sampleRate);
    }
    return 0;
}

DKAudioStream* DKAudioStreamFLACCreate(DKStream* stream)
{
    if (stream && DKSTREAM_IS_READABLE(stream))
    {
        FLAC_Context* context = (FLAC_Context*)DKMalloc(sizeof(FLAC_Context));
        memset(context, 0, sizeof(FLAC_Context));
        new(context) FLAC_Context();

        context->stream = stream;
        context->decoder = FLAC__stream_decoder_new();

        FLAC__StreamDecoderInitStatus st = FLAC__stream_decoder_init_stream(context->decoder,
            FLAC_Read,
            FLAC_Seek,
            FLAC_Tell,
            FLAC_Length,
            FLAC_IsEOF,
            FLAC_Write,
            FLAC_Metadata,
            FLAC_Error,
            context);

        if (st == FLAC__STREAM_DECODER_INIT_STATUS_OK)
        {
            DKAudioStream* audioStream = (DKAudioStream*)DKMalloc(sizeof(DKAudioStream));
            memset(audioStream, 0, sizeof(DKAudioStream));
            audioStream->mediaType = DKAudioStreamEncodingFormat_FLAC;
            audioStream->decoder = reinterpret_cast<void*>(context);

            if (FLAC_InitMetadata(audioStream, context))
            {
                audioStream->read = DKAudioStreamFLACRead;
                audioStream->seekRaw = DKAudioStreamFLACSeekRaw;
                audioStream->seekPcm = DKAudioStreamFLACSeekPcm;
                audioStream->seekTime = DKAudioStreamFLACSeekTime;
                audioStream->rawPosition = DKAudioStreamFLACRawPosition;
                audioStream->pcmPosition = DKAudioStreamFLACPcmPosition;
                audioStream->timePosition = DKAudioStreamFLACTimePosition;
                audioStream->rawTotal = DKAudioStreamFLACRawTotal;
                audioStream->pcmTotal = DKAudioStreamFLACPcmTotal;
                audioStream->timeTotal = DKAudioStreamFLACTimeTotal;
                return audioStream;
            }
            FLAC__stream_decoder_finish(context->decoder);
        }
        else
        {
            DKLog("FLAC__stream_decoder_init_stream failed:%s\n", FLAC__StreamDecoderInitStatusString[st]);
        }
        FLAC__stream_decoder_delete(context->decoder);
        context->stream = NULL;
        context->decoder = NULL;
        context->~FLAC_Context();
        DKFree(context);
    }
    return nullptr;
}

DKAudioStream* DKAudioStreamOggFLACCreate(DKStream* stream)
{
    if (stream && DKSTREAM_IS_READABLE(stream))
    {
        FLAC_Context* context = (FLAC_Context*)DKMalloc(sizeof(FLAC_Context));
        memset(context, 0, sizeof(FLAC_Context));
        new(context) FLAC_Context();

        context->stream = stream;
        context->decoder = FLAC__stream_decoder_new();

        FLAC__StreamDecoderInitStatus st = FLAC__stream_decoder_init_ogg_stream(context->decoder,
            FLAC_Read,
            FLAC_Seek,
            FLAC_Tell,
            FLAC_Length,
            FLAC_IsEOF,
            FLAC_Write,
            FLAC_Metadata,
            FLAC_Error,
            context);

        if (st == FLAC__STREAM_DECODER_INIT_STATUS_OK)
        {
            DKAudioStream* audioStream = (DKAudioStream*)DKMalloc(sizeof(DKAudioStream));
            memset(audioStream, 0, sizeof(DKAudioStream));
            audioStream->mediaType = DKAudioStreamEncodingFormat_OggFLAC;
            audioStream->decoder = reinterpret_cast<void*>(context);

            if (FLAC_InitMetadata(audioStream, context))
            {
                audioStream->read = DKAudioStreamFLACRead;
                audioStream->seekRaw = DKAudioStreamFLACSeekRaw;
                audioStream->seekPcm = DKAudioStreamFLACSeekPcm;
                audioStream->seekTime = DKAudioStreamFLACSeekTime;
                audioStream->rawPosition = DKAudioStreamFLACRawPosition;
                audioStream->pcmPosition = DKAudioStreamFLACPcmPosition;
                audioStream->timePosition = DKAudioStreamFLACTimePosition;
                audioStream->rawTotal = DKAudioStreamFLACRawTotal;
                audioStream->pcmTotal = DKAudioStreamFLACPcmTotal;
                audioStream->timeTotal = DKAudioStreamFLACTimeTotal;
                return audioStream;
            }
            FLAC__stream_decoder_finish(context->decoder);
        }
        else
        {
            DKLogE("FLAC__stream_decoder_init_stream failed:%s\n", FLAC__StreamDecoderInitStatusString[st]);
        }
        FLAC__stream_decoder_delete(context->decoder);
        context->stream = NULL;
        context->decoder = NULL;
        context->~FLAC_Context();
        DKFree(context);
    }
    return nullptr;
}

void DKAudioStreamFLACDestroy(DKAudioStream* stream)
{
    FLAC_Context* context = reinterpret_cast<FLAC_Context*>(stream->decoder);
    if (context->decoder)
    {
        FLAC__stream_decoder_finish(context->decoder);
        FLAC__stream_decoder_delete(context->decoder);
    }
    context->~FLAC_Context();
#if DEBUG
    memset(context, 0, sizeof(FLAC_Context));
    memset(stream, 0, sizeof(DKAudioStream));
#endif 
    DKFree(context);
    DKFree(stream);
}

void DKAudioStreamOggFLACDestroy(DKAudioStream* stream)
{
    DKAudioStreamFLACDestroy(stream);
}
