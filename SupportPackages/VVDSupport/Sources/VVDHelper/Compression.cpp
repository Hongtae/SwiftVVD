/*******************************************************************************
 File: Compression.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#include <stdlib.h>
#include <string.h>
#include <algorithm>

#include "../zlib/zlib.h"
#include "../zstd/lib/zstd.h"

#include "../lz4/lib/lz4.h"
#include "../lz4/lib/lz4hc.h"
#include "../lz4/lib/lz4frame.h"
#include "../lz4/lib/xxhash.h"

#include "../lzma/C/LzmaEnc.h"
#include "../lzma/C/LzmaDec.h"

#include "Compression.h"
#include "Endianness.h"
#include "Malloc.h"
#include "Log.h"

#define COMPRESSION_CHUNK_SIZE 0x40000

struct CompressorBuffer
{
    void* buffer;
    size_t bufferSize;
    CompressorBuffer(size_t length)
        : bufferSize(0)
    {
        buffer = VVDMalloc(length);
        if (buffer)
            bufferSize = length;
    }
    ~CompressorBuffer()
    {
        if (buffer)
            VVDFree(buffer);
    }
};

static VVDCompressionResult EncodeDeflate(VVDStream* input, VVDStream* output, int level)
{
    CompressorBuffer inputBuffer(COMPRESSION_CHUNK_SIZE);
    CompressorBuffer outputBuffer(COMPRESSION_CHUNK_SIZE);

    if (inputBuffer.buffer == nullptr || outputBuffer.buffer == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    VVDCompressionResult result = VVDCompressionResult_UnknownError;

    int err = Z_OK;
    z_stream stream = {};
    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.opaque = Z_NULL;

    int compressLevel = level;  // Z_DEFAULT_COMPRESSION is 6
    err = deflateInit(&stream, compressLevel);
    if (err == Z_OK)
    {
        result = VVDCompressionResult_Success;
        int flush = Z_NO_FLUSH;
        while (err == Z_OK)
        {
            if (stream.avail_in == 0)
            {
                size_t inputSize = VVDSTREAM_READ(input, inputBuffer.buffer, inputBuffer.bufferSize);
                if (inputSize == VVDSTREAM_ERROR)
                {
                    result = VVDCompressionResult_InputStreamError;
                    err = Z_STREAM_ERROR;
                    break;
                }
                else if (inputSize == 0)
                {
                    err = Z_STREAM_END;
                    flush = Z_FINISH;
                }

                stream.avail_in = (uInt)inputSize;
                stream.next_in = (Bytef*)inputBuffer.buffer;
            }

            stream.avail_out = (uInt)outputBuffer.bufferSize;
            stream.next_out = (Bytef*)outputBuffer.buffer;
            err = deflate(&stream, flush);
            if (err == Z_STREAM_ERROR) {
                result = VVDCompressionResult_InputStreamError;
                break;
            }

            size_t write = outputBuffer.bufferSize - stream.avail_out;
            if (VVDSTREAM_WRITE(output, outputBuffer.buffer, write) != write)
            {
                result = VVDCompressionResult_OutputStreamError;
                err = Z_STREAM_ERROR;
                break;
            }
        }
        deflateEnd(&stream);
    }
    if (err == Z_STREAM_END)
        return VVDCompressionResult_Success;
    return result;
}

static VVDCompressionResult DecodeDeflate(VVDStream* input, VVDStream* output)
{
    CompressorBuffer inputBuffer(COMPRESSION_CHUNK_SIZE);
    CompressorBuffer outputBuffer(COMPRESSION_CHUNK_SIZE);

    if (inputBuffer.buffer == nullptr || outputBuffer.buffer == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    VVDCompressionResult result = VVDCompressionResult_UnknownError;
    int err = Z_OK;
    z_stream stream = {};
    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.opaque = Z_NULL;
    stream.avail_in = 0;
    stream.next_in = Z_NULL;
    err = inflateInit(&stream);
    if (err == Z_OK)
    {
        result = VVDCompressionResult_Success;
        while (err == Z_OK)
        {
            if (stream.avail_in == 0)
            {
                size_t inputSize = VVDSTREAM_READ(input, inputBuffer.buffer, inputBuffer.bufferSize);
                if (inputSize == VVDSTREAM_ERROR)
                {
                    result = VVDCompressionResult_InputStreamError;
                    err = Z_STREAM_ERROR;
                    break;
                }
                else if (inputSize == 0)
                {
                    break;
                }
                stream.avail_in = (uInt)inputSize;
                stream.next_in = (Bytef*)inputBuffer.buffer;
            }

            stream.avail_out = (uInt)outputBuffer.bufferSize;
            stream.next_out = (Bytef*)outputBuffer.buffer;
            err = inflate(&stream, Z_NO_FLUSH);
            if (err == Z_STREAM_ERROR)
            {
                result = VVDCompressionResult_InputStreamError;
                break;
            }
            if (err == Z_NEED_DICT || err == Z_DATA_ERROR || err == Z_MEM_ERROR)
            {
                result = VVDCompressionResult_DataError;
                break;
            }

            size_t write = outputBuffer.bufferSize - stream.avail_out;
            if (write > 0)
            {
                if (VVDSTREAM_WRITE(output, outputBuffer.buffer, write) != write)
                {
                    result = VVDCompressionResult_OutputStreamError;
                    err = Z_STREAM_ERROR;
                    break;
                }
            }
        }
        inflateEnd(&stream);

        if (err == Z_STREAM_END)
            return VVDCompressionResult_Success;
    }
    return result;
}

static VVDCompressionResult EncodeZstd(VVDStream* input, VVDStream* output, int level)
{
    CompressorBuffer inputBuffer(ZSTD_CStreamInSize());
    CompressorBuffer outputBuffer(ZSTD_CStreamOutSize());

    if (inputBuffer.buffer == nullptr || outputBuffer.buffer == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    /*
    Zstd requests a large amount of memory allocation.
    So we do not need to use VVDMalloc.
    */
