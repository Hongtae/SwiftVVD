#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "DKStream.h"

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef enum _DKCompressorMethod
{
    DKCompressorMethod_Zlib,  /* 0 ~ 9, default: 5 */
    DKCompressorMethod_Zstd,  /* 3 ~ 19(22), default: 3, best ratio: 19 */
    DKCompressorMethod_Lz4,   /* 0 for LZ4, 9 for LZ4HC */
    DKCompressorMethod_Lzma,  /* 0 ~ 9, default: 5 */
} DKCompressorMethod;

#define DKCOMPRESSOR_LEVEL_ZLIB_MIN     0
#define DKCOMPRESSOR_LEVEL_ZLIB_MAX     9
#define DKCOMPRESSOR_LEVEL_ZSTD_MIN     3   /* ZSTD_CLEVEL_DEFAULT */
#define DKCOMPRESSOR_LEVEL_ZSTD_MAX     22  /* ZSTD_MAX_CLEVEL */
#define DKCOMPRESSOR_LEVEL_LZ4_MIN      0
#define DKCOMPRESSOR_LEVEL_LZ4_MAX      9
#define DKCOMPRESSOR_LEVEL_LZMA_MIN     0
#define DKCOMPRESSOR_LEVEL_LZMA_MAX     9

#define DKCOMPRESSOR_LEVEL_ZLIB_DEFAULT       5   /* Z_DEFAULT_COMPRESSION */
#define DKCOMPRESSOR_LEVEL_ZSTD_DEFAULT       3   /* ZSTD_CLEVEL_DEFAULT */
#define DKCOMPRESSOR_LEVEL_ZSTD_BEST_RATIO    19
#define DKCOMPRESSOR_LEVEL_LZ4_DEFAULT        0
#define DKCOMPRESSOR_LEVEL_LZ4HC              9
#define DKCOMPRESSOR_LEVEL_LZMA_DEFAULT       5
#define DKCOMPRESSOR_LEVEL_LZMA_FAST          0
#define DKCOMPRESSOR_LEVEL_LZMA_ULTRA         9

bool DKCompressorEncode(DKCompressorMethod, DKStream* input, DKStream* output, int level);
bool DKCompressorDecode(DKCompressorMethod, DKStream* input, DKStream* output);
bool DKCompressorDecodeAutoDetect(DKStream* input, DKStream* output, DKCompressorMethod*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
