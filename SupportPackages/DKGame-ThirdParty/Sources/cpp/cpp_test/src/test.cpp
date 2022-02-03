#include <stdio.h>

#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)

extern "C"
void cpp_test12()
{
#ifdef _WIN32
    printf("_WIN32 defined.\n");
#else
    printf("_WIN32 NOT defined.\n");
#endif

#ifdef DEBUG
    printf("DEBUG defined.\n");
#else
    printf("DEBUG NOT defined.\n");
#endif
#ifdef _DEBUG
    printf("_DEBUG defined.\n");
#else
    printf("_DEBUG NOT defined.\n");
#endif
#ifdef NDEBUG
    printf("NDEBUG defined.\n");
#else
    printf("NDEBUG NOT defined.\n");
#endif
#ifdef _NDEBUG
    printf("_NDEBUG defined.\n");
#else
    printf("_NDEBUG NOT defined.\n");
#endif
#ifdef __clang__
    printf("__clang__ defined. (%s)\n", TOSTRING(__clang__));
#else
    printf("__clang__ NOT defined.\n");
#endif
#ifdef __clang_version__
    printf("__clang_version__ defined. (%s)\n", TOSTRING(__clang_version__));
#else
    printf("__clang_version__ NOT defined.\n");
#endif

    printf("__cplusplus: %s\n", TOSTRING(__cplusplus) );
    printf("_MSC_VER: %s\n", TOSTRING(_MSC_VER) );

    int a = 0;
#ifdef DKGL_CPP_TEST
    a = DKGL_CPP_TEST;
#endif
    printf("[C++] cpp_test12 from Externals (DKGL_CPP_TEST:%d)\n", a);
}
