/*******************************************************************************
 File: Thread.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2026 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#include <unordered_map>
#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <pthread.h>
#include <sched.h>
#endif

#include "Thread.h"

extern "C" void VVDThreadYield()
{
#ifdef _WIN32
    if (SwitchToThread() == 0)
    {
        YieldProcessor();
        //Sleep(0);
    }
#else
    if (sched_yield() != 0)
    {
        struct timespec req = {0, 1};
        nanosleep(&req, nullptr);
    }
#endif
}

extern "C" uintptr_t VVDThreadCurrentId()
{
#ifdef _WIN32
    return (uintptr_t)::GetCurrentThreadId();
#else
    return (uintptr_t)pthread_self();
#endif
}

static thread_local std::unordered_map<const void *, void *> values;

extern "C" void* VVDThreadLocalGet(const void* slot)
{
    if (!slot)
        return nullptr;

    auto it = values.find(slot);
    if (it != values.end())
        return it->second;
    return nullptr;
}

extern "C" void VVDThreadLocalSet(const void* slot, void* value)
{
    if (!slot)
        return;

    if (value)
        values[slot] = value;
    else
        values.erase(slot);
}
