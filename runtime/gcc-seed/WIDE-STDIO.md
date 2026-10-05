# ASCII wide stream and formatting contract

Original Heirloom lex calls getwc and prints wchar_t strings/characters through
%ls and %lc. This stage supplies those exact operations for the fixed ASCII
C/POSIX locale. It does not add general Unicode encodings, stream orientation
APIs, wide pushback, wide output streams, or a full ISO wide-I/O surface.

getwc reads one byte through the real stream. ASCII bytes, including NUL and
DEL, become the same wint_t value. EOF returns WEOF and retains the stream EOF
indicator; an I/O error retains the stream error indicator. A byte above127
returns WEOF, sets EILSEQ and the stream error indicator. The invalid byte is
consumed; callers must not infer a portable stream position after an encoding
error. clearerr and fclose retain their existing real stream behavior.

%ls accepts a wchar_t pointer; %lc accepts an unsigned32-bit wint_t argument.
The formatter handles width, left alignment, dynamic width, byte precision for
strings, snprintf truncation/counting and register/stack variadic arguments.
In this one-byte encoding, byte precision equals character count. It never
reads past the precision bound. A selected unrepresentable character returns
-1 and EILSEQ; string fields are validated before emitting that field. Partial
output after an encoding error is not compared with the host oracle. A null
wide string uses the existing formatter's explicit '(null)' extension.

wide-stdio-check.py compares456 independently calculated format cases and
real-file ASCII/EOF/invalid-byte behavior with independent host C99 O0/O2
builds. A production-only protected-page check proves precision bounds; the
null-pointer extension and unsupported length rejection are also target-only.
The existing stdio production/fault checks and695 independent host-formatting
comparisons at each optimization level pass with this extension. The former
unsupported %ls regression now uses %lls, keeping rejection before va_arg.
