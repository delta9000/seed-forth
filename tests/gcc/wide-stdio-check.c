/* Original seed-forth regression fixture; see LICENSE. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <locale.h>
#include <wchar.h>
#ifndef WIDE_HOST_ORACLE
#include <seed-syscall.h>
#endif

static void record(int result, const unsigned char *buffer)
{
    int i;
    printf("%d ", result);
    for (i = 0; i < 64; i++) printf("%02x", (unsigned int)buffer[i]);
    putchar('\n');
}

int main(int argc, char **argv)
{
    static wchar_t texts[3][6] = {{0}, {'a','b','c',0}, {'A',127,'\t','z',0}};
    static int widths[4] = {-9,0,2,9};
    static int precisions[5] = {-1,0,1,3,9};
    static unsigned int capacities[6] = {0,1,2,4,12,64};
    static wint_t characters[4] = {0,32,65,127};
    wchar_t invalid[3] = {'A',128,0};
    unsigned char buffer[64];
    int t, w, p, n, result, i;
    FILE *stream;
    wint_t value;
#ifndef WIDE_HOST_ORACLE
    long mapping;
    wchar_t *edge;
    const char *unsupported[6] = {"%lls","%hs","%zs","%ts","%js","%l%"};
#endif
    if (argc != 5 || setlocale(LC_ALL,"C") == NULL) return 1;
    for (t = 0; t < 3; t++) for (w = 0; w < 4; w++)
    for (p = 0; p < 5; p++) for (n = 0; n < 6; n++) {
        memset(buffer,'X',sizeof(buffer));
        result = snprintf((char *)buffer,capacities[n],"[%*.*ls]",widths[w],precisions[p],texts[t]);
        record(result,buffer);
    }
    for (t = 0; t < 4; t++) for (w = 0; w < 4; w++) for (n = 0; n < 6; n++) {
        memset(buffer,'X',sizeof(buffer));
        result = snprintf((char *)buffer,capacities[n],"[%*lc]",widths[w],characters[t]);
        record(result,buffer);
    }
    if (snprintf((char *)buffer,sizeof(buffer),"%ls/%ls/%ls/%lc/%ls/%lc/%ls/%ls",texts[1],texts[1],texts[1],(wint_t)'X',texts[1],(wint_t)'Y',texts[1],texts[1]) != 27) return 2;
    if (strcmp((char *)buffer,"abc/abc/abc/X/abc/Y/abc/abc")) return 3;
    errno = EDOM;
    if (snprintf((char *)buffer,sizeof(buffer),"%.1ls",invalid) != 1 || strcmp((char *)buffer,"A") || errno != EDOM) return 4;
    errno = 0;
    if (snprintf((char *)buffer,sizeof(buffer),"%ls",invalid) != -1 || errno != EILSEQ) return 5;
    errno = 0;
    if (snprintf((char *)buffer,sizeof(buffer),"%lc",(wint_t)128) != -1 || errno != EILSEQ) return 6;
    errno = 0;
    if (snprintf(NULL,0,"%ls",invalid) != -1 || errno != EILSEQ) return 7;
    stream = fopen(argv[1],"r");
    if (stream == NULL) return 8;
    for (i = 0; i < 128; i++) {
        errno = EDOM; value = getwc(stream);
        if (value != (wint_t)i || errno != EDOM || ferror(stream) || feof(stream)) return 9;
    }
    errno = EDOM;
    if (getwc(stream) != WEOF || errno != EDOM || ferror(stream) || !feof(stream)) return 10;
    clearerr(stream);
    if (feof(stream) || ferror(stream) || fclose(stream)) return 11;
    for (i = 2; i <= 3; i++) {
        stream = fopen(argv[i],"r");
        if (stream == NULL) return 12;
        errno = 0;
        if (getwc(stream) != WEOF || errno != EILSEQ || !ferror(stream)) return 13;
        clearerr(stream);
        if (ferror(stream) || fclose(stream)) return 14;
    }
    stream = fopen(argv[4],"w");
    if (stream == NULL) return 15;
    if (fprintf(stream,"[%6.2ls][%-3lc]",texts[1],(wint_t)'Q') != 13 || fflush(stream) || fclose(stream)) return 16;
#ifndef WIDE_HOST_ORACLE
    for (i = 0; i < 6; i++) {
        errno = 0;
        if (snprintf((char *)buffer,sizeof(buffer),unsupported[i]) != -1 || errno != EINVAL) return 17;
    }
    mapping = __seed_syscall6(9,0,8192,3,34,-1,0);
    if (mapping < 0) return 18;
    edge = (wchar_t *)(mapping + 4096 - 3 * sizeof(wchar_t));
    edge[0] = 'A'; edge[1] = 'B'; edge[2] = 'C';
    if (__seed_syscall6(10,mapping + 4096,4096,0,0,0,0)) return 19;
    if (snprintf((char *)buffer,sizeof(buffer),"%.3ls/%.0ls",edge,edge+3) != 4 || strcmp((char *)buffer,"ABC/")) return 20;
    if (__seed_syscall6(11,mapping,8192,0,0,0,0)) return 21;
    if (snprintf((char *)buffer,sizeof(buffer),"%.3ls",(wchar_t *)0) != 3 || strcmp((char *)buffer,"(nu")) return 22;
#endif
    puts("wide streams passed");
    return 0;
}
