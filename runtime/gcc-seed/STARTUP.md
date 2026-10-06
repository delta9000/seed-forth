# Runtime-aware process entry

Original oyacc probes for __progname. The runtime-aware entry initializes this
real symbol before main to the basename within argv[0], or an empty string for
an absent name or trailing slash. Initialization allocates nothing and preserves
errno. The separate 46-byte Forth entry saves argc/argv across initialization,
aligns both outgoing calls, references main directly for archive selection,
and terminates using main's result. Before calling main it also loads the
SysV third argument, envp = argv + argc + 1 (lea rdx,[rsi+rdi*8+8]), the same
vector the initializer stores in environ, so int main(int, char **, char **)
receives the real environment as with glibc and musl. The existing 32-byte
raw entry remains independent of the C runtime and passes no envp; it is used
only by two-argument syscall proofs. Only full-runtime entry promises
initialization or envp.

Run tests/gcc/startup-check.py. Forth tests cover five argument-name forms,
argument preservation, null/empty initialization, errno, a three-argument main
run under env -i that checks envp == argv + argc + 1 == environ and finds its
variables before the NULL terminator, and a raw-entry program without runtime
dependencies. Separate host C callees at O0/O2 verify entry alignment and
exact arguments, including envp. Host objects are ABI oracles only. Reports retain
source and artifact hashes. These tests were reconstructed after workspace loss;
acceptance is based on their fresh replay, not the lost previous reports.
