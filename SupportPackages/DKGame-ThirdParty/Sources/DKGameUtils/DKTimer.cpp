/*******************************************************************************
 File: DKTimer.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#include <time.h>
#include <math.h>

#ifdef _WIN32
    #include <windows.h>
#elif defined(__APPLE__) && defined(__MACH__)
    #include <mach/mach.h>
    #include <mach/mach_time.h>
#elif defined(__linux__)
    #include <time.h>
#else
    #include <sys/time.h>
    #warning High-Resolution Timer Unsupported. (Unknown OS)
#endif

#include "DKTimer.h"

extern "C"
uint64_t DKTimerSystemTick()
{
#ifdef _WIN32
    LARGE_INTEGER count;
    ::QueryPerformanceCounter(&count);
    return count.QuadPart;
#elif defined(__APPLE__) && defined(__MACH__)
    return mach_absolute_time();
#elif defined(__linux__)
    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 0;
    clock_gettime(CLOCK_MONOTONIC_HR, &ts);
    return static_cast<Tick>(ts.tv_sec) * 1000000000ULL + ts.tv_nsec;
#else
    timeval tm;
    gettimeofday(&tm, NULL);
    return static_cast<Tick>(tm.tv_sec) * 1000000ULL + tm.tv_usec;
#endif
}

extern "C"
uint64_t DKTimerSystemTickFrequency()
{
#ifdef _WIN32
    static LONGLONG frequency = []()->LONGLONG
    {
        LARGE_INTEGER frequency;
        ::QueryPerformanceFrequency(&frequency);
        return frequency.QuadPart;
    }();
    return frequency;
#elif defined(__APPLE__) && defined(__MACH__)
    static uint64_t frequency = []()->uint64_t
    {
        mach_timebase_info_data_t base;
        mach_timebase_info(&base);
        uint64_t frequency = 1000000000ULL * base.denom / base.numer;
        return frequency;
    }();
    return frequency;
#elif defined(__linux__)
    return 1000000000ULL;
#else
    return 1000000ULL;
#endif
}
