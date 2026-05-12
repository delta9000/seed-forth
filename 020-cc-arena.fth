\ 020-cc-arena.fth — bump allocator for variable-size compiler data.
\ Used by the C compiler for: struct descriptors, label fixup overflow lists,
\ string pool overflow — anything that doesn't fit a fixed slot in a parallel
\ array.  Most compiler state lives in fixed-size buffers (parallel arrays
\ declared with `create NAME N allot`); this arena handles the rest.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, [lit], if,/then,,
\ swap, dup, over, drop, +, /, *, >, !, @, syscall6.

\ ----- Storage -----
\ The buffer lives in the dictionary alongside the cc-arena-base header (it's
\ what `create` builds: a header + data area; allot extends the data area).
\ Sized to fit within 000-seed.hex0's mapped segment with room for the compiler
\ dictionary, struct descriptors, labels, and string overflow.
[lit] 32768 constant cc-arena-cap
create cc-arena-base  cc-arena-cap allot
variable cc-arena-ptr
\ Initialize the bump pointer to the base of the buffer.
cc-arena-base cc-arena-ptr !

\ ----- cc-alloc -----
\ cc-alloc ( n -- addr )  Bump n bytes (rounded up to an 8-byte boundary)
\ off the arena and return the start address of the allocation.  On exhaustion
\ the program exits with status 7 (OOM).
\
\ Stack trace:
\   ( n )
\   align up to 8:  (n+7)/8*8
\   ( n' )
\   cc-arena-ptr @ swap over +     ( old-top new-top )
\   dup cc-arena-base cc-arena-cap + >    ( old-top new-top oom? )
\   if, drop drop  exit(7)  then,
\   cc-arena-ptr !                  ( old-top )
: cc-alloc                                       ( n -- addr )
  [lit] 7 + [lit] 8 / [lit] 8 *                  \ align up to 8 bytes
  cc-arena-ptr @ swap over +                     ( old-top new-top )
  dup cc-arena-base cc-arena-cap + > if,
    drop drop
    [lit] 7 die
  then,
  cc-arena-ptr ! ;                               ( -- old-top )
