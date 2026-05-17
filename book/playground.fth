\ book/playground.fth — gforth shim so Chapter 1's code can run in any
\ standard Forth.
\
\ Usage:
\     gforth book/playground.fth
\
\ Chapter 1 quotes definitions written for seed-forth's hand-encoded VM.
\ Two of those definitions use words that are not in standard Forth:
\
\     nand    -- the seed's only logical primitive
\     [lit]   -- the seed's explicit "push the next decimal literal"
\
\ Standard Forth has `and` and `invert` instead of `nand`, and auto-parses
\ numeric tokens, so `[lit]` is a no-op outside the seed.  Define both as
\ thin compatibility shims; everything else in Chapter 1 — over, nip,
\ rot, 2dup, 2drop, dup, drop, swap, >r, r>, +, - — is portable.

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
." seed-forth playground loaded." cr
." try:  3 4 + 5 *  ." cr
."        .s        \ shows the data stack" cr
."        bye       \ exit" cr
." or paste a definition from book/01-stacks-and-words.md and call it." cr
