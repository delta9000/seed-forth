# Application stream block size

BUFSIZ is an integer constant8192, exceeding the standard minimum256. It is
the recommended application I/O block allocation size and the default
stream buffer size ([STDIO-BUFFERING.md](STDIO-BUFFERING.md)). Unchanged
Heirloom lex emits YYLMAX BUFSIZ into generated scanners; those scanners
allocate real token arrays of that bound.

bufsiz-check.py compiles arrays sized by the macro through Forth, writes and
reads the complete8192-byte buffer with the real runtime, checks every byte
independently, and verifies EOF/error indicators. The source has a compile-time
minimum-size check. Larger scanner token limits still require the original
scanner's explicit YYLMAX override; no scanner source adaptation is needed.
