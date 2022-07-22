/*******************************************************************************
 File: DKThread.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <pthread.h>
#include <sys/select.h>
#include <sched.h>  // to using sched_yield() in DKThread::Yield()
#include <errno.h>
#include <limits.h>
#endif

#include "DKThread.h"

#ifndef POSIX_USE_SELECT_SLEEP
/// Set POSIX_USE_SELECT_SLEEP to 1 if you want use 'select' instead of 'nanosleep'.
/// ignored on Win32.
#define POSIX_USE_SELECT_SLEEP  1
#endif

extern "C" void DKThreadSleep(double d)
{
    if (d < 0.0)
        d = 0.0;

#ifdef _WIN32
    DWORD dwTime = static_cast<DWORD>(d * 1000.0f);
    ::Sleep(dwTime);
#elif POSIX_USE_SELECT_SLEEP
    timeval tm;
    uint64_t ms = (uint64_t)(d * 1000000.0);
    tm.tv_sec = ms / 1000000;
    tm.tv_usec = ms % 1000000;
    select(0, 0, 0, 0, &tm);
#else
    long sec = static_cast<long>(d);
    long usec = (d - sec) * 1000000;
    struct timespec req = {sec, usec * 1000};
    while ( nanosleep(&req, &req) != 0 )
    {
        // internal error! (except for signal, intrrupt)
        if (errno != EINTR)
            break;
    }
#endif
}

extern "C" void DKThreadYield()
{
#ifdef _WIN32
    if (SwitchToThread() == 0)
        DKThreadSleep(0);
#else
    if (sched_yield() != 0)
        DKThreadSleep(0);
#endif
}

extern "C" uintptr_t DKThreadCurrentId()
{
    #ifdef _WIN32
    return (uintptr_t)::GetCurrentThreadId();
#else
    return (uintptr_t)pthread_self();
#endif
}
