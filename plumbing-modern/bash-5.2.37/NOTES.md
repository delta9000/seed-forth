# GNU bash 5.2.37

Fixed Linux x86-64 / musl 1.1.24 / GCC 4.0.4 configuration, with no configure
or upstream patches. System header/function declarations were checked with
small static compiler probes. The default GNU89 mode works for this package.

- Use musl's allocator, POSIX signals, job control, termios, network functions,
  multibyte types, stat timestamps, and regex. `GETGROUPS_T=gid_t`,
  `RLIMTYPE=rlim_t`, and Linux wait status has `WEXITSTATUS_OFFSET=8`.
- LP64 sizes: int/wchar_t 4, long/pointer/size_t/intmax_t/long long/double 8.
  Bash-specific bits16_t/u_bits16_t/bits32_t/u_bits32_t/bits64_t map to
  short/unsigned short/int/unsigned int/double, as its configure template
  requests when libc does not define them.
- Enable arrays, aliases, brace expansion, extended glob syntax (off by
  default), arithmetic commands/loops, conditional commands, process
  substitution, job control, help and restricted-shell support. ASCII glob
  ranges default on. Readline, history, programmable completion, debugger,
  NLS and loadable builtin support are outside this bootstrap recipe.
- `HAVE_ISBLANK` and the other ctype answers are true. Leaving HAVE_ISBLANK
  undefined causes Bash to define its own macro before musl's ctype function
  declaration, which fails compilation. `HAVE_RESOURCE` is derived by the
  shipped config-bot.h rather than defined twice.
- Version/pathnames/pipesize headers are fixed configured results: release
  5.2, upstream patchlevel.h supplies 37, build number 0, compatibility 52,
  pipe size 4096. Host identity is x86_64-linux-musl; prefix is /usr.
- Use shipped y.tab.c/y.tab.h. Build mkbuiltins, mksyntax and mksignames with
  the same static compiler, then generate builtins.c/builtext.h, builtin C
  files, syntax.c and signames.h. No host parser generator is required.
- mkbuiltins writes each `$PRODUCES` filename in its working directory and
  cannot select another output path. Builtin generation therefore uses
  a small helper Makefile invoked with `make -C builtins`. All expanded
  recipe lines can execute directly without shell metacharacters.
  Generating in the root would collide with shell sources such as eval.c.

See ../README.md for build and smoke-check status.

`-DSHELL` is an upstream build definition required by braces.c and the
shell utility objects. Loadable builtin functions are intentionally disabled
with undefined HAVE_DLOPEN/HAVE_DLSYM/HAVE_DLCLOSE for the static build.

The final link repeats the builtin, shell and glob archives to resolve
cycles (glob_vector calls fnx_fromfs in libsh). This follows the older
plumbing recipe and needs no linker script or shared libraries.
