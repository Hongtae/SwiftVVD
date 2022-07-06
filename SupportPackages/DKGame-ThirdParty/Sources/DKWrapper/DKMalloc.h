/*******************************************************************************
 File: DKMalloc.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once
#include <stdlib.h>

#ifdef __cplusplus
inline auto DKMalloc(size_t s)  { return malloc(s); }
inline auto DKFree(void* p)     { return free(p); }
#endif /* __cplusplus */
