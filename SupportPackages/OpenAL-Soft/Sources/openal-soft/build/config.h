#ifndef CONFIG_H
#define CONFIG_H

/* #define AL_ALEXT_PROTOTYPES */

/* Define if deprecated EAX extensions are enabled */
#define ALSOFT_EAX

/* Define if HRTF data is embedded in the library */
#define ALSOFT_EMBED_HRTF_DATA

#ifdef _WIN32

#define SIZEOF_LONG			4
#define SIZEOF_LONG_LONG	8

#define HAVE__ALIGNED_MALLOC
#ifdef __clang__
#define HAVE_GCC_GET_CPUID
#define HAVE_CPUID_H
#endif
#define HAVE_CPUID_INTRINSIC
#define HAVE_SSE_INTRINSICS
#define HAVE_SSE
#define HAVE_SSE2
#define HAVE_SSE3
#define HAVE_SSE4_1
#define HAVE_MMDEVAPI
#define HAVE_DSOUND
#define HAVE_WINMM
#define HAVE_WAVE
#define HAVE_WASAPI
#define HAVE_XMMINTRIN_H
#define HAVE_MALLOC_H
#define HAVE_INTRIN_H
#define HAVE_GUIDDEF_H
#endif	/*fdef _WIN32*/

#if defined(__APPLE__) && defined(__MACH__)

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
#endif	/*if defined(__APPLE__) && defined(__MACH__)*/

#ifdef __ANDROID__
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

#define HAVE_ARM_NEON_H
#define HAVE_OPENSL
#define HAVE_WAVE
#define HAVE_STAT
#define HAVE_LRINTF
#define HAVE_STRTOF
#define HAVE_GCC_DESTRUCTOR
#define HAVE_GCC_FORMAT
#define HAVE_STDINT_H
#define HAVE_DLFCN_H
#define HAVE_XMMINTRIN_H
#define HAVE_FLOAT_H
#define HAVE_FENV_H
#define HAVE_PTHREAD_SETSCHEDPARAM
#endif /*ifdef __ANDROID__*/

#endif /*ifndef CONFIG_H*/
