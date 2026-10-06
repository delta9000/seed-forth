/* Static-storage floating initializers: every sf_ object is computed by the
   Forth compiler at compile time. static-float-check.py renames sf_ to or_
   for the independent host-GCC oracle copy and compares object bytes. */

/* The GNU make 3.82 declarations that first needed this. */
double sf_max_load_average = -1.0;
double sf_default_load_average = -1.0;

/* Literals, signs and integer operands. */
double sf_one = 1.0;
double sf_minus_one = -1.0;
double sf_difference = 0 - 1.0;
float sf_float_negative = -2.5f;
double sf_integer_negative = -1;
double sf_plus = +1.5;
double sf_negative_zero = -0.0;
double sf_positive_zero = 0.0;
double sf_negated_negative_zero = -(-0.0);
float sf_float_negative_zero = -0.0f;
float sf_float_upper_suffix = 1.25F;
double sf_float_widened = 0.1f;
float sf_double_narrowed = 0.1;
double sf_tenth = 0.1;
double sf_third = 1.0 / 3;
double sf_exponent_forms[] = { 1e3, .5, 5., 1.e-2, 2E+2, 0e0 };

/* Subnormal, normal and overflow boundaries. */
double sf_min_subnormal = 4.9406564584124654e-324;
double sf_half_min_subnormal_up = 2.4703282292062328e-324;
double sf_half_min_subnormal_even = 2.4703282292062327e-324;
double sf_max_subnormal = 2.2250738585072009e-308;
double sf_min_normal = 2.2250738585072014e-308;
double sf_max_finite = 1.7976931348623157e308;
double sf_negative_max = -1.7976931348623157e308;
double sf_subnormal_half = 4.9406564584124654e-324 / 2;
double sf_subnormal_three_halves = 4.9406564584124654e-324 * 1.5;
double sf_normal_to_subnormal = 2.2250738585072014e-308 / 3;
double sf_underflow_negative = -1e-300 * 1e-300;
double sf_large_product = 1e154 * 1e154;
float sf_float_min_subnormal = 1.4e-45f;
float sf_float_below_half_subnormal = 7e-46f;
float sf_float_above_half_subnormal = 7.1e-46f;
float sf_float_max = 3.4028234e38f;
float sf_float_min_normal = 1.17549435e-38f;
float sf_float_from_double_subnormal = 1e-40;
float sf_float_round_to_max = 3.40282356e38;

/* A direct binary32 decode avoids double rounding through binary64. */
float sf_float_direct_tie = 1.000000059604644775390625f;
float sf_float_direct_above_tie = 1.0000000596046447753906250000001f;
float sf_float_through_double = 1.0000000596046447753906250000001;

/* Integer to floating conversion of large 64-bit values. */
double sf_two_53_plus_one = 9007199254740993LL;
double sf_two_53_plus_three = 9007199254740995LL;
double sf_unsigned_max = 18446744073709551615UL;
double sf_signed_max = 9223372036854775807L;
double sf_signed_min = -9223372036854775807L - 1;
double sf_unsigned_high = 0x8000000000000401UL;
double sf_unsigned_tie = 0x8000000000000400UL;
float sf_float_two_24_plus_one = 16777217;
float sf_float_unsigned_max = 18446744073709551615UL;
float sf_float_sticky = 0x1000001000000001L;
double sf_unsigned_int = 4294967295U;
double sf_character = 'A';
double sf_casted_integer = (double)3;
float sf_casted_float = (float)16777219;

/* Floating to integer conversion truncates toward zero. */
int sf_int_positive = 2.7;
int sf_int_negative = -2.7;
int sf_int_negative_fraction = -0.5;
unsigned sf_unsigned_negative_fraction = -0.9;
unsigned char sf_byte_top = 255.9;
signed char sf_signed_byte_bottom = -128.9;
short sf_short_bottom = -32768.5;
unsigned short sf_ushort_top = 65535.75f;
long sf_long_large = 9.2e18;
long sf_long_min = -9223372036854775808.0;
unsigned long sf_ulong_large = 1.8e19;
long long sf_llong_float = -1.5e10f;
int sf_int_cast_sum = (int)2.5 + 1;
unsigned long sf_tiny_to_zero = 4.9406564584124654e-324;

