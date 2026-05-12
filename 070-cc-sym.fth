\ 070-cc-sym.fth — symbol table for the C-subset compiler.
\
\ Five parallel arrays indexed by symbol id (0..cc-sym-count-1):
\   cc-sym-name-addr [id] : pointer into cc-src-buf where the name begins
\   cc-sym-name-len  [id] : length of the name in bytes
\   cc-sym-kind      [id] : sk-* (global/local/func/struct/enum/typedef)
\   cc-sym-type      [id] : encoded type word from cc-types
\   cc-sym-val       [id] : kind-specific payload
\                            sk-global/sk-func: absolute vaddr
\                            sk-local         : rbp-relative offset (negative)
\                            sk-struct        : arena-pointer to descriptor
\                            sk-enum          : integer value
\                            sk-typedef       : encoded type word
\
\ Scope markers stored in cc-scope-stack (push records the current sym-count;
\ pop restores it, discarding all symbols added since the matching push).
\
\ Depends on 010-lib.fth (constant, variable, create, allot, [lit], if,/then,,
\   begin,/while,/repeat,, +, -, *, =, >=, 0=, !, @, +!, -!, drop, dup, swap)
\   and bytes-eq.

[lit] 4096 constant cc-sym-cap

create cc-sym-name-addr  cc-sym-cap [lit] 8 * allot
create cc-sym-name-len   cc-sym-cap [lit] 8 * allot
create cc-sym-kind       cc-sym-cap [lit] 8 * allot
create cc-sym-type       cc-sym-cap [lit] 8 * allot
create cc-sym-val        cc-sym-cap [lit] 8 * allot
\ Parallel array for "extra info".  For sk-local entries that are arrays this
\ is the array length (in elements); for everything else it is 0.
create cc-sym-extra      cc-sym-cap [lit] 8 * allot
\ Second extra slot.  For sk-func entries this is the head of a fixup list
\ for forward-emitted `movabs rdi, imm64` sites that load the function's
\ absolute vaddr (used when a forward-declared function appears as an
\ rvalue, e.g. `common_recursion(expression)` before expression is defined).
\ The list is walked and each 8-byte imm64 is patched to the function's real
\ vaddr when cc-parse-function processes its definition.  0 means "no
\ pending imm64 fixups".
create cc-sym-extra2     cc-sym-cap [lit] 8 * allot
variable cc-sym-count

[lit] 64 constant cc-scope-cap
create cc-scope-stack  cc-scope-cap [lit] 8 * allot
variable cc-scope-depth

\ Symbol kinds.
[lit] 0 constant sk-global
[lit] 1 constant sk-local
[lit] 2 constant sk-func
[lit] 3 constant sk-struct
[lit] 4 constant sk-enum
[lit] 5 constant sk-typedef

\ ===========================================================================
\ Helpers
\ ===========================================================================

\ sym-slot ( id arr -- addr )  Compute the address of slot id in array arr.
\ Each slot is 8 bytes; arr is the base address returned by `create`.
: sym-slot  swap [lit] 8 * + ;

\ ===========================================================================
\ Add / lookup
\ ===========================================================================

\ cc-sym-add ( name-addr name-len kind type val -- id )
\ Append a new symbol; return its id.
\ Stores fields by parking the new id on the return stack so each store
\ has a fresh copy to compute the slot address.
: cc-sym-add
  cc-sym-count @                                 ( a u k t v id )
  >r                                              \ R: id
  r@ cc-sym-val       sym-slot !                 \ store val
  r@ cc-sym-type      sym-slot !                 \ store type
  r@ cc-sym-kind      sym-slot !                 \ store kind
  r@ cc-sym-name-len  sym-slot !                 \ store name-len
  r@ cc-sym-name-addr sym-slot !                 \ store name-addr
  \ Extra is reused across scope pops; zero it on every add so callers don't
  \ inherit a stale value (sk-local array-len, sk-func fixup-list, etc.).
  [lit] 0 r@ cc-sym-extra  sym-slot !
  [lit] 0 r@ cc-sym-extra2 sym-slot !
  [lit] 1 cc-sym-count +!
  r> ;

\ cc-sym-find walks all entries top-down (most recent first).  We can't bail
\ early (no `exit` primitive in the seed), so we stash the needle in two
\ globals and accumulate the result in cc-sym-find-result.  Once a match is
\ recorded the loop continues but skips further comparisons.
\
\ Result encoding: -1 (= [lit] 0 0=) means "not found"; anything >= 0 is the
\ matched id.  Most-recent-first iteration combined with "skip once found"
\ delivers innermost-scope semantics.
variable cc-sym-find-result
variable cc-sym-find-needle-addr
variable cc-sym-find-needle-len

\ cc-sym-find ( name-addr name-len -- id-or-neg1 )
: cc-sym-find
  cc-sym-find-needle-len  !
  cc-sym-find-needle-addr !
  [lit] 0 0= cc-sym-find-result !                \ -1 = "not found yet"
  cc-sym-count @ [lit] 1 -                       ( i = count-1 )
  begin,
    dup [lit] 0 >=
  while,
    cc-sym-find-result @ [lit] 0 0= = if,        \ still searching?
      dup cc-sym-name-len sym-slot @
      cc-sym-find-needle-len @ = if,             \ same length?
        dup cc-sym-name-addr sym-slot @          ( i entry-addr )
        cc-sym-find-needle-addr @ swap           ( i needle entry )
        cc-sym-find-needle-len @                 ( i needle entry u )
        bytes-eq if,
          dup cc-sym-find-result !               \ record id
        then,
      then,
    then,
    [lit] 1 -                                    \ i--
  repeat,
  drop                                            \ discard final i (=-1)
  cc-sym-find-result @ ;

\ ===========================================================================
\ Field accessors / mutators (all take id on TOS).
\ ===========================================================================

: cc-sym-kind-of       cc-sym-kind      sym-slot @ ;     \ ( id -- kind )
: cc-sym-type-of       cc-sym-type      sym-slot @ ;     \ ( id -- ty   )
: cc-sym-val-of        cc-sym-val       sym-slot @ ;     \ ( id -- val  )

\ Extra-info accessor / setter.  For sk-local array entries, the extra field
\ holds the array length in elements; otherwise it stays 0.
: cc-sym-extra-of      cc-sym-extra     sym-slot @ ;     \ ( id -- extra )
: cc-sym-set-extra     cc-sym-extra     sym-slot ! ;     \ ( extra id -- )

\ Second extra slot — see comment near `create cc-sym-extra2` above.
: cc-sym-extra2-of     cc-sym-extra2    sym-slot @ ;     \ ( id -- extra2 )
: cc-sym-set-extra2    cc-sym-extra2    sym-slot ! ;     \ ( extra2 id -- )

\ ===========================================================================
\ Scopes
\ ===========================================================================

\ cc-scope-push ( -- )  Mark the current sym-count as a scope boundary.
: cc-scope-push
  cc-sym-count @
  cc-scope-stack cc-scope-depth @ [lit] 8 * + !
  [lit] 1 cc-scope-depth +! ;

\ cc-scope-pop ( -- )  Discard any symbols added since the matching push;
\ pops the marker off cc-scope-stack.
: cc-scope-pop
  [lit] 1 cc-scope-depth -!
  cc-scope-stack cc-scope-depth @ [lit] 8 * + @
  cc-sym-count ! ;
