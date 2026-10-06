/* Original seed-forth implementation; see LICENSE and ENVIRONMENT.md. */
#include <locale.h>
#include <limits.h>

static char seed_point[] = ".";
static char seed_empty[] = "";
static struct lconv seed_conventions;

struct lconv *localeconv(void)
{
    /* Rebuilt on every call: the caller must not modify the record, but a
       stray write cannot persist into the next answer. */
    seed_conventions.decimal_point = seed_point;
    seed_conventions.thousands_sep = seed_empty;
    seed_conventions.grouping = seed_empty;
    seed_conventions.int_curr_symbol = seed_empty;
    seed_conventions.currency_symbol = seed_empty;
    seed_conventions.mon_decimal_point = seed_empty;
    seed_conventions.mon_thousands_sep = seed_empty;
    seed_conventions.mon_grouping = seed_empty;
    seed_conventions.positive_sign = seed_empty;
    seed_conventions.negative_sign = seed_empty;
    seed_conventions.int_frac_digits = CHAR_MAX;
    seed_conventions.frac_digits = CHAR_MAX;
    seed_conventions.p_cs_precedes = CHAR_MAX;
    seed_conventions.p_sep_by_space = CHAR_MAX;
    seed_conventions.n_cs_precedes = CHAR_MAX;
    seed_conventions.n_sep_by_space = CHAR_MAX;
    seed_conventions.p_sign_posn = CHAR_MAX;
    seed_conventions.n_sign_posn = CHAR_MAX;
    seed_conventions.int_p_cs_precedes = CHAR_MAX;
    seed_conventions.int_p_sep_by_space = CHAR_MAX;
    seed_conventions.int_n_cs_precedes = CHAR_MAX;
    seed_conventions.int_n_sep_by_space = CHAR_MAX;
    seed_conventions.int_p_sign_posn = CHAR_MAX;
    seed_conventions.int_n_sign_posn = CHAR_MAX;
    return &seed_conventions;
}
