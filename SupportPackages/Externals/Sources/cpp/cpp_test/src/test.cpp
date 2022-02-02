#include <stdio.h>

extern "C"
void cpp_test12()
{
    int a = 0;
#ifdef DKGL_CPP_TEST
    a = DKGL_CPP_TEST;
#endif
    printf("[C++] cpp_test12 from Externals (DKGL_CPP_TEST:%d)\n", a);
}
