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
