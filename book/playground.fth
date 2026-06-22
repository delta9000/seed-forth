\ book/playground.fth — gforth shim for the chapters of Part I whose
\ Try-it snippets are pure Forth (no seed-only primitives).
\
\ Usage:
\     gforth book/playground.fth                  \ interactive
\     gforth book/playground.fth /tmp/snip.fth    \ batch — paste a chapter snippet
\
\ Coverage at a glance:
\   ✅ Chs 1-4, 6-9, 12      — paste a chapter snippet and run it
\   ⚠️  Chs 5, 10, 11        — chapter Try-it sections route you to a
\                              built ./seed-forth instead (these chapters
\                              exercise `syscall6`, IMMEDIATE-flag
\                              compilation, or branch-slot emission, which
\                              gforth cannot reproduce)
\
\ Do NOT `include 010-lib.fth` directly under this shim — the file uses
\ `syscall6`, `' branch`, `' 0branch` and other seed primitives that
\ gforth doesn't have.  Instead, paste the specific definitions from the
\ chapter you're reading; the chapters quote each definition self-
\ contained.
\
\ What the seed has that gforth doesn't, shimmed below:
\
\     nand    -- the seed's only logical primitive
\     [lit]   -- the seed's explicit "push the next decimal literal"
\
\ Standard Forth has `and` and `invert` instead of `nand`, and auto-parses
\ numeric tokens, so `[lit]` is a no-op outside the seed.  Define both as
\ thin compatibility shims; everything else the early chapters reach for
\ — over, nip, rot, 2dup, 2drop, dup, drop, swap, >r, r>, +, -, c, c@,
\ c! — is already in standard Forth.

\ NB: Forth's ( ... ) comments do NOT nest, so write the stack effect for
\ nand with plain words rather than ~(a&b).
: nand    ( a b -- bitwise-nand )  and invert ;
: [lit]   ( -- )                   ;   \ no-op: standard Forth auto-pushes numbers

\ With those two in place, Chapter 1's six definitions can be pasted
\ verbatim.  We do not redefine over/nip/rot/2dup/2drop/- here, so you
\ can choose: either use gforth's built-ins, or paste the seed
\ definitions from Chapter 1 and watch them shadow the built-ins.  Both
\ behave identically for the inputs Chapter 1 exercises.

\ Banner so the reader knows the shim loaded.
." seed-forth playground loaded — covers Part I snippets for Chs 1-4, 6-9, 12." cr
." Chs 5, 10, 11 need the built ./seed-forth; their Try-it sections say so." cr
." try:  3 4 + 5 *  ." cr
."        .s        \ shows the data stack" cr
."        bye       \ exit" cr
." or paste a definition from any covered chapter and call it." cr
