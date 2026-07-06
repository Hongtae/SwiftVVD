/*******************************************************************************
 File: Thread.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2026 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

void VVDThreadYield();
uintptr_t VVDThreadCurrentId();

void* VVDThreadLocalGet(const void* slot);
void VVDThreadLocalSet(const void* slot, void* value);

#ifdef __cplusplus
}
#endif /* __cplusplus */
