/*******************************************************************************
 File: AtomicNumber.h
 Author: Hongtae Kim (tiff2766@gmail.com)

 Copyright (c) 2004-2024 Hongtae Kim. All rights reserved.
 
*******************************************************************************/

#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

typedef struct _VVDAtomicNumber32
{
    volatile int32_t value;
} VVDAtomicNumber32;

int32_t VVDAtomicNumber32_Increment(VVDAtomicNumber32*);                  /* +1, returns resulting incremented value. */ 
int32_t VVDAtomicNumber32_Decrement(VVDAtomicNumber32*);                  /* -1, returns resulting decremented value. */
int32_t VVDAtomicNumber32_Add(VVDAtomicNumber32*, int32_t addend);        /* +addend, returns resulting added value. */

int32_t VVDAtomicNumber32_Exchange(VVDAtomicNumber32*, int32_t value);    /* set value, returns previous value. */

/* compare and set when equal. return true when operation succeeded. */
bool VVDAtomicNumber32_CompareAndSet(VVDAtomicNumber32*, int32_t comparand, int32_t value);
int32_t VVDAtomicNumber32_Value(VVDAtomicNumber32*); /* return value, not synchronized */

typedef struct _VVDAtomicNumber64
{
    volatile int64_t value;
} VVDAtomicNumber64;

int64_t VVDAtomicNumber64_Increment(VVDAtomicNumber64*);                  /* +1, returns resulting incremented value. */ 
int64_t VVDAtomicNumber64_Decrement(VVDAtomicNumber64*);                  /* -1, returns resulting decremented value. */
int64_t VVDAtomicNumber64_Add(VVDAtomicNumber64*, int64_t addend);        /* +addend, returns resulting added value. */

int64_t VVDAtomicNumber64_Exchange(VVDAtomicNumber64*, int64_t value);    /* set value, returns previous value. */

/* compare and set when equal. return true when operation succeeded. */
bool VVDAtomicNumber64_CompareAndSet(VVDAtomicNumber64*, int64_t comparand, int64_t value);
int64_t VVDAtomicNumber64_Value(VVDAtomicNumber64*); /* return value, not synchronized */

#ifdef __cplusplus
}
#endif /* __cplusplus */