/* Arithmetic, conversions and exact cancellation. */
double sf_arithmetic = 1.5 * 2 + 1.0 / 3 - 0.25;
double sf_cancel = 1.0 - 1.0;
double sf_negative_zero_sum = -0.0 + -0.0;
double sf_negative_zero_difference = -0.0 - 0.0;
double sf_mixed_zero_sum = -0.0 + 0.0;
double sf_negative_zero_product = -0.0 * 5;
double sf_negative_zero_quotient = 0.0 / -3;
double sf_add_tie_even = 1.0 + 1.1102230246251565e-16;
double sf_add_above_tie = 1.0 + 1.1102230246251568e-16;
double sf_far_apart = 1e308 + 4.9406564584124654e-324;
double sf_far_apart_difference = 4.9406564584124654e-324 - 1e308;
double sf_integer_quotient = 3 / 2.0;
float sf_float_sum = 0.1f + 0.2f;
double sf_double_sum = 0.1 + 0.2;
double sf_float_promoted = 0.1f + 0.2;
float sf_float_integer = 1 + 0.5f;
float sf_float_product = 16777215.0f * 3;
float sf_float_quotient = 1.0f / 3;
double sf_nested_casts = (double)(float)0.1;
double sf_cast_chain = (float)(1.0 / 3) * 3;
double sf_conditional = 1.0 ? 2 : 3.5;
double sf_conditional_false = 0.0 ? 2 : 3.5;
double sf_parenthesized = -(1.25 + -(2.5));

/* Comparisons, truth and logical operators produce int. */
int sf_less = 1.5 < 2;
int sf_greater = 1.5 > 2;
int sf_less_equal = 2.0 <= 2;
int sf_greater_equal = -0.0 >= 0.0;
int sf_zero_equal = -0.0 == 0.0;
int sf_not_equal = 0.1f != 0.1;
int sf_not_zero = !0.0;
int sf_not_negative_zero = !-0.0;
int sf_not_tiny = !4.9406564584124654e-324;
int sf_and = 0.5 && 2;
int sf_or = 0.0 || -0.0;
int sf_conditional_int = 0.25 ? 7 : 9;
int sf_array_bound[(int)2.5];

/* Arrays, records and nested records. */
double sf_table[] = { 1.0, -0.5, 3 };
float sf_float_table[4] = { 1.5f, -0.0f, 2 };
double sf_matrix[2][3] = { { 1, 2.5, -3 }, { 0.125, -0.0 } };
struct sf_mixed { int a; double b; float c; char d; double e[2]; };
struct sf_mixed sf_record = { 1, 2.5, -0.75f, 66, { 1e-310, -1e300 } };
struct sf_mixed sf_records[] = { { 1, 0.5 }, { 2, -1.0, 3.0f, 4.9 } };
struct sf_outer { float x; struct sf_mixed in; double y; };
struct sf_outer sf_outer = { 0.5f, { -7, 1.0 / 7, 0.1 }, 1e-5 };
struct sf_bits { int low : 3; unsigned mid : 5; double value; };
struct sf_bits sf_bits = { 2.9, 17.5, -2 };
static double sf_internal = 6.25;
double *sf_internal_address(void) { return &sf_internal; }

/* Block-scope objects with static storage duration. */
void *sf_block_double(unsigned long *size)
{ static double value = 1.5; *size = sizeof value; return &value; }
void *sf_block_float(unsigned long *size)
{ static float value = -0.1f; *size = sizeof value; return &value; }
void *sf_block_array(unsigned long *size)
{ static double value[] = { 1, -2.5, 1e-310, 3 / 2.0 }; *size = sizeof value; return value; }
void *sf_block_record(unsigned long *size)
{ static struct sf_mixed value = { 3, 0.5, 2, 'x', { -0.0 } }; *size = sizeof value; return &value; }
void *sf_block_integer(unsigned long *size)
{ static long value = -3.99; *size = sizeof value; return &value; }

/* Runtime binary32 literals use the same exact decoder. */
void *sf_block_runtime(unsigned long *size)
{
  static float value[6];
  value[0] = 1.0000000596046447753906250000001f;
  value[1] = -2.5f;
  value[2] = 0.1f + 0.2f;
  value[3] = 1e-45F;
  value[4] = 3.4028234e38f;
  value[5] = sizeof(1.0f) + sizeof 1.0;
  *size = sizeof value;
  return value;
}
