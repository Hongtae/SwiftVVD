#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef void* DKStreamContext;
#define DKSTREAM_ERROR ~uint64_t(0)

typedef uint64_t (*DKStreamSetPosition)(DKStreamContext, uint64_t);
typedef uint64_t (*DKStreamGetPosition)(DKStreamContext, uint64_t);
typedef uint64_t (*DKStreamRemainLength)(DKStreamContext);

typedef uint64_t (*DKStreamRead)(DKStreamContext, void*, size_t);
typedef uint64_t (*DKStreamWrite)(DKStreamContext, const void*, size_t);

typedef struct _DKStream
{
    DKStreamContext userContext;
    DKStreamSetPosition setPosition;
    DKStreamGetPosition getPosition;
    DKStreamRead read;
    DKStreamWrite write;
} DKStream;

#ifdef __cplusplus
}
#endif /* __cplusplus */
