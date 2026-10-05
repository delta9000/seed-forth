#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <wchar.h>
#include <wctype.h>
#include <inttypes.h>
int main(void)
{
    int i;
    int result;
    wchar_t wide;
    char bytes[2];
    int object;
    intptr_t address = (intptr_t)&object;
    if (sizeof(wchar_t) != 4 || (wchar_t)-1 >= 0 || sizeof(wint_t) != 4
        || (wint_t)-1 == 0 || WEOF != (wint_t)-1
        || sizeof(intptr_t) != sizeof(void *) || (void *)address != &object) return 1;
    if (!setlocale(LC_ALL, "C") || MB_CUR_MAX != 1) return 2;
#ifndef WIDE_HOST_ORACLE
    if (MB_LEN_MAX != 1) return 3;
#endif
    for (i = 0; i < 256; i++) {
        bytes[0] = (char)i; bytes[1] = 0; wide = 999; errno = EDOM;
        result = mbtowc(&wide, bytes, 1);
        printf("m %d %d %d %d\n", i, result, (int)wide, errno);
        bytes[0] = '!'; errno = EDOM;
        result = wctomb(bytes, (wchar_t)i);
        printf("w %d %d %u %d\n", i, result, (unsigned int)(unsigned char)bytes[0], errno);
        printf("c %d %d %d\n", i, !!iswprint((wint_t)i), !!iswspace((wint_t)i));
    }
    wide = 999; errno = EDOM;
    if (mbtowc(&wide, NULL, 0) != 0 || wide != 999 || errno != EDOM) return 4;
    if (wctomb(NULL, (wchar_t)-1) != 0 || errno != EDOM) return 5;
    if (mbtowc(NULL, "A", 1) != 1 || errno != EDOM) return 6;
    if (mbtowc(&wide, "A", 0) != -1 || wide != 999) return 7;
#ifndef WIDE_HOST_ORACLE
    /* The bounded implementation chooses EILSEQ for incomplete input. */
    if (errno != EILSEQ) return 7;
#endif
    bytes[0] = '!';
    if (wctomb(bytes, (wchar_t)-1) != -1 || errno != EILSEQ || bytes[0] != '!') return 8;
    if (wctomb(bytes, (wchar_t)2147483647) != -1 || errno != EILSEQ) return 9;
    if (iswprint(WEOF) || iswspace(WEOF) || iswprint((wint_t)0x10000)
        || iswspace((wint_t)0x2003)) return 10;
    puts("boundaries passed");
    return 0;
}
