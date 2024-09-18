/*******************************************************************************
 File: Log.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdio.h>
#include <stdlib.h>

#ifdef __cplusplus
#define VVDLog(fmt, ...)       fprintf(stdout, fmt, ## __VA_ARGS__)
#define VVDLogE(fmt, ...)      fprintf(stderr, fmt, ## __VA_ARGS__)
#define VVDLogW(fmt, ...)      fprintf(stderr, fmt, ## __VA_ARGS__) 
#endif /* __cplusplus */
