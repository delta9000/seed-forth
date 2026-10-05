#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
static int allocated, released, opened, closed, readcalls, fail_alloc;
static long open_result, close_result, read_result;
static int interrupt_open, interrupt_read;
static unsigned char payload[512];
static void *test_malloc(unsigned long n) {
    if (fail_alloc) { errno=ENOMEM; return NULL; }
    allocated++; return malloc(n);
}
static void test_free(void *p) { released++; free(p); }
static long test_syscall(long n,long a,long b,long c,long d,long e,long f) {
    if (n==2) {
        opened++;
        if (b != (0200000 | 02000000)) return -EINVAL;
        if (interrupt_open) { interrupt_open=0; return -EINTR; }
        return open_result;
    }
    if (n==3) { closed++; return close_result; }
    if (n==217) {
        readcalls++;
        if (interrupt_read) { interrupt_read=0; return -EINTR; }
        if (read_result>0 && read_result<=512) memcpy((void *)b,payload,read_result);
        return read_result;
    }
    return -ENOSYS;
}
#define malloc test_malloc
#define free test_free
#define __seed_syscall6 test_syscall
#define opendir test_opendir
#define readdir test_readdir
#define closedir test_closedir
#include "../../runtime/gcc-seed/dirent.c"
#undef malloc
#undef free
#undef __seed_syscall6
static void reset(void) {
    allocated=0;released=0;opened=0;closed=0;readcalls=0;fail_alloc=0;
    open_result=17;close_result=0;read_result=0;interrupt_open=0;interrupt_read=0;
    memset(payload,0,sizeof(payload));errno=71;
}
static int malformed(int amount,int reclen,int fill) {
    DIR *p;int result;
    reset();p=opendir("ignored");read_result=amount;
    memset(payload,fill,sizeof(payload));payload[16]=reclen%256;payload[17]=reclen/256;
    result=readdir(p)==NULL && errno==EIO;
    errno=73;result=result && readdir(p)==NULL && errno==EIO && readcalls==1;
    closedir(p);return result && allocated==1 && released==1 && closed==1;
}
int main(void) {
    DIR *p;struct dirent *entry;int i;
    reset();open_result=-ENOENT;if(opendir("missing") || errno!=ENOENT || allocated || closed)return 1;
    reset();fail_alloc=1;if(opendir("ignored") || errno!=ENOMEM || closed!=1)return 2;
    reset();interrupt_open=1;p=opendir("ignored");if(!p || opened!=2 || errno!=71)return 3;
    interrupt_read=1;if(readdir(p) || errno!=71 || readcalls!=2)return 4;
    errno=72;if(readdir(p) || errno!=72 || readcalls!=2)return 5;
    if(closedir(p) || released!=1 || closed!=1 || errno!=72)return 6;
    reset();p=opendir("ignored");read_result=-EBADF;if(readdir(p) || errno!=EBADF)return 7;
    read_result=24;payload[16]=24;payload[19]='x';entry=readdir(p);
    if(!entry || strcmp(entry->d_name,"x"))return 8;
    close_result=-EINTR;if(closedir(p)!=-1 || errno!=EINTR || closed!=1 || released!=1)return 9;
    for(i=1;i<24;i++)if(!malformed(i,24,'x'))return 10;
    if(!malformed(24,0,'x') || !malformed(24,16,'x') || !malformed(24,25,'x') || !malformed(24,32,'x'))return 11;
    if(!malformed(24,24,'x') || !malformed(24,24,0) || !malformed(32769,24,'x'))return 12;
    reset();p=opendir("ignored");read_result=48;
    payload[16]=24;payload[19]='a';payload[40]=24;payload[43]='b';
    entry=readdir(p);if(!entry || strcmp(entry->d_name,"a"))return 13;
    entry=readdir(p);if(!entry || strcmp(entry->d_name,"b") || readcalls!=1)return 14;
    read_result=0;if(readdir(p) || errno!=71)return 15;
    closedir(p);
    reset();p=opendir("ignored");read_result=512;payload[16]=0;payload[17]=2;
    for(i=19;i<511;i++)payload[i]='z';
    entry=readdir(p);if(!entry || strlen(entry->d_name)!=492)return 16;
    closedir(p);
    errno=0;if(readdir(NULL) || errno!=EBADF)return 17;
    errno=0;if(closedir(NULL)!=-1 || errno!=EBADF)return 18;
    puts("directory fault checks passed");return 0;
}