#if 0   
    ZSTD_customMem customMem = {
        [](void* opaque, size_t size)->void* {return VVDMalloc(size); }, //ZSTD_allocFunction
        [](void* opaque, void* address) { VVDFree(address); }, //ZSTD_freeFunction
        nullptr //opaque
    };
    ZSTD_CStream* const cstream = ZSTD_createCStream_advanced(customMem);
#else
    ZSTD_CStream* const cstream = ZSTD_createCStream();
#endif
    if (cstream)
    {
        VVDCompressionResult result = VVDCompressionResult_UnknownError;
        size_t const initResult = ZSTD_initCStream(cstream, level);
        if (ZSTD_isError(initResult))
        {
            VVDLogE("VVDCompression Encode-Error: ZSTD_initCStream failed: %s\n",
                    ZSTD_getErrorName(initResult));
            result = VVDCompressionResult_UnknownError;
        }
        else
        {
            result = VVDCompressionResult_Success;
            size_t toRead = inputBuffer.bufferSize;
            while (toRead > 0)
            {
                if (inputBuffer.bufferSize < toRead) {
                    result = VVDCompressionResult_DataError;
                    break;
                }
                size_t read = VVDSTREAM_READ(input, inputBuffer.buffer, toRead);
                if (read > 0)
                {
                    ZSTD_inBuffer zInput = { inputBuffer.buffer, read, 0 };
                    while (zInput.pos < zInput.size)
                    {
                        ZSTD_outBuffer zOutput = { outputBuffer.buffer, outputBuffer.bufferSize, 0 };;
                        size_t toRead = ZSTD_compressStream(cstream, &zOutput, &zInput);
                        if (ZSTD_isError(toRead))
                        {
                            VVDLogE("VVDCompression Encode-Error: %s\n",
                                    ZSTD_getErrorName(toRead));
                            result = VVDCompressionResult_DataError;
                            break;
                        }
                        if (toRead > inputBuffer.bufferSize)
                            toRead = inputBuffer.bufferSize;
                        if (VVDSTREAM_WRITE(output, outputBuffer.buffer, zOutput.pos) != zOutput.pos)
                        {
                            result = VVDCompressionResult_OutputStreamError;
                            break;
                        }
                    }
                }
                else
                {
                    if (read < 0) // error
                    {
                        result = VVDCompressionResult_InputStreamError;
                    }
                    break;
                }
            }
            if (result == VVDCompressionResult_Success)
            {
                ZSTD_outBuffer zOutput = { outputBuffer.buffer, outputBuffer.bufferSize,0 };
                size_t const remainingToFlush = ZSTD_endStream(cstream, &zOutput); // close frame.
                if (remainingToFlush)
                {
                    VVDLogE("VVDCompression Encode-Error: Unable to flush stream.\n");
                    result = VVDCompressionResult_OutputStreamError;
                }
                else
                {
                    if (VVDSTREAM_WRITE(output, outputBuffer.buffer, zOutput.pos) != zOutput.pos)
                    {
                        result = VVDCompressionResult_OutputStreamError;
                    }
                }
            }
        }
        ZSTD_freeCStream(cstream);
        return result;
    }
    // error: ZSTD_createCStream failed
    return VVDCompressionResult_UnknownError; // VVDCompressionResult_OutOfMemory?
}

