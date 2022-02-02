#include <stdio.h>

extern "C"
void DKGameCppTest()
{
    int a = 0;
#ifdef DKGL_CPP_TEST
    a = DKGL_CPP_TEST;
#endif
    printf("[C++] DKGame C++! (DKGL_CPP_TEST:%d)\n", a);
}
