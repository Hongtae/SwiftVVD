#define AL_API  __attribute__((visibility("default")))
#define ALC_API __attribute__((visibility("default")))

#define ALIGN(x) __attribute__((aligned(x)))

#define HAVE_POSIX_MEMALIGN

#define HAVE_GETOPT
/* #define HAVE_RTKIT */

#if defined(__aarch64__) || defined(__arm__)
#define HAVE_NEON
#elif defined(__x86_64__)
#define HAVE_SSE
#define HAVE_SSE2
#define HAVE_SSE3
#define HAVE_SSE4_1
#define HAVE_SSE_INTRINSICS
#endif

#define HAVE_OSS
#define HAVE_WAVE
#define HAVE_DLFCN_H
#define HAVE_MALLOC_H
#define HAVE_CPUID_H
#define HAVE_GCC_GET_CPUID

#define HAVE_PTHREAD_SETSCHEDPARAM
