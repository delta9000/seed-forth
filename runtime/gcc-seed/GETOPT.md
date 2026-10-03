# Source-built short options

Original oyacc 6.6 main.c parses `b:dlo:p:rtv` through getopt and reads optarg
and optind. The original project implementation in getopt.c supplies this
measured short-option interface, declared in the bounded unistd.h header.

The four public variables are `char *optarg` and `int optind`, `opterr`,
`optopt`. Parsing begins at optind 1 with diagnostics enabled. Each call returns
one option byte, or minus one when parsing finishes. A cluster such as `-dv`
yields both options; an option followed by a colon in the option string requires
an argument, either attached or in the next argv slot. An empty argument is
preserved. A required argument is consumed even if it begins with a hyphen.

Parsing stops at the first operand, a lone hyphen, or after `--`. It never
permutes argv. Unrecognized options return `?`, record their byte in optopt,
and advance within the cluster. Missing arguments return `?`, or `:` when
the option string begins with a colon. Both errors update optopt. Diagnostics
go to real stderr unless opterr is zero or the option string begins with a
colon. optarg is reset on each call and is nonnull only for a returned argument.

Resetting optind to 1 after completed parsing restarts the same argument vector.
Setting it to zero also resets the private cluster position as a small explicit
extension. The interface is single-threaded and non-reentrant. Optional
arguments, long options and GNU permutation/order extensions are outside this
bounded contract; the options string must use the described short syntax.

`python3 tests/gcc/getopt-check.py` checks fixed expected parse traces, original
oyacc option combinations, attached/separate/empty arguments, error optopt,
leading-colon behavior, both diagnostic paths, non-permutation, terminators and
restart after completion. All 47 argument cases are parsed twice. Independently
built host C90/header/libc versions at O0 and O2 use POSIXLY_CORRECT for the same
ordering contract. Host programs are test oracles only. Production parsing,
formatting, linking and execution use the Forth-built runtime. Each run keeps
its commands' outcome, source/executable/output hashes and report in a fresh
build directory with subprocess timeouts.
