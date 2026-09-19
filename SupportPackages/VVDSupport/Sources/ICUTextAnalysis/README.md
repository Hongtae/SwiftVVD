# ICU text analysis

`ICUTextAnalysis` is a static library product in the `VVDSupport` package. Its C
adapter exposes ICU line-boundary, script, and Unicode property queries to VVD
without including ICU declarations in VVD's public Swift interface. The Swift
iterator owns the immutable UTF-16 buffer and closes its cursor before releasing
that buffer. Each cursor is confined to one layout operation; it is not shared
across threads.

The package links the system ICU C library: `icucore` on macOS/iOS,
`icu` on Windows 10 version 1903 or later, and `icuuc` on Linux. Linux builds
require the ICU development package (`libicu-dev` on Debian/Ubuntu).
The platform's ICU release supplies the Unicode rules and locale data.

References: [ICU boundary API](https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/ubrk_8h.html)
and [Windows ICU availability](https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-).
