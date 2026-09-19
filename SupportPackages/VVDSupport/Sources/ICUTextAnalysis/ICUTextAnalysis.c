//
//  File: ICUTextAnalysis.c
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#include "ICUTextAnalysis.h"

#if defined(__APPLE__)
// The SDK exports the stable C ABI without installing the ICU headers.
typedef uint16_t UChar;
typedef int32_t UErrorCode;
typedef struct UBreakIterator UBreakIterator;
extern UBreakIterator *ubrk_open(int32_t type, const char *locale,
                                 const UChar *text, int32_t length, UErrorCode *status);
extern void ubrk_close(UBreakIterator *iterator);
extern int32_t ubrk_preceding(UBreakIterator *iterator, int32_t offset);
extern int32_t uscript_getScript(int32_t scalar, UErrorCode *status);
extern const char *uscript_getShortName(int32_t script);
extern int8_t uscript_hasScript(int32_t scalar, int32_t script);
extern int8_t u_charType(int32_t scalar);
extern int32_t u_getIntPropertyValue(int32_t scalar, int32_t property);
extern int8_t u_hasBinaryProperty(int32_t scalar, int32_t property);
enum { UBRK_LINE = 2, USCRIPT_HANGUL = 18 };
#elif defined(_WIN32)
#include <icu.h>
#else
#include <unicode/ubrk.h>
#include <unicode/uscript.h>
#include <unicode/uchar.h>
#endif

void *ICUTextLineBreakOpen(const uint16_t *text, int32_t length,
                          const char *locale, int32_t *error) {
    UErrorCode status = 0;
    UBreakIterator *iterator = ubrk_open(UBRK_LINE, locale, (const UChar *)text,
                                        length, &status);
    *error = (int32_t)status;
    return iterator;
}

void ICUTextLineBreakClose(void *iterator) { ubrk_close((UBreakIterator *)iterator); }
int32_t ICUTextLineBreakPreceding(void *iterator, int32_t index) {
    return ubrk_preceding((UBreakIterator *)iterator, index);
}
int ICUTextIsHangul(int32_t scalar) {
    UErrorCode status = 0;
    return uscript_getScript(scalar, &status) == USCRIPT_HANGUL && status <= 0;
}

int32_t ICUTextGetScript(int32_t scalar) {
    UErrorCode status = 0;
    int32_t script = uscript_getScript(scalar, &status);
    return status <= 0 ? script : -1;
}
const char *ICUTextGetScriptName(int32_t script) { return uscript_getShortName(script); }
int ICUTextHasScript(int32_t scalar, int32_t script) { return uscript_hasScript(scalar, script); }
int ICUTextIsNonspacingMark(int32_t scalar) { return u_charType(scalar) == 6; }
int32_t ICUTextGetIntProperty(int32_t scalar, int32_t property) {
    return u_getIntPropertyValue(scalar, property);
}
int ICUTextHasBinaryProperty(int32_t scalar, int32_t property) {
    return u_hasBinaryProperty(scalar, property);
}
