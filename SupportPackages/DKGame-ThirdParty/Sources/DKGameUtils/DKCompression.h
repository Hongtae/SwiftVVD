/*******************************************************************************
 File: DKCompression.h
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

typedef enum _DKCompressionAlgorithm
{
    DKCompressionAlgorithm_Zlib,  /* 0 ~ 9, default: 5 */
    DKCompressionAlgorithm_Zstd,  /* 3 ~ 19(22), default: 3, best ratio: 19 */
    DKCompressionAlgorithm_Lz4,   /* 0 for LZ4, 9 for LZ4HC */
    DKCompressionAlgorithm_Lzma,  /* 0 ~ 9, default: 5 */
} DKCompressionAlgorithm;

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

typedef enum _DKCompressionResult {
    DKCompressionResult_Success = 0,
    DKCompressionResult_UnknownError,
    DKCompressionResult_OutOfMemory,
    DKCompressionResult_InputStreamError,
    DKCompressionResult_OutputStreamError,
    DKCompressionResult_DataError,
    DKCompressionResult_InvalidParameter,
    DKCompressionResult_UnknownFormat,
} DKCompressionResult;

DKCompressionResult DKCompressionEncode(DKCompressionAlgorithm, DKStream* input, DKStream* output, int level);
DKCompressionResult DKCompressionDecode(DKCompressionAlgorithm, DKStream* input, DKStream* output);
DKCompressionResult DKCompressionDecodeAutoDetect(DKStream* input, DKStream* output, DKCompressionAlgorithm*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
