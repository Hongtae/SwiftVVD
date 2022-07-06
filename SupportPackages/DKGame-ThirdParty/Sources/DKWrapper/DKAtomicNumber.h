/*******************************************************************************
 File: DKAtomicNumber.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2022 Hongtae Kim. All rights reserved.
 
 Copyright notice:
 - This is a simplified part of DKGL.
 - The full version of DKGL can be found at https://github.com/Hongtae/DKGL

 License: https://github.com/Hongtae/DKGL/blob/master/LICENSE

*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef struct _DKAtomicNumber32
{
    volatile int32_t value;
} DKAtomicNumber32;

int32_t DKAtomicNumber32_Increment(DKAtomicNumber32*);                  /* +1, returns resulting incremented value. */ 
int32_t DKAtomicNumber32_Decrement(DKAtomicNumber32*);                  /* -1, returns resulting decremented value. */
int32_t DKAtomicNumber32_Add(DKAtomicNumber32*, int32_t addend);        /* +addend, returns resulting added value. */

int32_t DKAtomicNumber32_Exchange(DKAtomicNumber32*, int32_t value);    /* set value, returns previous value. */

/* compare and set when equal. return true when operation succeeded. */
bool DKAtomicNumber32_CompareAndSet(DKAtomicNumber32*, int32_t comparand, int32_t value);
int32_t DKAtomicNumber32_Value(DKAtomicNumber32*); /* return value, not synchronized */

typedef struct _DKAtomicNumber64
{
    volatile int64_t value;
} DKAtomicNumber64;

int64_t DKAtomicNumber64_Increment(DKAtomicNumber64*);                  /* +1, returns resulting incremented value. */ 
int64_t DKAtomicNumber64_Decrement(DKAtomicNumber64*);                  /* -1, returns resulting decremented value. */
int64_t DKAtomicNumber64_Add(DKAtomicNumber64*, int64_t addend);        /* +addend, returns resulting added value. */

int64_t DKAtomicNumber64_Exchange(DKAtomicNumber64*, int64_t value);    /* set value, returns previous value. */

/* compare and set when equal. return true when operation succeeded. */
bool DKAtomicNumber64_CompareAndSet(DKAtomicNumber64*, int64_t comparand, int64_t value);
int64_t DKAtomicNumber64_Value(DKAtomicNumber64*); /* return value, not synchronized */

#ifdef __cplusplus
}
#endif /* __cplusplus */
