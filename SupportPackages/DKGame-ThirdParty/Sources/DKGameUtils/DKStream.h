#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef void* DKStreamContext;
#define DKSTREAM_ERROR ~uint64_t(0)

typedef uint64_t (*DKStreamSetPosition)(DKStreamContext, uint64_t);
typedef uint64_t (*DKStreamGetPosition)(DKStreamContext);
typedef uint64_t (*DKStreamRemainLength)(DKStreamContext);

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

} DKStream;

#define DKSTREAM_READ(stream, p, s)         stream->read(stream->userContext, p, s)
#define DKSTREAM_WRITE(stream, p, s)        stream->write(stream->userContext, p, s)
#define DKSTREAM_SET_POSITION(stream, p)    stream->setPosition(stream->userContext, p)
#define DKSTREAM_GET_POSITION(stream)       stream->getPosition(stream->userContext)
#define DKSTREAM_REMAIN_LENGTH(stream)      stream->remainLength(stream->userContext)

#ifdef __cplusplus
}
#endif /* __cplusplus */
