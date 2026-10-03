#ifndef SEED_GCC_ASSERT_H
#define SEED_GCC_ASSERT_H
/* Original seed-forth interface; see LICENSE. C89 assertion contract.
   Reports the expression, file and line to real stderr, then calls abort.
   A function name may be supplied to the failure helper by direct callers. */
void __assert_fail(const char *expression, const char *file,
                   unsigned int line, const char *function);
#endif
/* C permits reinclusion after changing NDEBUG. */
#undef assert
#ifdef NDEBUG
#define assert(expression) ((void)0)
#else
#define assert(expression) ((expression) ? (void)0 : __assert_fail(#expression, __FILE__, __LINE__, 0))
#endif
