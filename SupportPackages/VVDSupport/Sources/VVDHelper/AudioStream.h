/*******************************************************************************
 File: AudioStream.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stdbool.h>

#include "Stream.h"

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef enum _VVDAudioStreamEncodingFormat
{
    VVDAudioStreamEncodingFormat_Unknown = 0,
    VVDAudioStreamEncodingFormat_OggVorbis,
    VVDAudioStreamEncodingFormat_OggFLAC,
    VVDAudioStreamEncodingFormat_FLAC,
    VVDAudioStreamEncodingFormat_MP3,
    VVDAudioStreamEncodingFormat_Wave,
} VVDAudioStreamEncodingFormat;

#define VVDAUDIO_IDENTIFY_FORMAT_HEADER_LENGTH 35 /* 32 for oggS-fLaC, 35 for oggS-vorbis */
#define VVDAUDIO_IDENTIFY_FORMAT_HEADER_MINIMUM_LENGTH 4 /* oggS, fLaC, RIFF */

VVDAudioStreamEncodingFormat VVDAudioStreamDetermineFormatFromHeader(char*, size_t);

struct _VVDAudioStream;
typedef uint64_t (*VVDAudioStreamReadFn)(struct _VVDAudioStream*, void*, size_t);

typedef uint64_t (*VVDAudioStreamSeekRawFn)(struct _VVDAudioStream*, uint64_t);
typedef uint64_t (*VVDAudioStreamSeekPcmFn)(struct _VVDAudioStream*, uint64_t);
typedef double   (*VVDAudioStreamSeekTimeFn)(struct _VVDAudioStream*, double);

typedef uint64_t (*VVDAudioStreamRawPositionFn)(struct _VVDAudioStream*);
typedef uint64_t (*VVDAudioStreamPcmPositionFn)(struct _VVDAudioStream*);
typedef double   (*VVDAudioStreamTimePositionFn)(struct _VVDAudioStream*);

typedef uint64_t (*VVDAudioStreamRawTotalFn)(struct _VVDAudioStream*);
typedef uint64_t (*VVDAudioStreamPcmTotalFn)(struct _VVDAudioStream*);
typedef double (*VVDAudioStreamTimeTotalFn)(struct _VVDAudioStream*);

typedef struct _VVDAudioStream
{
    void* userContext;
    
    bool seekable;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t bits;
    VVDAudioStreamEncodingFormat mediaType;

    VVDAudioStreamReadFn read;
    VVDAudioStreamSeekRawFn seekRaw;
    VVDAudioStreamSeekPcmFn seekPcm;
    VVDAudioStreamSeekTimeFn seekTime;

    VVDAudioStreamRawPositionFn rawPosition;
    VVDAudioStreamPcmPositionFn pcmPosition;
    VVDAudioStreamTimePositionFn timePosition;

    VVDAudioStreamRawTotalFn rawTotal;
    VVDAudioStreamPcmTotalFn pcmTotal;
    VVDAudioStreamTimeTotalFn timeTotal;

    void* decoder;
} VVDAudioStream;

#define VVDAUDIO_STREAM_READ(stream, p, s)     (stream)->read((stream), (p), (s))
#define VVDAUDIO_STREAM_SEEK_RAW(stream, s)    (stream)->seekRaw((stream), (s))
#define VVDAUDIO_STREAM_SEEK_PCM(stream, s)    (stream)->seekPcm((stream), (s))
#define VVDAUDIO_STREAM_SEEK_TIME(stream, t)   (stream)->seekTime((stream), (t))
#define VVDAUDIO_STREAM_RAW_POSITION(stream)   (stream)->rawPosition((stream))
#define VVDAUDIO_STREAM_PCM_POSITION(stream)   (stream)->pcmPosition((stream))
#define VVDAUDIO_STREAM_TIME_POSITION(stream)  (stream)->timePosition((stream))
#define VVDAUDIO_STREAM_RAW_TOTAL(stream)      (stream)->rawTotal((stream))
#define VVDAUDIO_STREAM_PCM_TOTAL(stream)      (stream)->pcmTotal((stream))
#define VVDAUDIO_STREAM_TIME_TOTAL(stream)     (stream)->timeTotal((stream))

VVDAudioStream* VVDAudioStreamCreate(VVDStream*);
void VVDAudioStreamDestroy(VVDAudioStream*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
