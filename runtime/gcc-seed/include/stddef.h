#ifndef SEED_GCC_STDDEF_H
#define SEED_GCC_STDDEF_H
/* Linux AMD64 LP64 declarations for the bounded seed runtime. */
typedef unsigned long size_t;
typedef long ptrdiff_t;
typedef int wchar_t;
#define NULL ((void *)0)
#define offsetof(type, member) ((size_t)&(((type *)0)->member))
#endif
