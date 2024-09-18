/*******************************************************************************
 File: Compression.h
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

typedef enum _VVDCompressionAlgorithm
{
    VVDCompressionAlgorithm_Zlib,  /* 0 ~ 9, default: 5 */
    VVDCompressionAlgorithm_Zstd,  /* 3 ~ 19(22), default: 3, best ratio: 19 */
    VVDCompressionAlgorithm_Lz4,   /* 0 for LZ4, 9 for LZ4HC */
    VVDCompressionAlgorithm_Lzma,  /* 0 ~ 9, default: 5 */
} VVDCompressionAlgorithm;

#define VVDCOMPRESSOR_LEVEL_ZLIB_MIN     0
#define VVDCOMPRESSOR_LEVEL_ZLIB_MAX     9
#define VVDCOMPRESSOR_LEVEL_ZSTD_MIN     3   /* ZSTD_CLEVEL_DEFAULT */
#define VVDCOMPRESSOR_LEVEL_ZSTD_MAX     22  /* ZSTD_MAX_CLEVEL */
#define VVDCOMPRESSOR_LEVEL_LZ4_MIN      0
#define VVDCOMPRESSOR_LEVEL_LZ4_MAX      9
#define VVDCOMPRESSOR_LEVEL_LZMA_MIN     0
#define VVDCOMPRESSOR_LEVEL_LZMA_MAX     9

#define VVDCOMPRESSOR_LEVEL_ZLIB_DEFAULT       5   /* Z_DEFAULT_COMPRESSION */
#define VVDCOMPRESSOR_LEVEL_ZSTD_DEFAULT       3   /* ZSTD_CLEVEL_DEFAULT */
#define VVDCOMPRESSOR_LEVEL_ZSTD_BEST_RATIO    19
#define VVDCOMPRESSOR_LEVEL_LZ4_DEFAULT        0
#define VVDCOMPRESSOR_LEVEL_LZ4HC              9
#define VVDCOMPRESSOR_LEVEL_LZMA_DEFAULT       5
#define VVDCOMPRESSOR_LEVEL_LZMA_FAST          0
#define VVDCOMPRESSOR_LEVEL_LZMA_ULTRA         9

typedef enum _VVDCompressionResult {
    VVDCompressionResult_Success = 0,
    VVDCompressionResult_UnknownError,
    VVDCompressionResult_OutOfMemory,
    VVDCompressionResult_InputStreamError,
    VVDCompressionResult_OutputStreamError,
    VVDCompressionResult_DataError,
    VVDCompressionResult_InvalidParameter,
    VVDCompressionResult_UnknownFormat,
} VVDCompressionResult;

VVDCompressionResult VVDCompressionEncode(VVDCompressionAlgorithm, VVDStream* input, VVDStream* output, int level);
VVDCompressionResult VVDCompressionDecode(VVDCompressionAlgorithm, VVDStream* input, VVDStream* output);
VVDCompressionResult VVDCompressionDecodeAutoDetect(VVDStream* input, VVDStream* output, VVDCompressionAlgorithm*);

#ifdef __cplusplus
}
#endif /* __cplusplus */
