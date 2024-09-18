/*******************************************************************************
 File: Stream.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef void* VVDStreamContext;
#define VVDSTREAM_ERROR ~uint64_t(0)

typedef uint64_t (*VVDStreamSetPosition)(VVDStreamContext, uint64_t);
typedef uint64_t (*VVDStreamGetPosition)(VVDStreamContext);
typedef uint64_t (*VVDStreamRemainLength)(VVDStreamContext);
typedef uint64_t (*VVDStreamTotalLength)(VVDStreamContext);

typedef uint64_t (*VVDStreamRead)(VVDStreamContext, void*, size_t);
typedef uint64_t (*VVDStreamWrite)(VVDStreamContext, const void*, size_t);

typedef struct _VVDStream
{
    VVDStreamContext userContext;

    VVDStreamRead read;
    VVDStreamWrite write;
    VVDStreamSetPosition setPosition;
    VVDStreamGetPosition getPosition;

    VVDStreamRemainLength remainLength;
    VVDStreamTotalLength totalLength;
} VVDStream;

#define VVDSTREAM_READ(stream, p, s)         (stream)->read((stream)->userContext, (p), (s))
#define VVDSTREAM_WRITE(stream, p, s)        (stream)->write((stream)->userContext, (p), (s))
#define VVDSTREAM_SET_POSITION(stream, p)    (stream)->setPosition((stream)->userContext, (p))
#define VVDSTREAM_GET_POSITION(stream)       (stream)->getPosition((stream)->userContext)
#define VVDSTREAM_REMAIN_LENGTH(stream)      (stream)->remainLength((stream)->userContext)
#define VVDSTREAM_TOTAL_LENGTH(stream)       (stream)->totalLength((stream)->userContext)

#define VVDSTREAM_IS_READABLE(stream)        ((stream)->read)
#define VVDSTREAM_IS_WRITABLE(stream)        ((stream)->write)
#define VVDSTREAM_IS_SEEKABLE(stream)        ((stream)->setPosition && (stream)->getPosition)
#define VVDSTREAM_HAS_LENGTH(stream)         ((stream)->remainLength && (stream)->totalLength)

#ifdef __cplusplus
}
#endif /* __cplusplus */