static VVDCompressionResult DecodeZstd(VVDStream* input, VVDStream* output)
{
    CompressorBuffer inputBuffer(ZSTD_DStreamInSize());
    CompressorBuffer outputBuffer(ZSTD_DStreamOutSize());

    if (inputBuffer.buffer == nullptr || outputBuffer.buffer == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    /*
    Zstd requests a large amount of memory allocation.
    So we do not need to use VVDMalloc.
    */
#if 0   
    ZSTD_customMem customMem = {
        [](void* opaque, size_t size)->void* { return VVDMalloc(size); }, //ZSTD_allocFunction
        [](void* opaque, void* address) { VVDFree(address); }, //ZSTD_freeFunction
        nullptr //opaque
    };
    ZSTD_DStream* const dstream = ZSTD_createDStream_advanced(customMem);
#else
    ZSTD_DStream* const dstream = ZSTD_createDStream();
#endif
    if (dstream)
    {
        VVDCompressionResult result = VVDCompressionResult_UnknownError;
        size_t const initResult = ZSTD_initDStream(dstream);
        if (ZSTD_isError(initResult))
        {
            VVDLogE("VVDCompression Decode-Error: ZSTD_initDStream failed: %s\n",
                    ZSTD_getErrorName(initResult));
            result = VVDCompressionResult_UnknownError;
        }
        else
        {
            result = VVDCompressionResult_Success;
            size_t toRead = initResult;
            while (toRead > 0)
            {
                if (inputBuffer.bufferSize < toRead) {
                    result = VVDCompressionResult_DataError;
                    break;
                }
                size_t read = VVDSTREAM_READ(input, inputBuffer.buffer, toRead);
                if (read > 0)
                {
                    ZSTD_inBuffer zInput = { inputBuffer.buffer, read, 0 };
                    while (zInput.pos < zInput.size)
                    {
                        ZSTD_outBuffer zOutput = { outputBuffer.buffer, outputBuffer.bufferSize,0 };
                        toRead = ZSTD_decompressStream(dstream, &zOutput, &zInput);
                        if (ZSTD_isError(toRead))
                        {
                            VVDLogE("VVDCompression Decode-Error: %s\n",
                                    ZSTD_getErrorName(toRead));
                            result = VVDCompressionResult_DataError;
                            break;
                        }
                        if (VVDSTREAM_WRITE(output, outputBuffer.buffer, zOutput.pos) != zOutput.pos)
                        {
                            result = VVDCompressionResult_OutputStreamError;
                            break;
                        }
                    }
                }
                else
                {
                    if (read < 0) // error
                    {
                        result = VVDCompressionResult_InputStreamError;
                    }
                    break;
                }
            }
        }

        ZSTD_freeDStream(dstream);
        return result;
    }
    // error: ZSTD_createDStream failed
    return VVDCompressionResult_UnknownError; // VVDCompressionResult_OutOfMemory?
}

static VVDCompressionResult EncodeLz4(VVDStream* input, VVDStream* output, int level)
{
    LZ4F_preferences_t prefs = {};
    prefs.autoFlush = 1;
    prefs.compressionLevel = level; // 0 for LZ4 fast, 9 for LZ4HC
    prefs.frameInfo.blockMode = LZ4F_blockLinked; // for better compression ratio.
    prefs.frameInfo.contentChecksumFlag = LZ4F_contentChecksumEnabled; // to detect data corruption.
    prefs.frameInfo.blockSizeID = LZ4F_max4MB;

    size_t inputBufferSize = size_t(1) << (8 + (2 * prefs.frameInfo.blockSizeID));
    size_t outputBufferSize = LZ4F_compressFrameBound(inputBufferSize, &prefs);;

    CompressorBuffer inputBuffer(inputBufferSize);
    CompressorBuffer outputBuffer(outputBufferSize);

    if (inputBuffer.buffer == nullptr || outputBuffer.buffer == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    LZ4F_compressionContext_t ctx;
    LZ4F_errorCode_t err = LZ4F_createCompressionContext(&ctx, LZ4F_VERSION);

    if (!LZ4F_isError(err))
    {
        VVDCompressionResult result = VVDCompressionResult_UnknownError;

        size_t inputSize = VVDSTREAM_READ(input, inputBuffer.buffer, inputBuffer.bufferSize);
        if (inputSize != VVDSTREAM_ERROR)
        {
            // generate header
            size_t headerSize = LZ4F_compressBegin(ctx, outputBuffer.buffer, outputBuffer.bufferSize, &prefs);
            if (!LZ4F_isError(headerSize))
            {
                // write header
                if (VVDSTREAM_WRITE(output, outputBuffer.buffer, headerSize) == headerSize)
                {
                    result = VVDCompressionResult_Success;
                    // compress block
                    while (inputSize > 0)
                    {
                        size_t outputSize = LZ4F_compressUpdate(ctx, outputBuffer.buffer, outputBuffer.bufferSize, inputBuffer.buffer, inputSize, NULL);
                        if (LZ4F_isError(outputSize))
                        {
                            VVDLogE("VVDCompression Encode-Error: LZ4 error: %s\n", LZ4F_getErrorName(outputSize));
                            result = VVDCompressionResult_DataError;
                            break;
                        }
                        if (VVDSTREAM_WRITE(output, outputBuffer.buffer, outputSize) != outputSize)
                        {
                            result = VVDCompressionResult_OutputStreamError;
                            break;
                        }
                        inputSize = VVDSTREAM_READ(input, inputBuffer.buffer, inputBuffer.bufferSize);
                        if (inputSize == VVDSTREAM_ERROR)
                        {
                            result = VVDCompressionResult_InputStreamError;
                            break;
                        }
                    }
                    if (result == VVDCompressionResult_Success)
                    {
                        // generate footer
                        headerSize = LZ4F_compressEnd(ctx, outputBuffer.buffer, outputBuffer.bufferSize, NULL);
                        if (!LZ4F_isError(headerSize))
                        {
                            // write footer
                            if (VVDSTREAM_WRITE(output, outputBuffer.buffer, headerSize) != headerSize)
                                result = VVDCompressionResult_OutputStreamError;
                        }
                        else
                        {
                            result = VVDCompressionResult_DataError;
                        }
                    }
                }
            }
            else
            {
                VVDLogE("VVDCompression Encode-Error: LZ4 error: %s\n", LZ4F_getErrorName(headerSize));
                result = VVDCompressionResult_DataError;
            }
        }
        else
        {
            result = VVDCompressionResult_InputStreamError;
        }
        err = LZ4F_freeCompressionContext(ctx);
        if (LZ4F_isError(err))
            return VVDCompressionResult_UnknownError;
        return result;
    }
    VVDLogE("VVDCompression Encode-Error: LZ4 Encoder error: %s\n", LZ4F_getErrorName(err));
    return VVDCompressionResult_UnknownError;
}

static VVDCompressionResult DecodeLz4(VVDStream* input, VVDStream* output)
{
    CompressorBuffer inputBuffer(COMPRESSION_CHUNK_SIZE);
    CompressorBuffer outputBuffer(COMPRESSION_CHUNK_SIZE);

    if (inputBuffer.buffer == nullptr || outputBuffer.buffer == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    const uint32_t lz4_Header = VVDSystemToLittleEndian(0x184D2204U);
    const uint32_t lz4_SkipHeader = VVDSystemToLittleEndian(0x184D2A50U);

    LZ4F_decompressionContext_t ctx;
    LZ4F_errorCode_t err = LZ4F_createDecompressionContext(&ctx, LZ4F_VERSION);
    if (!LZ4F_isError(err))
    {
        size_t inputSize = 0;
        size_t processed = 0;
        size_t inSize, outSize;
        uint8_t* const inData = reinterpret_cast<uint8_t*>(inputBuffer.buffer);
        LZ4F_errorCode_t nextToLoad;
        VVDCompressionResult result = VVDCompressionResult_Success;

        while (result == VVDCompressionResult_Success)
        {
            if (inputSize == 0)
            {
                inputSize = VVDSTREAM_READ(input, inputBuffer.buffer, inputBuffer.bufferSize);
                if (inputSize == VVDSTREAM_ERROR)
                {
                    result = VVDCompressionResult_InputStreamError;
                    break;
                }
                else if (inputSize == 0) // end steam
                    break;
            }
            uint32_t header = reinterpret_cast<const uint32_t*>(&inData[processed])[0];
            if (header == lz4_Header)
            {
                do
                {
                    while (processed < inputSize)
                    {
                        inSize = inputSize - processed;
                        outSize = outputBuffer.bufferSize;
                        nextToLoad = LZ4F_decompress(ctx, outputBuffer.buffer, &outSize, &inData[processed], &inSize, NULL);
                        if (LZ4F_isError(nextToLoad))
                        {
                            VVDLogE("VVDCompression Decode-Error: Lz4 Header Error: %s\n", LZ4F_getErrorName(nextToLoad));
                            result = VVDCompressionResult_DataError;
                            nextToLoad = 0;
                            break;
                        }
                        processed += inSize;
                        if (outSize > 0)
                        {
                            if (VVDSTREAM_WRITE(output, outputBuffer.buffer, outSize) != outSize)
                            {
                                result = VVDCompressionResult_OutputStreamError;
                                nextToLoad = 0;
                                break;
                            }
                        }
                    }
                    inputSize = 0;
                    processed = 0;
                    if (nextToLoad)
                    {
                        inputSize = VVDSTREAM_READ(input, inputBuffer.buffer, std::min(nextToLoad, inputBuffer.bufferSize));
                        if (inputSize == VVDSTREAM_ERROR)
                        {
                            result = VVDCompressionResult_InputStreamError;
                            break;
                        }
                    }
                } while (nextToLoad);
            }
            else if ((header & 0xfffffff0U) == lz4_SkipHeader)
            {
                while (inputSize < 8) // header + skip-length = 8
                {
                    size_t n = VVDSTREAM_READ(input, &inData[inputSize], 8 - inputSize);
                    if (n == VVDSTREAM_ERROR)
                    {
                        result = VVDCompressionResult_InputStreamError;
                        break;
                    }
                    else if (n == 0) // end stream? 
                    {
                        VVDLogE("VVDCompression Decode-Error: Lz4 input stream ended before processing skip frame!\n");
                        result = VVDCompressionResult_DataError;
                        break;
                    }
                    inputSize += n;
                }
                if (inputSize >= 8)
                {
                    uint32_t bytesToSkip = reinterpret_cast<const uint32_t*>(&inData[processed])[1];
                    bytesToSkip = VVDLittleEndianToSystem(bytesToSkip);
                    size_t remains = inputSize - processed;
                    if (bytesToSkip > remains)
                    {
                        size_t offset = bytesToSkip - remains;
                        if (VVDSTREAM_IS_SEEKABLE(input))
                        {
                            if (VVDSTREAM_SET_POSITION(input, (VVDSTREAM_GET_POSITION(input) + offset)) != VVDSTREAM_ERROR)
                            {
                                inputSize = 0;
                            }
                        }
                        else
                        {
                            VVDLogW("VVDCompression Decode-Warning: Lz4 stream seeking is not available!\n");
                            size_t r = 0;
                            while (r < offset)
                            {
                                uint64_t t = VVDSTREAM_READ(input, inputBuffer.buffer, std::min((offset - r), inputBuffer.bufferSize));
                                if (t == VVDSTREAM_ERROR)
                                    break;
                                r += t;
                            }
                            if (r == offset)
                                inputSize = 0;
                        }
                        if (inputSize) // seek failed.
                        {
                            VVDLogE("VVDCompression Decode-Error: Lz4 input stream cannot process skip frame!\n");
                            result = VVDCompressionResult_InputStreamError;
                            break;
                        }
                    }
                    else
                        processed += bytesToSkip;
                }
            }
            else
            {
                VVDLogE("VVDCompression Decode-Error: Lz4 stream followed by unrecognized data.\n");
                result = VVDCompressionResult_DataError;
                break;
            }
        }
        err = LZ4F_freeDecompressionContext(ctx);
        if (result != VVDCompressionResult_Success && LZ4F_isError(err))
            return VVDCompressionResult_UnknownError;
        return result;
    }
    return VVDCompressionResult_UnknownError;
}

struct LzmaInStream : public ISeqInStream
{
    VVDStream* source;
    LzmaInStream(VVDStream* stream) : source(stream)
    {
        if (source->read)
        {
            this->Read = [](const ISeqInStream *p, void *buf, size_t *size) -> SRes
            {
                LzmaInStream* stream = (LzmaInStream*)p;
                size_t bytesRequest = *size;
                uint64_t bytesRead = VVDSTREAM_READ(stream->source, buf, bytesRequest);
                if (bytesRead == VVDSTREAM_ERROR)
                    return SZ_ERROR_READ;
                *size = bytesRead;
                return SZ_OK;
            };
        }
        else
        {
            this->Read = [](const ISeqInStream *p, void *buf, size_t *size)->SRes
            {
                return SZ_ERROR_READ;
            };
        }
    }
};

struct LzmaOutStream : public ISeqOutStream
{
    VVDStream* source;
    LzmaOutStream(VVDStream* stream) : source(stream)
    {
        if (source->write)
        {
            this->Write = [](const ISeqOutStream *p, const void *buf, size_t size)-> size_t
            {
                LzmaOutStream* stream = (LzmaOutStream*)p;
                return VVDSTREAM_WRITE(stream->source, buf, size);
            };
        }
        else
        {
            this->Write = [](const ISeqOutStream *p, const void *buf, size_t size)-> size_t
            {
                return 0;
            };
        }
    }
};

static VVDCompressionResult LzmaResult(SRes res)
{
    switch (res)
    {
        case SZ_OK:
            return VVDCompressionResult_Success;
        case SZ_ERROR_DATA:
        case SZ_ERROR_MEM:  
        case SZ_ERROR_CRC:
            return VVDCompressionResult_DataError;
        case SZ_ERROR_UNSUPPORTED:
        case SZ_ERROR_PARAM:
            return VVDCompressionResult_InvalidParameter;
        case SZ_ERROR_INPUT_EOF:
        case SZ_ERROR_READ:
            return VVDCompressionResult_InputStreamError;
        case SZ_ERROR_OUTPUT_EOF:
        case SZ_ERROR_WRITE:
            return VVDCompressionResult_OutputStreamError;
        case SZ_ERROR_PROGRESS:
        case SZ_ERROR_FAIL:
        case SZ_ERROR_THREAD:
        case SZ_ERROR_ARCHIVE:
        case SZ_ERROR_NO_ARCHIVE:
            return VVDCompressionResult_UnknownError;                
    }
    return VVDCompressionResult_UnknownError;
}

static VVDCompressionResult EncodeLzma(VVDStream* input, VVDStream* output, int level)
{
    if (input == nullptr || input->read == nullptr)
        return VVDCompressionResult_InputStreamError;
    if (output == nullptr || output->write == nullptr)
        return VVDCompressionResult_OutputStreamError;

    LzmaInStream inStream(input);
    LzmaOutStream outStream(output);
    ISzAlloc alloc = {
        [](ISzAllocPtr, size_t s) { return VVDMalloc(s); },
        [](ISzAllocPtr, void* p) { VVDFree(p); }
    };

    CLzmaEncHandle enc = LzmaEnc_Create(&alloc);
    if (enc == nullptr)
    {
        return VVDCompressionResult_OutOfMemory;
    }

    CLzmaEncProps props;
    LzmaEncProps_Init(&props);
    props.level = level;
    //LzmaEncProps_Normalize(&props);
    SRes res = LzmaEnc_SetProps(enc, &props); 
    if (res == SZ_OK)
    {
        uint64_t streamLength = (uint64_t)VVDSTREAM_REMAIN_LENGTH(input);

        uint8_t header[LZMA_PROPS_SIZE + 8];
        size_t headerSize = LZMA_PROPS_SIZE;
        res = LzmaEnc_WriteProperties(enc, header, &headerSize);
        for (int i = 0; i < 8; i++)
            header[headerSize++] = (uint8_t)(streamLength >> (8 * i));
        if (res == SZ_OK)
        {
            //if (outStream.Write(&outStream, header, headerSize) != headerSize)
            //    res = SZ_ERROR_WRITE;
            if (VVDSTREAM_WRITE(output, header, headerSize) != headerSize)
                res = SZ_ERROR_WRITE;
            else
                res = LzmaEnc_Encode(enc, &outStream, &inStream, NULL, &alloc, &alloc);
        }
    }
    else
    {
        VVDLogE("VVDCompression Encode-Error: Invalid parameters!\n");
    }
    LzmaEnc_Destroy(enc, &alloc, &alloc);
    if (res != SZ_OK)
        return LzmaResult(res);
    return VVDCompressionResult_Success;
}

static VVDCompressionResult DecodeLzma(VVDStream* input, VVDStream* output)
{
    if (input == nullptr || input->read == nullptr)
        return VVDCompressionResult_InputStreamError;
    if (output == nullptr || output->write == nullptr)
        return VVDCompressionResult_OutputStreamError;

    LzmaInStream inStream(input);
    LzmaOutStream outStream(output);
    ISzAlloc alloc = {
        [](ISzAllocPtr, size_t s) { return VVDMalloc(s); },
        [](ISzAllocPtr, void* p) { VVDFree(p); }
    };

    /* header: 5 bytes of LZMA properties and 8 bytes of uncompressed size */
    uint8_t header[LZMA_PROPS_SIZE + 8];
    SRes res = SeqInStream_Read(&inStream, header, sizeof(header));
    if (res == SZ_OK)
    {
        uint64_t unpackSize = 0;
        for (int i = 0; i < 8; i++)
            unpackSize += (UInt64)header[LZMA_PROPS_SIZE + i] << (i * 8);

        CLzmaDec state;
        LzmaDec_Construct(&state);
        if (LzmaDec_Allocate(&state, header, LZMA_PROPS_SIZE, &alloc) == SZ_OK)
        {
            bool enableUnpackSize = true;
            if (unpackSize == ~uint64_t(0))
                enableUnpackSize = false;

            CompressorBuffer inputBuffer(COMPRESSION_CHUNK_SIZE);
            CompressorBuffer outputBuffer(COMPRESSION_CHUNK_SIZE);
            uint8_t* inBuf = (uint8_t*)inputBuffer.buffer;
            uint8_t* outBuf = (uint8_t*)outputBuffer.buffer;

            size_t inPos = 0, inSize = 0, outPos = 0;
            LzmaDec_Init(&state);
            while (true)
            {
                if (inPos == inSize)
                {
                    inSize = inputBuffer.bufferSize;
                    res = inStream.Read(&inStream, inBuf, &inSize);
                    if (res != SZ_OK)
                        break;
                    inPos = 0;
                }
                {
                    SizeT inProcessed = inSize - inPos;
                    SizeT outProcessed = outputBuffer.bufferSize - outPos;
                    ELzmaFinishMode finishMode = LZMA_FINISH_ANY;
                    if (enableUnpackSize && outProcessed > unpackSize)
                    {
                        outProcessed = (SizeT)unpackSize;
                        finishMode = LZMA_FINISH_END;
                    }
                    ELzmaStatus status;
                    res = LzmaDec_DecodeToBuf(&state,
                                                outBuf + outPos, &outProcessed,
                                                inBuf + inPos, &inProcessed,
                                                finishMode, &status);
                    inPos += inProcessed;
                    outPos += outProcessed;
                    unpackSize -= outProcessed;

                    if (outStream.Write(&outStream, outBuf, outPos) != outPos)
                        res = SZ_ERROR_WRITE;

                    outPos = 0;
                    if (res != SZ_OK || (enableUnpackSize && unpackSize == 0))
                        break;

                    if (inProcessed == 0 && outProcessed == 0)
                    {
                        if (enableUnpackSize || status != LZMA_STATUS_FINISHED_WITH_MARK)
                            res = SZ_ERROR_DATA;
                        break;
                    }
                }
            }
            LzmaDec_Free(&state, &alloc);
        }
    }
    if (res != SZ_OK)
        return LzmaResult(res);
    return VVDCompressionResult_Success;
}

static bool DetectAlgorithm(void* p, size_t n, VVDCompressionAlgorithm& algo)
{
    if (p)
    {
        if (n >= 4)
        {
            const uint32_t zstd_MagicNumber = VVDSystemToLittleEndian(0xFD2FB528U);

            if (reinterpret_cast<const uint32_t*>(p)[0] == zstd_MagicNumber)
            {
                algo = VVDCompressionAlgorithm_Zstd;
                return true;
            }
        }
        if (n >= 4)
        {
            const uint32_t lz4_Header = VVDSystemToLittleEndian(0x184D2204U);
            const uint32_t lz4_SkipHeader = VVDSystemToLittleEndian(0x184D2A50U);

            if (reinterpret_cast<const uint32_t*>(p)[0] == lz4_Header ||
                (reinterpret_cast<const uint32_t*>(p)[0] & 0xfffffff0U) == lz4_SkipHeader)
            {
                algo = VVDCompressionAlgorithm_Lz4;
                return true;
            }
        }
        if (n >= 1)
        {
            if (reinterpret_cast<const char*>(p)[0] == 0x78)
            {
                algo = VVDCompressionAlgorithm_Zlib;
                return true;
            }
        }
        if (n >= 13) /* LZMA_PROPS_SIZE + 8(uint64_t, uncompressed size) */
        {
            const uint8_t* header = reinterpret_cast<const uint8_t*>(p);

            uint64_t unpackSize = 0;
            for (int i = 0; i < 8; i++)
                unpackSize += (UInt64)header[LZMA_PROPS_SIZE + i] << (i * 8);

            if (unpackSize > 0)
            {
                CLzmaProps props;
                if (LzmaProps_Decode(&props, header, LZMA_PROPS_SIZE) == SZ_OK)
                {
                    algo = VVDCompressionAlgorithm_Lzma;
                    return true;
                }
            }
        }
    }
    return false;
}

extern "C"
VVDCompressionResult VVDCompressionEncode(VVDCompressionAlgorithm a, VVDStream* input, VVDStream* output, int level)
{
    if (input == nullptr || input->read == nullptr)
        return VVDCompressionResult_InputStreamError;
    if (output == nullptr || output->write == nullptr)
        return VVDCompressionResult_OutputStreamError;

    switch (a)
    {
    case VVDCompressionAlgorithm_Zlib:
        return EncodeDeflate(input, output, level);
    case VVDCompressionAlgorithm_Zstd:
        return EncodeZstd(input, output, level);
    case VVDCompressionAlgorithm_Lz4:
        return EncodeLz4(input, output, level);
    case VVDCompressionAlgorithm_Lzma:
        if (input->remainLength)
            return EncodeLzma(input, output, level);
        return VVDCompressionResult_InputStreamError;
    }
    return VVDCompressionResult_InvalidParameter;
}

extern "C"
VVDCompressionResult VVDCompressionDecode(VVDCompressionAlgorithm a, VVDStream* input, VVDStream* output)
{
    if (input == nullptr || input->read == nullptr)
        return VVDCompressionResult_InputStreamError;
    if (output == nullptr || output->write == nullptr)
        return VVDCompressionResult_OutputStreamError;

    switch (a)
    {
    case VVDCompressionAlgorithm_Zlib:
        return DecodeDeflate(input, output);
    case VVDCompressionAlgorithm_Zstd:
        return DecodeZstd(input, output);
    case VVDCompressionAlgorithm_Lz4:
        return DecodeLz4(input, output);
    case VVDCompressionAlgorithm_Lzma:
        return DecodeLzma(input, output);
    }
    return VVDCompressionResult_InvalidParameter;
}

extern "C"
VVDCompressionResult VVDCompressionDecodeAutoDetect(VVDStream* input, VVDStream* output, VVDCompressionAlgorithm* pAlg)
{
    if (input == nullptr || input->read == nullptr)
        return VVDCompressionResult_InputStreamError;
    if (output == nullptr || output->write == nullptr)
        return VVDCompressionResult_OutputStreamError;

    struct BufferedStreamContext
    {
        enum {BufferLength = 1024};
        VVDStream* source;
        uint8_t buffer[BufferLength];
        uint8_t* preloadedData;
        size_t preloadedLength;

        BufferedStreamContext(VVDStream* s): source(s)
        {
            preloadedLength = VVDSTREAM_READ(source, buffer, BufferLength);
            if (preloadedLength > 0 && preloadedLength != VVDSTREAM_ERROR)
                preloadedData = buffer;
            else
                preloadedLength = 0; // error? 
        }
    };
    BufferedStreamContext inputStreamContext(input);
    if (inputStreamContext.preloadedLength == VVDSTREAM_ERROR)
        return VVDCompressionResult_InputStreamError;

    VVDStream bufferedInputStream = {};
    bufferedInputStream.userContext = reinterpret_cast<VVDStreamContext>(&inputStreamContext);
    bufferedInputStream.read = [](VVDStreamContext c, void* p, size_t s) -> uint64_t
    {
        BufferedStreamContext* ctxt = reinterpret_cast<BufferedStreamContext*>(c);
        size_t totalRead = 0;
        while (s > 0 && ctxt->preloadedLength > 0)
        {
            size_t read = std::min(s, ctxt->preloadedLength);
            // VVDASSERT_DEBUG(read > 0);

            memcpy(p, ctxt->preloadedData, read);
            ctxt->preloadedData += read;
            ctxt->preloadedLength -= read;

            // VVDASSERT_DEBUG(s >= read);

            s = s - read;
            p = &reinterpret_cast<uint8_t*>(p)[read];
            totalRead += read;
        }
        if (s > 0)
        {
            totalRead += VVDSTREAM_READ(ctxt->source, p, s);
        }
        //VVDASSERT_DEBUG(preloadedLength >= 0);
        return totalRead;
    };
    if (input->remainLength)
    {
        bufferedInputStream.remainLength = [](VVDStreamContext c)
        {
            BufferedStreamContext* ctxt = reinterpret_cast<BufferedStreamContext*>(c);
            auto pos = VVDSTREAM_REMAIN_LENGTH(ctxt->source);
            return pos + ctxt->preloadedLength;
        };
    }
    if (input->setPosition)
    {
        bufferedInputStream.setPosition = [](VVDStreamContext c, uint64_t p)
        {
            BufferedStreamContext* ctxt = reinterpret_cast<BufferedStreamContext*>(c);
            auto pos = VVDSTREAM_SET_POSITION(ctxt->source, p);
            if (pos != VVDSTREAM_ERROR)
                ctxt->preloadedLength = 0;
            return pos;
        };
    }
    if (input->getPosition)
    {
        bufferedInputStream.getPosition = [](VVDStreamContext c)
        {
            BufferedStreamContext* ctxt = reinterpret_cast<BufferedStreamContext*>(c);
            auto pos = VVDSTREAM_GET_POSITION(ctxt->source);
            return pos - ctxt->preloadedLength;
        };
    }

    VVDCompressionAlgorithm algo;
    if (!DetectAlgorithm(inputStreamContext.preloadedData, inputStreamContext.preloadedLength, algo))
    {
        VVDLogE("VVDCompression Decode-Error: Unable to identify format.\n");
        return VVDCompressionResult_UnknownFormat;
    }
    VVDCompressionResult result = VVDCompressionDecode(algo, &bufferedInputStream, output);
    if (result == VVDCompressionResult_Success && pAlg)
        *pAlg = algo;
    return result;
}
