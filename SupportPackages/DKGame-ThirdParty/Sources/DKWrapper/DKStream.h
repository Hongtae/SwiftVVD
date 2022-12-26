/*******************************************************************************
 File: DKStream.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef void* DKStreamContext;
#define DKSTREAM_ERROR ~uint64_t(0)

typedef uint64_t (*DKStreamSetPosition)(DKStreamContext, uint64_t);
typedef uint64_t (*DKStreamGetPosition)(DKStreamContext);
typedef uint64_t (*DKStreamRemainLength)(DKStreamContext);
typedef uint64_t (*DKStreamTotalLength)(DKStreamContext);

typedef uint64_t (*DKStreamRead)(DKStreamContext, void*, size_t);
typedef uint64_t (*DKStreamWrite)(DKStreamContext, const void*, size_t);

typedef struct _DKStream
{
    DKStreamContext userContext;

    DKStreamRead read;
    DKStreamWrite write;
    DKStreamSetPosition setPosition;
    DKStreamGetPosition getPosition;

    DKStreamRemainLength remainLength;
    DKStreamTotalLength totalLength;
} DKStream;

#define DKSTREAM_READ(stream, p, s)         (stream)->read((stream)->userContext, (p), (s))
#define DKSTREAM_WRITE(stream, p, s)        (stream)->write((stream)->userContext, (p), (s))
#define DKSTREAM_SET_POSITION(stream, p)    (stream)->setPosition((stream)->userContext, (p))
#define DKSTREAM_GET_POSITION(stream)       (stream)->getPosition((stream)->userContext)
#define DKSTREAM_REMAIN_LENGTH(stream)      (stream)->remainLength((stream)->userContext)
#define DKSTREAM_TOTAL_LENGTH(stream)       (stream)->totalLength((stream)->userContext)

#define DKSTREAM_IS_READABLE(stream)        ((stream)->read)
#define DKSTREAM_IS_WRITABLE(stream)        ((stream)->write)
#define DKSTREAM_IS_SEEKABLE(stream)        ((stream)->setPosition && (stream)->getPosition)
#define DKSTREAM_HAS_LENGTH(stream)         ((stream)->remainLength && (stream)->totalLength)

#ifdef __cplusplus
}
#endif /* __cplusplus */
