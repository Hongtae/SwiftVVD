#include "DKCompressor.h"

extern "C"
bool DKCompressorEncode(DKCompressorMethod, DKStream* input, DKStream* output, int level)
{
    return false;
}

extern "C"
bool DKCompressorDecode(DKCompressorMethod, DKStream* input, DKStream* output)
{
    return false;
}

extern "C"
bool DKCompressorDecodeAutoDetect(DKStream* input, DKStream* output, DKCompressorMethod*)
{
    return false;
}
