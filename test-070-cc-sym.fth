\ test-070-cc-sym.fth — smoke test for 070-cc-sym.fth.
\ Run via:
\   cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 050-cc-lex.fth 060-cc-types.fth 070-cc-sym.fth \
\       test-070-cc-sym.fth | strip_forth | seed/seed-forth ; echo $?
\
\ AND-accumulator pattern; final `0= die` -> exit 0 on pass.

\ Reset state explicitly (these vars are uninitialized after `variable`).
[lit] 0 cc-sym-count   !
[lit] 0 cc-scope-depth !

\ Lay names into cc-src-buf:
\   offset 0      : "x"
\   offset 1..3   : "foo"
[lit] 120 cc-src-buf            c!  \ x
[lit] 102 cc-src-buf [lit] 1 +  c!  \ f
[lit] 111 cc-src-buf [lit] 2 +  c!  \ o
[lit] 111 cc-src-buf [lit] 3 +  c!  \ o
[lit] 4 cc-src-len !

\ -----------------------------------------------------------------
\ Add "x" as a local with rbp-relative offset -8.
\ -8 in two's complement built via `0 8 -`.
\ -----------------------------------------------------------------
cc-src-buf [lit] 1 sk-local
ty-int [lit] 0 ty-make
[lit] 0 [lit] 8 -
cc-sym-add                                                 ( id-x )
\ Seed the AND accumulator: id-x should be 0.
[lit] 0 =

\ -----------------------------------------------------------------
\ Look up "x"; should return id=0.
\ -----------------------------------------------------------------
cc-src-buf [lit] 1 cc-sym-find [lit] 0 =                   and

\ Check val of id 0 = -8.
[lit] 0 cc-sym-val-of  [lit] 0 [lit] 8 - =                 and

\ Check kind = sk-local.
[lit] 0 cc-sym-kind-of  sk-local =                         and

\ -----------------------------------------------------------------
\ Look up nonexistent "foo"; should return -1.
\ -1 == ( [lit] 0 0= ).
\ -----------------------------------------------------------------
cc-src-buf [lit] 1 + [lit] 3 cc-sym-find
[lit] 0 0= =                                               and

\ -----------------------------------------------------------------
\ Add "foo" as a global at vaddr 0x401234 (= 4198964).
\ -----------------------------------------------------------------
cc-src-buf [lit] 1 + [lit] 3 sk-global
ty-int [lit] 0 ty-make [lit] 4198964
cc-sym-add  drop

\ Look up "foo"; verify val.
cc-src-buf [lit] 1 + [lit] 3 cc-sym-find
cc-sym-val-of  [lit] 4198964 =                             and

\ -----------------------------------------------------------------
\ Scope test:
\   - record current count
\   - push scope
\   - shadow "x" with a new local (val = -16)
\   - lookup "x" -> sees the shadow (most-recent-first)
\   - pop scope
\   - count should be back to recorded value
\   - lookup "x" -> sees the original (val = -8)
\ -----------------------------------------------------------------
cc-sym-count @                                             \ stash baseline
cc-scope-push
cc-src-buf [lit] 1 sk-local
ty-int [lit] 0 ty-make  [lit] 0 [lit] 16 -
cc-sym-add  drop

\ Shadow visible.
cc-src-buf [lit] 1 cc-sym-find cc-sym-val-of
[lit] 0 [lit] 16 - =                                       and

cc-scope-pop

\ Count restored?  Compare against the stashed baseline.
cc-sym-count @ =                                           and

\ Original "x" (val=-8) visible again.
cc-src-buf [lit] 1 cc-sym-find cc-sym-val-of
[lit] 0 [lit] 8 - =                                        and

\ ===========================================================================
\ Final exit
\ ===========================================================================
0= die
