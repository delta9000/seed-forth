/* Independent host oracle; target ELF is produced by seed Forth alone. */
#define _GNU_SOURCE
#include <elf.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#define main review_reference_entry
#include "review-sysv-fixture.c"
#undef main
int review_bad_alignment, review_bad_vector_count, review_bad_preservation;
extern long review_checked_callback(long,long,long,long,long,long,long,long);
extern long review_checked_variadic(long,...);
extern long review_preserve_guard(long (*)(long),long);
long review_host_callback(long a,long b,long c,long d,long e,long f,long g,long h) {
    return a+3*b+5*c+7*d+11*e+13*f+17*g+19*h;
}
long review_host_variadic(long count,...) {
    va_list args; long result;
    if (count!=8) return -1;
    va_start(args,count);
    result = va_arg(args,int)!=-1;
    result |= (va_arg(args,int)!=65535)<<1;
    result |= (va_arg(args,unsigned int)!=4294967295U)<<2;
    for (long i=4;i<=8;i++) result |= (va_arg(args,long)!=i)<<(i+1);
    va_end(args);
    return result;
}
#define CHECK(test) do { if (!(test)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#test); return 1; } } while(0)
int main(int argc,char **argv) {
    struct stat st; Elf64_Ehdr eh; Elf64_Phdr ph; unsigned char *map;
    int fd; size_t mapsz; unsigned char *entry; int32_t rel;
    long (*lookup)(long);
    const unsigned char startup[] = {0x48,0x8b,0x3c,0x24,0x48,0x8d,0x74,0x24,0x08,0x31,0xc0,0xe8};
    CHECK(argc==2);
    fd=open(argv[1],O_RDONLY); CHECK(fd>=0);
    CHECK(fstat(fd,&st)==0);
    CHECK(pread(fd,&eh,sizeof eh,0)==sizeof eh);
    CHECK(eh.e_type==ET_EXEC && eh.e_machine==EM_X86_64 && eh.e_phnum==1);
    CHECK(pread(fd,&ph,sizeof ph,eh.e_phoff)==sizeof ph);
    CHECK(ph.p_type==PT_LOAD && ph.p_offset==0 && ph.p_filesz==(size_t)st.st_size);
    mapsz=(ph.p_memsz+4095)&~(size_t)4095;
    map=mmap((void *)(uintptr_t)ph.p_vaddr,mapsz,PROT_READ|PROT_WRITE|PROT_EXEC,
             MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED_NOREPLACE,-1,0);
    CHECK(map!=MAP_FAILED);
    CHECK(pread(fd,map,st.st_size,0)==st.st_size); close(fd);
    entry=map+(eh.e_entry-ph.p_vaddr);
    CHECK(entry[0]==0xe8 && memcmp(entry+5,startup,sizeof startup)==0);
    memcpy(&rel,entry+17,4);
    lookup=(long (*)(long))(void *)(entry+21+rel);
    CHECK(((long (*)(void))(uintptr_t)lookup(0))()==42);
    CHECK(((long (*)(long,long,long,long,long,long))(uintptr_t)lookup(1))(-1,2,-3,4,-5,6)==review_six(-1,2,-3,4,-5,6));
    CHECK(((long (*)(long,long,long,long,long,long,long))(uintptr_t)lookup(2))(-1,2,-3,4,-5,6,-7)==review_seven(-1,2,-3,4,-5,6,-7));
    CHECK(((review_callback8)(uintptr_t)lookup(3))(-1,2,-3,4,-5,6,-7,8)==review_eight(-1,2,-3,4,-5,6,-7,8));
    CHECK(((long (*)(long,long,long,long,long,long,long,long,long,long,long,long))(uintptr_t)lookup(4))(-1,2,-3,4,-5,6,-7,8,-9,10,-11,12)==review_twelve(-1,2,-3,4,-5,6,-7,8,-9,10,-11,12));
    for (long x=0;x<=13;x++) {
        CHECK(review_preserve_guard((long (*)(long))(uintptr_t)lookup(5),x)==review_recursion(x));
        CHECK(review_preserve_guard((long (*)(long))(uintptr_t)lookup(6),x)==review_operands(x));
        CHECK(review_preserve_guard((long (*)(long))(uintptr_t)lookup(17),x)==review_control(x));
    }
    CHECK(!review_bad_preservation);
    CHECK(((review_narrow_callback)(uintptr_t)lookup(7))(-128,255,-32768,65535,(-2147483647-1),4294967295U,-4294967297L,18446744073709551615UL)==0);
    for (long x=-513;x<=513;x++) {
        CHECK(((signed char (*)(long))(uintptr_t)lookup(8))(x)==(signed char)x);
        CHECK(((unsigned char (*)(long))(uintptr_t)lookup(9))(x)==(unsigned char)x);
        CHECK(((short (*)(long))(uintptr_t)lookup(10))(x*257)==(short)(x*257));
        CHECK(((unsigned short (*)(long))(uintptr_t)lookup(11))(x*257)==(unsigned short)(x*257));
        CHECK(((int (*)(long))(uintptr_t)lookup(12))(x*16777217L)==(int)(x*16777217L));
        CHECK(((unsigned int (*)(long))(uintptr_t)lookup(13))(x*16777217L)==(unsigned int)(x*16777217L));
    }
    CHECK(((long (*)(review_callback8,long,long,long,long,long,long,long,long))(uintptr_t)lookup(14))(review_checked_callback,-1,2,-3,4,-5,6,-7,8)==review_callback(review_checked_callback,-1,2,-3,4,-5,6,-7,8));
    CHECK(((long (*)(review_narrow_callback))(uintptr_t)lookup(15))(review_narrow)==0);
    CHECK(((long (*)(review_variadic))(uintptr_t)lookup(16))(review_checked_variadic)==0);
    CHECK(!review_bad_alignment && !review_bad_vector_count);
    CHECK(munmap(map,mapsz)==0);
    puts("PASS: host/seed SysV interoperability, 0/6/7/8/12 arguments, callbacks, recursion, widths, alignment, AL and callee-save sentinels");
    return 0;
}
