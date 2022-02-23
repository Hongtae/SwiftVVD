/*******************************************************************************
 File: DKThread.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

void DKThreadSleep(double d);
void DKThreadYield();

#ifdef __cplusplus
}
#endif /* __cplusplus */
