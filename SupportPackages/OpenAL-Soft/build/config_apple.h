
#define AL_API  __attribute__((visibility("default")))
#define ALC_API __attribute__((visibility("default")))

/* Define any available alignment declaration */
#define ALIGN(x) __attribute__((aligned(x)))

#if __LP64__
#define SIZEOF_LONG			8
#define SIZEOF_LONG_LONG	8
#else
#define SIZEOF_LONG			4
#define SIZEOF_LONG_LONG	8
#endif

#define HAVE_POSIX_MEMALIGN
/* #define HAVE_SSE */
#define HAVE_COREAUDIO
#define HAVE_WAVE
#define HAVE_STAT
#define HAVE_LRINTF
#define HAVE_STRTOF
/* #define HAVE_GCC_DESTRUCTOR */
/* #define HAVE_GCC_FORMAT */
#define HAVE_STDINT_H
#define HAVE_DLFCN_H
#define HAVE_XMMINTRIN_H
/* #define HAVE_CPUID_H */
#define HAVE_FLOAT_H
#define HAVE_FENV_H
#define HAVE_PTHREAD_SETSCHEDPARAM