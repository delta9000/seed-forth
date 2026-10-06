# Runtime environment and C/POSIX locale

The full runtime entry now calls __seed_init_runtime. It preserves the existing
standalone program-name helper and captures the genuine environment vector
immediately after argv's null terminator. Raw entry remains independent.
getenv searches that vector without allocating or modifying strings. It checks
complete name boundaries, returns the first matching entry, preserves empty
values and errno, and rejects empty names or names containing '='. environ is
the actual replaceable process-environment pointer; no host answers are copied.
putenv moves environ to a runtime-owned vector holding the caller's strings;
see [the driver runtime](DRIVER-RUNTIME.md#putenv-and-environ-ownership).

setenv(name, value, overwrite) copies "name=value" into a new allocation and
installs it with putenv, so the caller's strings are not retained; an
existing name is left alone when overwrite is zero. A NULL value is treated
as empty. unsetenv(name) removes every entry with that name (putenv of the
bare name). Both reject a NULL or empty name or one containing '=' with
EINVAL. Replaced setenv strings are never freed, because a caller may still
hold a getenv pointer into them; programs that set the same variable in a
loop grow the heap, as with many C libraries.

Heirloom lex calls setlocale(LC_CTYPE, ""). The implementation genuinely follows
LC_ALL, then the requested category variable, then LANG, ignoring empty values.
With no selection it uses C. Queries preserve state. Explicit C and POSIX are
supported and return canonical C; unavailable names, including C.UTF-8, fail
without a state change. LC_ALL validates every supported category before
succeeding. This is a fixed C/POSIX implementation, not UTF-8 or a locale database.
See [locale selection](https://man7.org/linux/man-pages/man3/setlocale.3.html).

localeconv returns the C locale's struct lconv (glibc's member order): a
decimal point of ".", empty strings for every other text member, and
CHAR_MAX (127, "not available") for every numeric member, including the
international ones. The record is rewritten on every call. The POSIX gate
`tests/gcc/posix-strings-check.py` compares setenv, unsetenv, the
environment seen by a system() child and localeconv with host glibc; see
[STRINGS-POSIX.md](STRINGS-POSIX.md).

The production test injects known environment values through actual process
startup, checks the vector and getenv boundaries, and exercises24 precedence
cases plus UTF-8 rejection. Separate host C90 O0/O2 builds repeat shared cases.
The startup checks still verify argument/name behavior, raw-entry independence
and both call-site alignments, using the new initializer symbol in the ABI
oracle. Each report pins its exact source and executable hashes.
