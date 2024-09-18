/*******************************************************************************
 File: Malloc.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdlib.h>

#ifdef __cplusplus
inline auto VVDMalloc(size_t s)  { return malloc(s); }
inline auto VVDFree(void* p)     { return free(p); }
#endif /* __cplusplus */
