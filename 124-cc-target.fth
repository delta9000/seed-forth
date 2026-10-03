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
