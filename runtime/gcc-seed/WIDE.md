# ASCII wide-character primitives

Original Heirloom lex requires pointer-sized integers, wchar_t/wint_t,
C-locale classification/conversion and wcstol. This bounded header layer uses
signed32-bit wchar_t, unsigned32-bit wint_t with all-one WEOF, and LP64 pointer
integers. MB_CUR_MAX and MB_LEN_MAX are one because only ASCII C/POSIX encoding
is available. Requests for other locales already fail honestly.

mbtowc inspects at most the requested bytes and accepts ASCII, including the
null character. wctomb emits one byte for representable characters, including
null. Null source/destination reset requests return zero for the stateless
encoding. Invalid characters fail with EILSEQ without modifying the destination.
A zero byte count fails; this implementation explicitly chooses EILSEQ where
the host oracle leaves errno unchanged. iswprint/iswspace cover only the two
measured C-locale predicates and return false for WEOF and other non-ASCII values.

wcstol implements bases0 and2..36, sign/whitespace/prefix handling, exact end
positions, LONG_MIN/MAX and complete digit consumption after overflow. Overflow
sets ERANGE; invalid bases set EINVAL; successful/no-conversion results preserve
errno. No binary-prefix extension or Unicode digit classification is promised.

wide-check.py tests every byte plus boundary/reset cases and356 independently
constructed numeric cases. Separate host C90 O0/O2 builds compare the shared
contract; the explicit zero-count errno choice is checked only for this runtime.
Wide stream I/O and wide printf formatting are a separate successor stage.
Original binutils adds ASCII `mbstowcs` and C-locale `towlower`; see
[FILE-METADATA.md](FILE-METADATA.md).

## Restartable conversions

`wchar.h` adds `mbstate_t` (eight bytes, always in the initial state for
this stateless encoding) and `mbstate.c` the restartable and length forms
used by gnulib's `quotearg` and `mbswidth`: `mbrtowc` (0 for the null
character, 1 for other ASCII bytes, `(size_t)-2` for a zero count,
`(size_t)-1`/`EILSEQ` above 127; a NULL string resets and returns 0),
`mbrlen`, `wcrtomb` (one byte; values above 127 fail `EILSEQ`; a NULL
destination returns 1), `mbsinit` (true for NULL or the zero state),
`btowc`/`wctob` (ASCII only, `WEOF`/`EOF` otherwise), and in `stdlib.h`
`mblen` (as `mbtowc`) and `wcstombs` (the inverse of `mbstowcs`). Host glibc
in the C locale rejects bytes above 127 the same way, and
`tests/gcc/posix-strings-check.py` compares every case with it.
