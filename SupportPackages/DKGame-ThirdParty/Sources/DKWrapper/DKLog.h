/*******************************************************************************
 File: DKLog.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once
#include <stdio.h>
#include <stdlib.h>

#ifdef __cplusplus
#define DKLog(fmt, ...)       fprintf(stdout, fmt, ## __VA_ARGS__)
#define DKLogE(fmt, ...)      fprintf(stderr, fmt, ## __VA_ARGS__)
#define DKLogW(fmt, ...)      fprintf(stderr, fmt, ## __VA_ARGS__) 
#endif /* __cplusplus */
