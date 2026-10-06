#ifndef SEED_GCC_MATH_H
#define SEED_GCC_MATH_H
/* Original seed-forth binary64 math interface; see ../MATH.md.
 * Functions marked [libc] live in fpclass.c (default runtime archive, like
 * glibc's libc copies); every other function needs an explicit -lm. */

/* Infinity and NaN are runtime expressions: the Forth compiler's constant
 * folder rejects overflow and division by zero, so these are not usable in
 * static initializers. INFINITY and NAN have type double here. */
#define HUGE_VAL (1.0 / 0.0)
#define INFINITY (1.0 / 0.0)
#define NAN (-(0.0 / 0.0))

#define FP_NAN 0
#define FP_INFINITE 1
#define FP_ZERO 2
#define FP_SUBNORMAL 3
#define FP_NORMAL 4

#define MATH_ERRNO 1
#define MATH_ERREXCEPT 2
#define math_errhandling MATH_ERRNO

#define M_E 2.7182818284590452354
#define M_LOG2E 1.4426950408889634074
#define M_LOG10E 0.43429448190325182765
#define M_LN2 0.69314718055994530942
#define M_LN10 2.30258509299404568402
#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_1_PI 0.31830988618379067154
#define M_2_PI 0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2 1.41421356237309504880
#define M_SQRT1_2 0.70710678118654752440

/* Classification helpers [libc]; the macros accept double (and float by
 * promotion) arguments and evaluate them once. */
int __seed_fpclassify(double x);
int __seed_signbit(double x);
int __seed_isunordered(double x, double y);
int __seed_islessgreater(double x, double y);
#define fpclassify(x) __seed_fpclassify(x)
#define isnan(x) (__seed_fpclassify(x) == FP_NAN)
#define isinf(x) (__seed_fpclassify(x) == FP_INFINITE)
#define isfinite(x) (__seed_fpclassify(x) >= FP_ZERO)
#define isnormal(x) (__seed_fpclassify(x) == FP_NORMAL)
#define signbit(x) __seed_signbit(x)
#define isunordered(x, y) __seed_isunordered(x, y)
#define isgreater(x, y) ((x) > (y))
#define isgreaterequal(x, y) ((x) >= (y))
#define isless(x, y) ((x) < (y))
#define islessequal(x, y) ((x) <= (y))
#define islessgreater(x, y) __seed_islessgreater(x, y)

/* Exact bit operations [libc]. */
double frexp(double x, int *exponent);
double ldexp(double x, int exponent);
double scalbn(double x, int exponent);
double modf(double x, double *integral);
double copysign(double x, double y);

/* Exact operations [-lm]. */
double fabs(double x);
double floor(double x);
double ceil(double x);
double trunc(double x);
double round(double x);
double rint(double x);
double nearbyint(double x);
long lround(double x);
long lrint(double x);
long long llround(double x);
long long llrint(double x);
double fmod(double x, double y);
double remainder(double x, double y);
double fmin(double x, double y);
double fmax(double x, double y);
double fdim(double x, double y);
double sqrt(double x);

/* Approximations [-lm]; see MATH.md for measured accuracy. */
double exp(double x);
double exp2(double x);
double expm1(double x);
double log(double x);
double log2(double x);
double log10(double x);
double log1p(double x);
double pow(double x, double y);
double cbrt(double x);
double hypot(double x, double y);
double sin(double x);
double cos(double x);
double tan(double x);
double asin(double x);
double acos(double x);
double atan(double x);
double atan2(double y, double x);
double sinh(double x);
double cosh(double x);
double tanh(double x);
#endif
