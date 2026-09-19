//
//  File: ICUTextAnalysis.h
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#pragma once

#include <stdint.h>

// The caller retains the UTF-16 buffer until close. Nonpositive error codes
// indicate success, including locale fallback warnings.
void *ICUTextLineBreakOpen(const uint16_t *text, int32_t length,
                          const char *locale, int32_t *error);
void ICUTextLineBreakClose(void *iterator);
// Returns the strict UTF-16 predecessor, or -1 when no boundary exists.
int32_t ICUTextLineBreakPreceding(void *iterator, int32_t index);
int ICUTextIsHangul(int32_t scalar);

int32_t ICUTextGetScript(int32_t scalar);
const char *ICUTextGetScriptName(int32_t script);
int ICUTextHasScript(int32_t scalar, int32_t script);
int ICUTextIsNonspacingMark(int32_t scalar);
int32_t ICUTextGetIntProperty(int32_t scalar, int32_t property);
int ICUTextHasBinaryProperty(int32_t scalar, int32_t property);
