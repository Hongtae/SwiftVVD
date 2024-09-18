/*******************************************************************************
 File: Timer.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

uint64_t VVDTimerSystemTick();
uint64_t VVDTimerSystemTickFrequency();

#ifdef __cplusplus
}
#endif /* __cplusplus */
