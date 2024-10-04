#ifndef CONFIG_H
#define CONFIG_H

/* #define AL_ALEXT_PROTOTYPES */

/* Define if deprecated EAX extensions are enabled */
#define ALSOFT_EAX

/* Define if HRTF data is embedded in the library */
#define ALSOFT_EMBED_HRTF_DATA

#ifdef _WIN32
#include "config_win32.h"
#endif	/*fdef _WIN32*/

#if defined(__APPLE__) && defined(__MACH__)
#include "config_apple.h"
#endif	/*if defined(__APPLE__) && defined(__MACH__)*/

#ifdef __ANDROID__
#include "config_android.h"
#endif /* ifdef __ANDROID__*/

#if defined(__linux__) && !defined(__ANDROID__)
#include "config_linux.h"
#endif /* if defined(__linux__) && !defined(__ANDROID__) */

#endif /*ifndef CONFIG_H*/
