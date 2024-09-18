/*******************************************************************************
 File: Endianness.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>
#if !defined(__BIG_ENDIAN__) && !defined(__LITTLE_ENDIAN__)
#error System endianness not defined.
#endif

#ifdef __cplusplus
#include <type_traits>

/// byteorder swap template functions.
inline uint8_t VVDSwitchIntegralByteOrder(uint8_t n)
{
    static_assert(sizeof(uint8_t) == 1, "Invalid type size");
    return n;
}
/// byteorder swap template functions.
inline uint16_t VVDSwitchIntegralByteOrder(uint16_t n)
{
    static_assert(sizeof(uint16_t) == 2, "Invalid type size");
    return
        ((n & 0xff00) >> 8) |
        ((n & 0x00ff) << 8);
}
/// byteorder swap template functions.
inline uint32_t VVDSwitchIntegralByteOrder(uint32_t n)
{
    static_assert(sizeof(uint32_t) == 4, "Invalid type size");
    return
        ((n & 0xff000000) >> 24) |
        ((n & 0x00ff0000) >> 8) |
        ((n & 0x0000ff00) << 8) |
        ((n & 0x000000ff) << 24);
}
/// byteorder swap template functions.
inline uint64_t VVDSwitchIntegralByteOrder(uint64_t n)
{
    static_assert(sizeof(uint64_t) == 8, "Invalid type size");
    return
        ((n & 0xff00000000000000ULL) >> 56) |
        ((n & 0x00ff000000000000ULL) >> 40) |
        ((n & 0x0000ff0000000000ULL) >> 24) |
        ((n & 0x000000ff00000000ULL) >> 8) |
        ((n & 0x00000000ff000000ULL) << 8) |
        ((n & 0x0000000000ff0000ULL) << 24) |
        ((n & 0x000000000000ff00ULL) << 40) |
        ((n & 0x00000000000000ffULL) << 56);
}

template <int i> struct VVDNumber {enum {Value = i};	};

/// swap byte order for 1 byte (actually does nothing)
template <typename T> inline T VVDSwitchIntegralByteOrder(T n, VVDNumber<1>)
{
    static_assert(sizeof(T) == 1, "Invalid type size");
    auto r = VVDSwitchIntegralByteOrder(reinterpret_cast<uint8_t&>(n));
    return reinterpret_cast<T&>(r);
}
/// swap byte order for 2 bytes
template <typename T> inline T VVDSwitchIntegralByteOrder(T n, VVDNumber<2>)
{
    static_assert(sizeof(T) == 2, "Invalid type size");
    auto r = VVDSwitchIntegralByteOrder(reinterpret_cast<uint16_t&>(n));
    return reinterpret_cast<T&>(r);
}
/// swap byte order for 4 bytes
template <typename T> inline T VVDSwitchIntegralByteOrder(T n, VVDNumber<4>)
{
    static_assert(sizeof(T) == 4, "Invalid type size");
    auto r = VVDSwitchIntegralByteOrder(reinterpret_cast<uint32_t&>(n));
    return reinterpret_cast<T&>(r);
}
/// swap byte order for 8 bytes
template <typename T> inline T VVDSwitchIntegralByteOrder(T n, VVDNumber<8>)
{
    static_assert(sizeof(T) == 8, "Invalid type size");
    auto r = VVDSwitchIntegralByteOrder(reinterpret_cast<uint64_t&>(n));
    return reinterpret_cast<T&>(r);
}

/// change byte order: System -> Big-Endian
template <typename T> inline T VVDSystemToBigEndian(T n)
{
    static_assert(std::is_integral<T>::value, "Argument must be integer.");
#ifdef __LITTLE_ENDIAN__
    return VVDSwitchIntegralByteOrder(n, VVDNumber<sizeof(T)>());
#endif
    return n;
}
/// change byte order: Big-Endian to System
template <typename T> inline T VVDBigEndianToSystem(T n)
{
    static_assert(std::is_integral<T>::value, "Argument must be integer.");
#ifdef __LITTLE_ENDIAN__
    return VVDSwitchIntegralByteOrder(n, VVDNumber<sizeof(T)>());
#endif
    return n;
}

/// change byte order: System -> Little-Endian
template <typename T> inline T VVDSystemToLittleEndian(T n)
{
    static_assert(std::is_integral<T>::value, "Argument must be integer.");
#ifdef __BIG_ENDIAN__
    return VVDSwitchIntegralByteOrder(n, VVDNumber<sizeof(T)>());
#endif
    return n;
}
/// change byte order: Little-Endian to System
template <typename T> inline T VVDLittleEndianToSystem(T n)
{
    static_assert(std::is_integral<T>::value, "Argument must be integer.");
#ifdef __BIG_ENDIAN__
    return VVDSwitchIntegralByteOrder(n, VVDNumber<sizeof(T)>());
#endif
    return n;
}


/// runtime byte order test.
/// using preprocessor macros at compile-time and validate in run-time.
/// middle-endian is not supported.
enum class VVDByteOrder  
{
    Unknown,
    BigEndian,
    LittleEndian,
};
inline VVDByteOrder VVDRuntimeByteOrder()
{
    union
    {
        uint8_t c[4];
        uint32_t i;
    } val = { 0x01, 0x02, 0x03, 0x04 };

    switch (val.i)
    {
        case 0x01020304U:	return VVDByteOrder::BigEndian;		break;
        case 0x04030201U:	return VVDByteOrder::LittleEndian;	break;
    }
    return VVDByteOrder::Unknown;
}

inline bool VVDVerifyByteOrder()
{
#if     defined(__BIG_ENDIAN__)
    return VVDRuntimeByteOrder() == VVDByteOrder::BigEndian;
#elif  defined(__LITTLE_ENDIAN__)
    return VVDRuntimeByteOrder() == VVDByteOrder::LittleEndian;
#endif
}

#endif // __cplusplus
