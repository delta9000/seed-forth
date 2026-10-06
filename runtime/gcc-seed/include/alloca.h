#ifndef SEED_GCC_ALLOCA_H
#define SEED_GCC_ALLOCA_H
/* Original seed-forth interface; see LICENSE and ../STRINGS-POSIX.md.
   The Forth C compiler has no stack-allocating builtin, so the runtime
   defines no alloca. This declaration only gives callers the correct
   pointer result type (an undeclared call would truncate it to int). The
   program must link a portable C alloca, such as libiberty's or gnulib's
   alloca.c compiled with C_ALLOCA; see ../STRINGS-POSIX.md. */
#include <stddef.h>
void *alloca(size_t size);
#endif
