#if defined(__APPLE__) && defined(__MACH__)
#include <TargetConditionals.h>
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#endif
