# Runtime-aware process entry

Original oyacc probes for __progname. The runtime-aware entry initializes this
real symbol before main to the basename within argv[0], or an empty string for
an absent name or trailing slash. Initialization allocates nothing and preserves
errno. The separate 41-byte Forth entry saves argc/argv across initialization,
aligns both outgoing calls, references main directly for archive selection,
and terminates using main's result. The existing 32-byte raw entry remains
independent of the C runtime. Only full-runtime entry promises initialization.

Run tests/gcc/startup-check.py. Forth tests cover five argument-name forms,
argument preservation, null/empty initialization, errno and a raw-entry program
without runtime dependencies. Separate host C callees at O0/O2 verify entry
alignment and exact arguments. Host objects are ABI oracles only. Reports retain
source and artifact hashes. These tests were reconstructed after workspace loss;
acceptance is based on their fresh replay, not the lost previous reports.
