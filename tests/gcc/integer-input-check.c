/* Original seed-forth regression fixture; see LICENSE. */
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#ifndef INTEGER_INPUT_HOST
#include <seed-syscall.h>
#endif
int main(void)
{
    int d;
    unsigned int o;
    unsigned int x;
    int a,b,c,e,f,g,h;
    int result;
    const char *empty_format = "";
#ifndef INTEGER_INPUT_HOST
    long mapping;
    char *edge;
    const char *unsupported[6] = {"%u","%i","%ld","%2d","%*d","%s"};
    int i;
#endif
    d = 17; o = 18; x = 19; errno = EDOM;
    if (sscanf(" \t-42:075:0xFf%","%d:%o:%x%%",&d,&o,&x) != 3 || d != -42 || o != 61 || x != 255 || errno != EDOM) return 1;
    if (sscanf("12 34","%d : %d",&d,&a) != 1 || d != 12) return 2;
    if (sscanf(" % 42"," %% %d",&d) != 1 || d != 42) return 3;
    if (sscanf("1 2 3 4 5 6 7 8","%d%d%d%d%d%d%d%d",&a,&b,&c,&d,&e,&f,&g,&h) != 8 || a+b+c+d+e+f+g+h != 36 || a != 1 || h != 8) return 4;
    d = 123; errno = EDOM;
    if (sscanf("","%d",&d) != EOF || d != 123) return 5;
#ifndef INTEGER_INPUT_HOST
    if (errno != EDOM) return 5;
#endif
    if (sscanf(" \t\n","%d",&d) != EOF || d != 123) return 6;
    if (sscanf("+","%d",&d) != 0 || d != 123) return 7;
    if (sscanf("--1","%d",&d) != 0 || d != 123) return 8;
    if (sscanf("\2401","%d",&d) != 0 || d != 123) return 9;
    if (sscanf("",empty_format) != 0) return 10;
    if (sscanf("%","%%") != 0) return 11;
    result = sscanf("4","%d%d",&d,&a);
    if (result != 1 || d != 4) return 12;
    x = 123;
    if (sscanf("g","%x",&x) != 0 || x != 123) return 13;
    if (sscanf("8","%o",&x) != 0 || x != 123) return 14;
#ifndef INTEGER_INPUT_HOST
    for (i = 0; i < 6; i++) {
        d = 123; errno = 0;
        if (sscanf("42",unsupported[i],&d) != EOF || errno != EINVAL || d != 123) return 15;
    }
    d = 123; errno = 0;
    if (sscanf("2147483648","%d",&d) != 0 || errno != ERANGE || d != 123) return 16;
    if (sscanf("-2147483649","%d",&d) != 0 || errno != ERANGE || d != 123) return 17;
    x = 123; errno = 0;
    if (sscanf("100000000","%x",&x) != 0 || errno != ERANGE || x != 123) return 18;
    if (sscanf("40000000000","%o",&x) != 0 || errno != ERANGE || x != 123) return 19;
    x = 123; errno = EDOM;
    if (sscanf("0x","%x",&x) != 0 || x != 123 || errno != EDOM) return 20;
    errno = 0;
    if (atoi("2147483648") != INT_MAX || errno != ERANGE) return 21;
    if (atoi("-2147483649") != INT_MIN || errno != ERANGE) return 22;
    if (atoi("99999999999999999999999999999999999999") != INT_MAX || errno != ERANGE) return 23;
    mapping = __seed_syscall6(9,0,8192,3,34,-1,0);
    if (mapping < 0 || __seed_syscall6(10,mapping+4096,4096,0,0,0,0)) return 24;
    edge = (char *)(mapping+4094); edge[0] = '0'; edge[1] = 0;
    if (sscanf(edge,"%x",&x) != 1 || x != 0 || atoi(edge) != 0) return 25;
    if (__seed_syscall6(11,mapping,8192,0,0,0,0)) return 26;
#endif
    puts("integer input boundaries passed");
    return 0;
}
