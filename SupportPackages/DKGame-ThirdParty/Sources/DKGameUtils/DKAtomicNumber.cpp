/*******************************************************************************
 File: DKAtomicNumber.cpp
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#ifdef _WIN32
#include <windows.h>
#endif
#if defined(__APPLE__) && defined(__MACH__)
#include <libkern/OSAtomic.h>
#endif

#include "DKAtomicNumber.h"

extern "C" int32_t DKAtomicNumber32_Increment(DKAtomicNumber32* atomic)
{
	int32_t value;
#ifdef _WIN32
	value = ::InterlockedIncrement((LONG*)&atomic->value);
#elif defined(__APPLE__) && defined(__MACH__)
	value = ::OSAtomicIncrement32(&atomic->value);
#else
	value = __sync_add_and_fetch(&atomic->value, 1);
#endif
	return value;
}

extern "C" int32_t DKAtomicNumber32_Decrement(DKAtomicNumber32* atomic)
{
	int32_t value;
#ifdef _WIN32
	value = ::InterlockedDecrement((LONG*)&atomic->value);
#elif defined(__APPLE__) && defined(__MACH__)
	value = ::OSAtomicDecrement32(&atomic->value);
#else
	value = __sync_sub_and_fetch(&atomic->value, 1);
#endif
	return value;
}

extern "C" int32_t DKAtomicNumber32_Add(DKAtomicNumber32* atomic, int32_t addend)
{
	int32_t value;
#ifdef _WIN32
	value = ::InterlockedExchangeAdd((LONG*)&atomic->value, addend);
    value += addend;
#elif defined(__APPLE__) && defined(__MACH__)
	value = ::OSAtomicAdd32(addend, &atomic->value);
#else
	value = __sync_add_and_fetch(&atomic->value, addend);
#endif
	return value;
}

extern "C" int32_t DKAtomicNumber32_Exchange(DKAtomicNumber32* atomic, int32_t value)
{
	int32_t prev;
#ifdef _WIN32
	prev = ::InterlockedExchange((LONG*)&atomic->value, value);
#elif defined(__APPLE__) && defined(__MACH__)
	do 	{
		prev = atomic->value;
	} while (!::OSAtomicCompareAndSwap32(prev, value, &atomic->value));
#else
	do {
		prev = atomic->value;
	} while (__sync_val_compare_and_swap(&atomic->value, prev, value) != prev);
#endif
	return prev;
}

extern "C" bool DKAtomicNumber32_CompareAndSet(DKAtomicNumber32* atomic, int32_t comparand, int32_t value)
{
#ifdef _WIN32
	return ::InterlockedCompareExchange((LONG*)&atomic->value, value, comparand) == comparand;
#elif defined(__APPLE__) && defined(__MACH__)
	return ::OSAtomicCompareAndSwap32(comparand, value, &atomic->value);
#else
	return __sync_bool_compare_and_swap(&atomic->value, comparand, value);
#endif
}

extern "C" int32_t DKAtomicNumber32_Value(DKAtomicNumber32* atomic)
{
	return atomic->value;
}

extern "C" int64_t DKAtomicNumber64_Increment(DKAtomicNumber64* atomic)
{
	int64_t value;
#ifdef _WIN32
	value = ::InterlockedIncrement64((LONGLONG*)&atomic->value);
#elif defined(__APPLE__) && defined(__MACH__)
	value = ::OSAtomicIncrement64(&atomic->value);
#else
	value = __sync_add_and_fetch(&atomic->value, 1);
#endif
	return value;
}

extern "C" int64_t DKAtomicNumber64_Decrement(DKAtomicNumber64* atomic)
{
	int64_t value;
#ifdef _WIN32
	value = ::InterlockedDecrement64((LONGLONG*)&atomic->value);
#elif defined(__APPLE__) && defined(__MACH__)
	value = ::OSAtomicDecrement64(&atomic->value);
#else
	value = __sync_sub_and_fetch(&atomic->value, 1);
#endif
	return value;
}

extern "C" int64_t DKAtomicNumber64_Add(DKAtomicNumber64* atomic, int64_t addend)
{
	int64_t value;
#ifdef _WIN32
	value = ::InterlockedExchangeAdd64((LONGLONG*)&atomic->value, addend);
    value += addend;
#elif defined(__APPLE__) && defined(__MACH__)
	value = ::OSAtomicAdd64(addend, &atomic->value);
#else
	value = __sync_add_and_fetch(&atomic->value, addend);
#endif
	return value;
}

extern "C" int64_t DKAtomicNumber64_Exchange(DKAtomicNumber64* atomic, int64_t value)
{
	int64_t prev;
#ifdef _WIN32
	prev = ::InterlockedExchange64((LONGLONG*)&atomic->value, value);
#elif defined(__APPLE__) && defined(__MACH__)
	do 	{
		prev = atomic->value;
	} while (!::OSAtomicCompareAndSwap64(prev, value, &atomic->value));
#else
	do {
		prev = atomic->value;
	} while (__sync_val_compare_and_swap(&atomic->value, prev, value) != prev);
#endif
	return prev;
}

extern "C" bool DKAtomicNumber64_CompareAndSet(DKAtomicNumber64* atomic, int64_t comparand, int64_t value)
{
#ifdef _WIN32
	return ::InterlockedCompareExchange64((LONGLONG*)&atomic->value, value, comparand) == comparand;
#elif defined(__APPLE__) && defined(__MACH__)
	return ::OSAtomicCompareAndSwap64(comparand, value, &atomic->value);
#else
	return __sync_bool_compare_and_swap(&atomic->value, comparand, value);
#endif
}

extern "C" int64_t DKAtomicNumber64_Value(DKAtomicNumber64* atomic)
{
	return atomic->value;
}
