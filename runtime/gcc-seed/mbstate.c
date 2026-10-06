/* Original seed-forth implementation; see LICENSE and WIDE.md.
   Restartable and length conversions for the stateless ASCII C locale. */
#include <stdlib.h>
#include <wchar.h>
#include <stdio.h>
#include <errno.h>

size_t mbrtowc(wchar_t *wide, const char *bytes, size_t count, mbstate_t *state)
{
    unsigned char value;
    (void)state;
    if (bytes == NULL) return 0;
    if (count == 0) return (size_t)-2;
    value = (unsigned char)*bytes;
    if (value > 127) {
        errno = EILSEQ;
        return (size_t)-1;
    }
    if (wide) *wide = value;
    return value != 0;
}

size_t mbrlen(const char *bytes, size_t count, mbstate_t *state)
{
    return mbrtowc(NULL, bytes, count, state);
}

size_t wcrtomb(char *bytes, wchar_t wide, mbstate_t *state)
{
    (void)state;
    /* A NULL destination resets the (always initial) state: one byte. */
    if (bytes == NULL) return 1;
    if ((unsigned int)wide > 127) {
        errno = EILSEQ;
        return (size_t)-1;
    }
    *bytes = (char)wide;
    return 1;
}

int mbsinit(const mbstate_t *state)
{
    return state == NULL || state->__seed_count == 0;
}

wint_t btowc(int byte)
{
    return byte >= 0 && byte <= 127 ? (wint_t)byte : WEOF;
}

int wctob(wint_t wide)
{
    return wide <= 127 ? (int)wide : EOF;
}

int mblen(const char *bytes, size_t count)
{
    return mbtowc(NULL, bytes, count);
}

size_t wcstombs(char *bytes, const wchar_t *wide, size_t count)
{
    size_t done = 0;
    wchar_t value;
    while (bytes == NULL || done < count) {
        value = wide[done];
        if ((unsigned int)value > 127) {
            errno = EILSEQ;
            return (size_t)-1;
        }
        if (bytes) bytes[done] = (char)value;
        if (value == 0) break;
        done++;
    }
    return done;
}
