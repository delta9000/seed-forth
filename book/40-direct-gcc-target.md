# 40. Choosing the target header dialect

Historical headers often choose ANSI declarations when `__STDC__` is defined
and a traditional, less precise interface otherwise. GCC's original
`ansidecl.h`, for example, chooses `void *`, prototypes, and qualifiers on
that branch. The compiler needs an explicit policy for these declarations.

The optional System V mode selects a C90-oriented compatibility profile:
`__STDC__` is 1, `__STDC_HOSTED__` is 0, and `__SEED_FORTH__` identifies this
compiler. It declares the actual AMD64 Linux LP64 target. It does not define
`__GNUC__` or a C99/C11 `__STDC_VERSION__`. This is a bounded bootstrap dialect,
not a claim that every ISO C90 program is accepted. The supported header
branches and executable semantics must be tested together; a macro cannot
supply missing language features or libc functions.

The hook runs after the macro table resets and before the source is scanned.
It adds no source lines, so diagnostics keep their source-relative numbering.
The existing native/TinyCC mode retains its prior macro policy. This target
policy also does not answer configuration probes: those must execute with the
actual compiler and runtime when a build needs them.

The target also enables dynamic `__FILE__` and `__LINE__` entries in the
preprocessor's ordinary macro table. A macro defined in a header and invoked
in a C file reports the invocation's file and physical line. An argument
written on a later line retains its own location during argument expansion.
Nested replacements save and restore that location so one argument cannot
change the line used by the containing replacement. If the outermost macro expansion began with an object-like alias and leaves a
function-like macro name that consumes parentheses from the surrounding file,
the resulting call keeps the outer expansion's invocation location, including
its rescanned arguments. This matches GCC's alias-tail behavior and is tested
separately from directly spelled calls and function-like expansions that
return another macro name. An expansion-depth counter records that outermost
kind; nested aliases inherit it. Function-root calls retain raw argument
locations. Includes keep separate
file cursors; returning from an include resumes the enclosing file's count.
The opened filename is escaped as a C string token, including quotes,
backslashes, and control bytes. With no supplied source name it is `<stdin>`.

This behavior follows the [GCC description of standard predefined
macros](https://gcc.gnu.org/onlinedocs/cpp/Standard-Predefined-Macros.html).
The implementation remains in Forth. File-local cursors count raw newlines
independently of the flattened output line used by compiler diagnostics.
A backwards raw-argument scan resets its file cursor before counting again.
Command-line macro text is processed before the real source's cursor starts.

The first stage deliberately rejects selected `#line` directives and numeric
line markers with error 49. Silently dropping them would make the new location
macros report false provenance. Skipped directives remain inactive. Logical
line-control support is a later required extension for generated parsers;
physical locations already suffice for the original GCC `gengenrtl.c` and
`errors.c` consumers. This is a declared boundary, not a claim of complete
preprocessor conformance.

`tests/gcc/source-location-check.py` compares nested includes, macro calls,
multiline arguments, token pasting, stringification, and escaped paths with
an independent host preprocessor. Its execution test builds static filename
arrays and checks invocation lines using only Forth-produced target code.
The host result is an oracle, never an input to production preprocessing.

```forth file=124-cc-target.fth
\ 124-cc-target.fth -- explicit predefined macros for the SysV C90-oriented mode.
\ The legacy/native route keeps its existing macro policy. No GCC identity
\ or C99/C11 language version is advertised. See book Ch 40 for the boundary.
create cc-target-name-stdc       s, __STDC__
create cc-target-name-hosted     s, __STDC_HOSTED__
create cc-target-name-seed       s, __SEED_FORTH__
create cc-target-name-linux      s, __linux__
create cc-target-name-amd64      s, __x86_64__
create cc-target-name-lp64       s, __LP64__

: cc-target-predefines
  cc-target-sysv @ if,
    cc-prep-location-builtins
    cc-target-name-stdc   [lit] 8  cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-hosted [lit] 15 cc-pp-t0 [lit] 1 cc-macro-add
    cc-target-name-seed   [lit] 14 cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-linux  [lit] 9  cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-amd64  [lit] 10 cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-lp64   [lit] 8  cc-pp-t1 [lit] 1 cc-macro-add
  then, ;
' cc-target-predefines is cc-prep-target-fwd
```
