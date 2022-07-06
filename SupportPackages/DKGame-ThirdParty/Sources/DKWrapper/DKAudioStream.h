/*******************************************************************************
 File: DKAudioStream.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stdbool.h>

#include "DKStream.h"

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef enum _DKAudioStreamEncodingFormat
{
    DKAudioStreamEncodingFormat_Unknown = 0,
    DKAudioStreamEncodingFormat_OggVorbis,
    DKAudioStreamEncodingFormat_OggFLAC,
    DKAudioStreamEncodingFormat_FLAC,
    DKAudioStreamEncodingFormat_MP3,
    DKAudioStreamEncodingFormat_Wave,
} DKAudioStreamEncodingFormat;

#define DKAUDIO_IDENTIFY_FORMAT_HEADER_LENGTH 35 /* 32 for oggS-fLaC, 35 for oggS-vorbis */
#define DKAUDIO_IDENTIFY_FORMAT_HEADER_MINIMUM_LENGTH 4 /* oggS, fLaC, RIFF */

DKAudioStreamEncodingFormat DKAudioStreamDetermineFormatFromHeader(char*, size_t);

struct _DKAudioStream;
typedef uint64_t (*DKAudioStreamReadFn)(struct _DKAudioStream*, void*, size_t);

typedef uint64_t (*DKAudioStreamSeekRawFn)(struct _DKAudioStream*, uint64_t);
typedef uint64_t (*DKAudioStreamSeekPcmFn)(struct _DKAudioStream*, uint64_t);
typedef double   (*DKAudioStreamSeekTimeFn)(struct _DKAudioStream*, double);

typedef uint64_t (*DKAudioStreamRawPositionFn)(struct _DKAudioStream*);
typedef uint64_t (*DKAudioStreamPcmPositionFn)(struct _DKAudioStream*);
typedef double   (*DKAudioStreamTimePositionFn)(struct _DKAudioStream*);

typedef uint64_t (*DKAudioStreamRawTotalFn)(struct _DKAudioStream*);
typedef uint64_t (*DKAudioStreamPcmTotalFn)(struct _DKAudioStream*);
typedef double (*DKAudioStreamTimeTotalFn)(struct _DKAudioStream*);

typedef struct _DKAudioStream
{
    void* userContext;
    
    bool seekable;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t bits;
    DKAudioStreamEncodingFormat mediaType;

    DKAudioStreamReadFn read;
    DKAudioStreamSeekRawFn seekRaw;
    DKAudioStreamSeekPcmFn seekPcm;
    DKAudioStreamSeekTimeFn seekTime;

    DKAudioStreamRawPositionFn rawPosition;
    DKAudioStreamPcmPositionFn pcmPosition;
    DKAudioStreamTimePositionFn timePosition;

    DKAudioStreamRawTotalFn rawTotal;
    DKAudioStreamPcmTotalFn pcmTotal;
    DKAudioStreamTimeTotalFn timeTotal;

    void* decoder;
} DKAudioStream;

#define DKAUDIO_STREAM_READ(stream, p, s)     (stream)->read((stream), (p), (s))
#define DKAUDIO_STREAM_SEEK_RAW(stream, s)    (stream)->seekRaw((stream), (s))
#define DKAUDIO_STREAM_SEEK_PCM(stream, s)    (stream)->seekPcm((stream), (s))
#define DKAUDIO_STREAM_SEEK_TIME(stream, t)   (stream)->seekTime((stream), (t))
#define DKAUDIO_STREAM_RAW_POSITION(stream)   (stream)->rawPosition((stream))
#define DKAUDIO_STREAM_PCM_POSITION(stream)   (stream)->pcmPosition((stream))
#define DKAUDIO_STREAM_TIME_POSITION(stream)  (stream)->timePosition((stream))
#define DKAUDIO_STREAM_RAW_TOTAL(stream)      (stream)->rawTotal((stream))
#define DKAUDIO_STREAM_PCM_TOTAL(stream)      (stream)->pcmTotal((stream))
#define DKAUDIO_STREAM_TIME_TOTAL(stream)     (stream)->timeTotal((stream))

DKAudioStream* DKAudioStreamCreate(DKStream*);
void DKAudioStreamDestroy(DKAudioStream*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
