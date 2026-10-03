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
    cc-target-name-stdc   [lit] 8  cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-hosted [lit] 15 cc-pp-t0 [lit] 1 cc-macro-add
    cc-target-name-seed   [lit] 14 cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-linux  [lit] 9  cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-amd64  [lit] 10 cc-pp-t1 [lit] 1 cc-macro-add
    cc-target-name-lp64   [lit] 8  cc-pp-t1 [lit] 1 cc-macro-add
  then, ;
' cc-target-predefines is cc-prep-target-fwd
```
