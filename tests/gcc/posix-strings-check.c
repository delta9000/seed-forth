/* POSIX string, number, environment, locale and line-input fixture:
   Forth runtime versus host glibc in the C locale. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <wchar.h>
#include <inttypes.h>
#include <unistd.h>

#define SIGN(value) ((value) > 0 ? 1 : (value) < 0 ? -1 : 0)

static void comparisons(void)
{
    static const char *const words[] = { "abc", "ABC", "abd", "AB", "", "a\351", "A\311", "[", "{", "_" };
    unsigned int left, right;
    for (left = 0; left < sizeof(words) / sizeof(words[0]); left++)
        for (right = 0; right < sizeof(words) / sizeof(words[0]); right++)
            printf("case %u %u %d %d %d %d\n", left, right, SIGN(strcasecmp(words[left], words[right])),
                   SIGN(strncasecmp(words[left], words[right], 2)), SIGN(strncasecmp(words[left], words[right], 0)),
                   SIGN(strcoll(words[left], words[right])));
}

static void bsd_memory(void)
{
    char buffer[32];
    int values[] = { 0, 1, 2, 3, 8, 12, 0x10000, -1, INT_MIN, 0x40000000 };
    unsigned int slot;
    const char *text = "a/b/c";
    printf("index %s rindex %s none %d\n", index(text, '/'), rindex(text, '/'), index(text, 'z') == NULL);
    printf("index nul %d\n", index(text, '\0') == text + 5);
    strcpy(buffer, "0123456789");
    bcopy(buffer, buffer + 2, 6);
    printf("bcopy up %s\n", buffer);
    bcopy(buffer + 3, buffer, 5);
    printf("bcopy down %s\n", buffer);
    bzero(buffer + 4, 3);
    printf("bzero %d %d %d %c\n", buffer[4], buffer[5], buffer[6], buffer[7]);
    printf("bcmp %d %d %d\n", bcmp("abc", "abd", 3) != 0, bcmp("abc", "abd", 2), bcmp("", "", 0));
    for (slot = 0; slot < sizeof(values) / sizeof(values[0]); slot++)
        printf("ffs %d %d\n", values[slot], ffs(values[slot]));
}

static void copies(void)
{
    char buffer[32], *copy, *end, *saved, *token;
    printf("strnlen %lu %lu %lu\n", (unsigned long)strnlen("hello", 3), (unsigned long)strnlen("hello", 10),
           (unsigned long)strnlen("", 4));
    copy = strndup("hello world", 5);
    printf("strndup [%s]\n", copy);
    free(copy);
    copy = strndup("hi", 10);
    printf("strndup short [%s]\n", copy);
    free(copy);
    end = stpcpy(buffer, "abc");
    end = stpcpy(end, "def");
    printf("stpcpy [%s] %ld\n", buffer, (long)(end - buffer));
    memset(buffer, 'x', sizeof(buffer));
    end = stpncpy(buffer, "ab", 5);
    printf("stpncpy %ld %d %d %d %c\n", (long)(end - buffer), buffer[2], buffer[3], buffer[4], buffer[5]);
    end = stpncpy(buffer, "abcdef", 3);
    printf("stpncpy full %ld %c\n", (long)(end - buffer), buffer[3]);
    strcpy(buffer, ",,a,b;;c,,");
    for (token = strtok(buffer, ",;"); token; token = strtok(NULL, ",;")) printf("strtok [%s]\n", token);
    printf("strtok again %d\n", strtok(NULL, ",") == NULL);
    strcpy(buffer, "x=1&y=2&&z");
    for (token = strtok_r(buffer, "&", &saved); token; token = strtok_r(NULL, "&", &saved))
        printf("strtok_r [%s]\n", token);
    strcpy(buffer, ",,,");
    printf("strtok empty %d\n", strtok(buffer, ",") == NULL);
    printf("strxfrm %lu", (unsigned long)strxfrm(buffer, "collate", sizeof(buffer)));
    printf(" [%s] %lu\n", buffer, (unsigned long)strxfrm(NULL, "abc", 0));
}

static void conversions(void)
{
    static const char *const texts[] = {
        "0", "42", "-42", "  +17xyz", "0x1F", "-0x10", "010", "9223372036854775807",
        "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
        "18446744073709551615", "18446744073709551616", "-1", "zz", "", "0x", "  ", "1e3"
    };
    unsigned int index;
    int bases[] = { 10, 0, 16, 36 };
    unsigned int base;
    char *end;
    long long signed_value;
    unsigned long long unsigned_value;
    intmax_t maximum;
    uintmax_t unsigned_maximum;
    for (index = 0; index < sizeof(texts) / sizeof(texts[0]); index++) {
        for (base = 0; base < 4; base++) {
            errno = 0;
            signed_value = strtoll(texts[index], &end, bases[base]);
            printf("strtoll [%s] %d %lld end %ld errno %d", texts[index], bases[base], signed_value,
                   (long)(end - texts[index]), errno);
            errno = 0;
            unsigned_value = strtoull(texts[index], &end, bases[base]);
            printf(" strtoull %llu end %ld errno %d\n", unsigned_value, (long)(end - texts[index]), errno);
        }
        errno = 0;
        maximum = strtoimax(texts[index], &end, 0);
        printf("strtoimax %jd end %ld errno %d", maximum, (long)(end - texts[index]), errno);
        errno = 0;
        unsigned_maximum = strtoumax(texts[index], &end, 0);
        printf(" strtoumax %ju end %ld errno %d", unsigned_maximum, (long)(end - texts[index]), errno);
        printf(" atoll %lld\n", atoll(texts[index]));
    }
    errno = 0;
    signed_value = strtoll("12", NULL, 1);
    printf("bad base %lld errno %d\n", signed_value, errno);
}

static void arithmetic(void)
{
    int numerators[] = { 7, -7, 7, -7, 0 };
    int denominators[] = { 2, 2, -2, -2, 3 };
    unsigned int index;
    div_t quotient;
    ldiv_t long_quotient;
    lldiv_t long_long_quotient;
    printf("labs %ld %ld %ld\n", labs(-5L), labs(5L), labs(LONG_MIN + 1));
    printf("llabs %lld %lld\n", llabs(-9000000000LL), llabs(LLONG_MAX));
    for (index = 0; index < 5; index++) {
        quotient = div(numerators[index], denominators[index]);
        long_quotient = ldiv((long)numerators[index] * 1000000000L, (long)denominators[index]);
        long_long_quotient = lldiv((long long)numerators[index], (long long)denominators[index] * 3);
        printf("div %d %d -> %d %d ldiv %ld %ld lldiv %lld %lld\n", numerators[index], denominators[index],
               quotient.quot, quotient.rem, long_quotient.quot, long_quotient.rem,
               long_long_quotient.quot, long_long_quotient.rem);
    }
}

static void random_numbers(void)
{
    unsigned int seeds[] = { 1, 42, 0, 12345, 4000000000U };
    unsigned int index;
    int count;
    printf("RAND_MAX %d\n", RAND_MAX);
    for (index = 0; index < 5; index++) {
        srand(seeds[index]);
        printf("srand %u", seeds[index]);
        for (count = 0; count < 8; count++) printf(" %d", rand());
        printf("\n");
        srandom(seeds[index]);
        printf("srandom %u", seeds[index]);
        for (count = 0; count < 4; count++) printf(" %ld", random());
        printf("\n");
    }
    srand(7);
    for (count = 0; count < 100000; count++) rand();
    printf("rand 100001 %d\n", rand());
}

static void classification(void)
{
    int value;
    printf("isblank");
    for (value = -1; value < 256; value++)
        if (isblank(value)) printf(" %d", value);
    printf("\n");
}

static void environment(void)
{
    char *value;
    int count = 0;
    char **entry;
    printf("setenv %d", setenv("SEED_NEW", "one", 0));
    printf(" [%s]\n", getenv("SEED_NEW"));
    printf("setenv keep %d", setenv("SEED_NEW", "two", 0));
    printf(" [%s]\n", getenv("SEED_NEW"));
    printf("setenv replace %d", setenv("SEED_NEW", "a=b", 1));
    printf(" [%s]\n", getenv("SEED_NEW"));
    printf("setenv existing %d", setenv("SEED_POSIX", "changed", 1));
    printf(" [%s]\n", getenv("SEED_POSIX"));
    printf("setenv empty %d", setenv("SEED_EMPTY", "", 1));
    value = getenv("SEED_EMPTY");
    printf(" [%s]\n", value ? value : "(null)");
    errno = 0;
    printf("setenv bad %d", setenv("A=B", "x", 1));
    printf(" errno %d", errno);
    errno = 0;
    printf(" %d", setenv("", "x", 1));
    printf(" errno %d\n", errno);
    printf("unsetenv %d", unsetenv("SEED_NEW"));
    value = getenv("SEED_NEW");
    printf(" [%s]\n", value ? value : "(null)");
    printf("unsetenv missing %d\n", unsetenv("SEED_NEVER"));
    errno = 0;
    printf("unsetenv bad %d", unsetenv("X=Y"));
    printf(" errno %d\n", errno);
    for (entry = environ; *entry; entry++) count++;
    printf("environ entries %d\n", count);
    fflush(stdout);
    if (system("env | grep '^SEED_' | sort") != 0) puts("system failed");
}

static void conventions(void)
{
    struct lconv *numeric = localeconv();
    printf("lconv [%s] [%s] [%s] [%s] [%s] [%s] [%s] [%s] [%s] [%s]\n", numeric->decimal_point,
           numeric->thousands_sep, numeric->grouping, numeric->int_curr_symbol, numeric->currency_symbol,
           numeric->mon_decimal_point, numeric->mon_thousands_sep, numeric->mon_grouping,
           numeric->positive_sign, numeric->negative_sign);
    printf("lconv %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", numeric->int_frac_digits, numeric->frac_digits,
           numeric->p_cs_precedes, numeric->p_sep_by_space, numeric->n_cs_precedes, numeric->n_sep_by_space,
           numeric->p_sign_posn, numeric->n_sign_posn, numeric->int_p_cs_precedes,
           numeric->int_p_sep_by_space, numeric->int_n_cs_precedes, numeric->int_n_sep_by_space,
           numeric->int_p_sign_posn, numeric->int_n_sign_posn);
}

static void wide(void)
{
    mbstate_t state;
    wchar_t character = 0;
    wchar_t text[4];
    char bytes[8];
    size_t result;
    memset(&state, 0, sizeof(state));
    printf("mbsinit %d %d\n", mbsinit(&state), mbsinit(NULL));
    result = mbrtowc(&character, "A", 1, &state);
    printf("mbrtowc %ld %d\n", (long)result, (int)character);
    result = mbrtowc(&character, "", 1, &state);
    printf("mbrtowc nul %ld %d\n", (long)result, (int)character);
    result = mbrtowc(&character, "A", 0, &state);
    printf("mbrtowc zero %ld\n", (long)result);
    errno = 0;
    result = mbrtowc(&character, "\351", 1, &state);
    printf("mbrtowc high %ld errno %d\n", (long)result, errno);
    printf("mbrtowc null %ld\n", (long)mbrtowc(NULL, NULL, 0, &state));
    printf("mbrlen %ld %ld\n", (long)mbrlen("xy", 2, NULL), (long)mbrlen("", 1, NULL));
    result = wcrtomb(bytes, (wchar_t)'z', &state);
    printf("wcrtomb %ld %c\n", (long)result, bytes[0]);
    errno = 0;
    result = wcrtomb(bytes, 0x263a, &state);
    printf("wcrtomb high %ld errno %d\n", (long)result, errno);
    printf("wcrtomb null %ld\n", (long)wcrtomb(NULL, (wchar_t)'q', &state));
    printf("btowc %d %d %d\n", (int)btowc('a'), btowc(200) == WEOF, btowc(EOF) == WEOF);
    printf("wctob %d %d\n", wctob((wint_t)'a'), wctob(0x263a));
    printf("mblen %d %d %d\n", mblen("a", 1), mblen("", 1), mblen(NULL, 0));
    text[0] = (wchar_t)'o';
    text[1] = (wchar_t)'k';
    text[2] = 0;
    printf("wcstombs %ld", (long)wcstombs(bytes, text, sizeof(bytes)));
    printf(" [%s] count %ld\n", bytes, (long)wcstombs(NULL, text, 0));
    text[1] = 0x263a;
    errno = 0;
    result = wcstombs(bytes, text, sizeof(bytes));
    printf("wcstombs high %ld errno %d\n", (long)result, errno);
}

static void lines(void)
{
    FILE *stream;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length;
    int count;
    stream = fopen("lines.txt", "w");
    fputs("first\n\nthird line is longer than the initial buffer of the implementation, "
          "which must grow it by reallocating more than once to hold it all\nlast:no:newline", stream);
    fclose(stream);
    stream = fopen("lines.txt", "r");
    while ((length = getline(&line, &capacity, stream)) != -1)
        printf("getline %ld [%s] fits %d\n", (long)length, line, capacity > (size_t)length);
    printf("eof %d\n", feof(stream));
    rewind(stream);
    count = 0;
    while ((length = getdelim(&line, &capacity, ':', stream)) != -1 && count++ < 3)
        printf("getdelim %ld [%s]\n", (long)length, line);
    fclose(stream);
    free(line);
    line = NULL;
    stream = fopen("empty.txt", "w");
    fclose(stream);
    stream = fopen("empty.txt", "r");
    printf("empty %ld\n", (long)getline(&line, &capacity, stream));
    fclose(stream);
    free(line);
    errno = 0;
    length = getline(NULL, &capacity, stdin);
    printf("null line %ld errno %d\n", (long)length, errno);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    comparisons();
    bsd_memory();
    copies();
    conversions();
    arithmetic();
    random_numbers();
    classification();
    environment();
    conventions();
    wide();
    lines();
    puts("done");
    return 0;
}
