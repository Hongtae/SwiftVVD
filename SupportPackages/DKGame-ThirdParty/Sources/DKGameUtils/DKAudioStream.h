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
    DKAudioStreamEncodingFormatUnknown = 0,
    DKAudioStreamEncodingFormatOggVorbis,
    DKAudioStreamEncodingFormatOggFLAC,
    DKAudioStreamEncodingFormatFLAC,
    DKAudioStreamEncodingFormatWave,
} DKAudioStreamEncodingFormat;

#define DKAUDIO_IDENTIFY_FORMAT_HEADER_LENGTH 35 /* 32 for oggS-fLaC, 35 for oggS-vorbis */
#define DKAUDIO_IDENTIFY_FORMAT_HEADER_MINIMUM_LENGTH 4 /* oggS, fLaC, RIFF */

DKAudioStreamEncodingFormat DKAudioDetermineFormatFromHeader(char*, size_t);

typedef void* DKAudioStreamContext;
typedef uint64_t (*DKAudioStreamRead)(DKAudioStreamContext, void*, size_t);
typedef uint64_t (*DKAudioStreamSeekRaw)(DKAudioStreamContext, uint64_t);
typedef uint64_t (*DKAudioStreamSeekPcm)(DKAudioStreamContext, uint64_t);
typedef double   (*DKAudioStreamSeekTime)(DKAudioStreamContext, double);

typedef uint64_t (*DKAudioStreamRawPosition)(DKAudioStreamContext);
typedef uint64_t (*DKAudioStreamPcmPosition)(DKAudioStreamContext);
typedef double   (*DKAudioStreamTimePosition)(DKAudioStreamContext);

typedef uint64_t (*DKAudioStreamRawTotal)(DKAudioStreamContext);
typedef uint64_t (*DKAudioStreamPcmTotal)(DKAudioStreamContext);
typedef double (*DKAudioStreamTimeTotal)(DKAudioStreamContext);

typedef struct _DKAudioStream
{
    DKAudioStreamContext userContext;
    
    bool seekable;
    uint32_t frequency;
    uint32_t channels;
    uint32_t bits;
    DKAudioStreamEncodingFormat mediaType;

    DKAudioStreamRead read;
    DKAudioStreamSeekRaw seekRaw;
    DKAudioStreamSeekPcm seekPcm;
    DKAudioStreamSeekTime seekTime;

    DKAudioStreamRawPosition rawPosition;
    DKAudioStreamPcmPosition pcmPosition;
    DKAudioStreamTimePosition timePosition;

    DKAudioStreamRawTotal rawTotal;
    DKAudioStreamPcmTotal pcmTotal;
    DKAudioStreamTimeTotal timeTotal;

    void* decoder;
} DKAudioStream;

DKAudioStream* DKAudioStreamCreate(DKStream*);
void DKAudioStreamDestroy(DKAudioStream*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
