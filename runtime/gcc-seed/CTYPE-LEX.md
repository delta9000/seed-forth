# Measured lexer classification additions

Unchanged Heirloom lex has real isascii references. Flex2.5.11's misc.c and
parse.y require islower/isxdigit; the original Autoconf ANSI-header behavior
probe also requires toupper. These four functions extend the previous seven
ASCII C-locale functions. Each is an ordinary addressable function and evaluates
its argument once. isascii accepts every int and returns true exactly for0..127.
The other ISO functions' supported domain remains EOF or an unsigned-char value.

ctype-lex-check.py computes all11 expected results independently for every
valid argument and compares both the Forth executable and host C90 O0/O2
executables. It also checks function addresses, side effects, and isascii at
INT_MIN, INT_MAX, -2 and256. No locale tables or Unicode classification is added.

Actual Forth-built Flex parse.o adds three more POSIX-class references from
the original parse.y: iscntrl, isgraph and ispunct. The source host-object
census had hidden them behind the host libc's internal classification table.
These functions classify ASCII controls (0 through 31 and 127), graphical
characters (33 through 126), and graphical non-alphanumeric characters,
respectively. The same exhaustive fixture now checks all 14 functions against
independent expected values and host O0/O2. No unselected archive dependency
is used to expand the interface.
