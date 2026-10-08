\ 070-cc-sym.fth — symbol table for the C-subset compiler.
\
\ Ten parallel arrays indexed by symbol id (cell[], 030-cc-io.fth):
\   cc-sym-name-addr [id] : pointer into cc-src-buf where the name begins
\   cc-sym-name-len  [id] : length of the name in bytes
\   cc-sym-kind      [id] : sk-* (global/local/func/struct/enum/typedef)
\   cc-sym-type      [id] : encoded type word from cc-types
\   cc-sym-val       [id] : kind-specific payload
\                            sk-global/sk-func: globals-buf offset / vaddr
\                            sk-local         : slot index (disp -8*(slot+1))
\                            sk-struct        : arena-pointer to descriptor
\                            sk-enum          : integer value
\                            sk-typedef       : encoded type word
\   cc-sym-extra     [id] : one more fact, whose meaning depends on the symbol
\   cc-sym-extra2    [id] : and, for sk-func only, a second one
\ Nothing outside this file names the two extra arrays: each meaning has its
\ own accessor (see "Field accessors" below).
\
\ Scope markers stored in cc-scope-stack (push records the current sym-count;
\ pop restores it, discarding all symbols added since the matching push).
\
\ Depends on 010-lib.fth (constant, variable, create, allot, [lit], if,/then,,
\   0=, 1+, !, @, +!, -!, drop, swap, >r, r@, r>), 020-cc-arena.fth (cc-die,
\   cc-check-cap) and 030-cc-io.fth (cell[], cc-name-find).

[lit] 8192 constant cc-sym-cap

create cc-sym-name-addr  cc-sym-cap [lit] 8 * allot
create cc-sym-name-len   cc-sym-cap [lit] 8 * allot
create cc-sym-kind       cc-sym-cap [lit] 8 * allot
create cc-sym-type       cc-sym-cap [lit] 8 * allot
create cc-sym-val        cc-sym-cap [lit] 8 * allot
create cc-sym-extra      cc-sym-cap [lit] 8 * allot
create cc-sym-extra2     cc-sym-cap [lit] 8 * allot
create cc-sym-desc        cc-sym-cap [lit] 8 * allot
create cc-sym-inner       cc-sym-cap [lit] 8 * allot
\ Qualification provenance is separate from the encoded C type.
create cc-sym-qualified cc-sym-cap [lit] 8 * allot
variable cc-qualified-fields
\ A field's qualifier set (110's cc-qualifier-bit) lives in a list of
\ { next, record, set } nodes; the newest node for a record wins.
: cc-field-qualified ( record -- set )
  cc-qualified-fields @ begin, dup while,
    2dup [lit] 8 + @ = if, nip [lit] 16 + @ exit, then, @
  repeat, 2drop [lit] 0 ;
: cc-field-set-qualified ( set record -- )
  over if,
    [lit] 24 cc-alloc dup >r [lit] 8 + ! r@ [lit] 16 + !
    cc-qualified-fields @ r@ ! r> cc-qualified-fields !
  else, 2drop then, ;
variable cc-sym-count

\ Lookup by name goes through a hash table, as the preprocessor's macros
\ do (040): cc-sym-bucket holds, per cc-name-hash bucket (030), one more
\ than the id of the newest live symbol there (0 for none), and
\ cc-sym-hnext links each symbol to the next older one in its bucket (-1
\ at the end).  cc-scope-pop unlinks what it discards.
create cc-sym-bucket  cc-name-buckets [lit] 8 * allot
create cc-sym-hnext   cc-sym-cap [lit] 8 * allot

\ cc-sym-bucket-of ( id -- addr )  The bucket of symbol id's name.
: cc-sym-bucket-of
  dup cc-sym-name-addr cell[] @ swap cc-sym-name-len cell[] @
  cc-name-hash cc-sym-bucket cell[] ;

\ cc-sym-link ( id -- )  Put symbol id, whose name is filed, at the head
\ of its bucket.  Entries at id or above were discarded without
\ cc-scope-pop (a count stored directly): leave them out of the chain.
: cc-sym-link
  >r  r@ cc-sym-bucket-of
  dup @ 1-
  begin, dup r@ < 0= while, cc-sym-hnext cell[] @ repeat,
  r@ cc-sym-hnext cell[] !
  r> 1+ swap ! ;

\ cc-sym-unlink ( id -- )  Take symbol id, the newest in its bucket, out.
: cc-sym-unlink
  dup cc-sym-hnext cell[] @ 1+  swap cc-sym-bucket-of ! ;

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
\ Add / lookup
\ ===========================================================================

\ cc-sym-add ( name-addr name-len kind type val -- id )
\ Append a new symbol; return its id.  Dies with code 60 if the table
\ already holds cc-sym-cap symbols.
\ Stores fields by parking the new id on the return stack so each store
\ has a fresh copy to compute the slot address.
: cc-sym-add
  cc-sym-count @ 1+ cc-sym-cap [lit] 60 cc-check-cap
  cc-sym-count @                                 ( a u k t v id )
  >r                                              \ R: id
  r@ cc-sym-val       cell[] !                   \ store val
  r@ cc-sym-type      cell[] !                   \ store type
  r@ cc-sym-kind      cell[] !                   \ store kind
  r@ cc-sym-name-len  cell[] !                   \ store name-len
  r@ cc-sym-name-addr cell[] !                   \ store name-addr
  r@ cc-sym-link                                 \ file it under its hash
  \ Extra is reused across scope pops; zero it on every add so callers don't
  \ inherit a stale value (sk-local array-len, sk-func fixup-list, etc.).
  [lit] 0 r@ cc-sym-extra  cell[] !
  [lit] 0 r@ cc-sym-extra2 cell[] !
  [lit] 0 r@ cc-sym-desc cell[] !
  [lit] 0 r@ cc-sym-inner cell[] !
  [lit] 0 r@ cc-sym-qualified cell[] !
  [lit] 1 cc-sym-count +!
  r> ;

\ cc-sym-find ( name-addr name-len -- id-or-neg1 )
\ The walk goes newest first along the name's bucket and returns at the
\ first match, which gives innermost-scope semantics: -1 means "not
\ found", anything >= 0 is the matched id.
\ The default keeps the original single lookup for the bootstrap dialect.
\ A target can separate C's ordinary and tag namespaces without replacing
\ the shared symbol records or their scope lifetime.
: cc-sym-find-default
  cc-nf-u ! cc-nf-a !
  cc-nf-a @ cc-nf-u @ cc-name-hash cc-sym-bucket cell[] @ 1-     ( id )
  begin, dup 0< 0= while,
    dup cc-sym-count @ < over cc-sym-name-len cell[] @ cc-nf-u @ = and if,
      dup cc-sym-name-addr cell[] @ cc-nf-a @ cc-nf-u @ bytes-eq if, exit, then,
    then,
    cc-sym-hnext cell[] @
  repeat, ;
defer cc-sym-find
defer cc-sym-find-tag
' cc-sym-find-default is cc-sym-find
' cc-sym-find-default is cc-sym-find-tag

\ ===========================================================================
\ Field accessors / mutators (all take id on TOS).
\ ===========================================================================

: cc-sym-kind-of       cc-sym-kind      cell[] @ ;       \ ( id -- kind )
: cc-sym-type-of       cc-sym-type      cell[] @ ;       \ ( id -- ty   )
: cc-sym-val-of        cc-sym-val       cell[] @ ;       \ ( id -- val  )

\ The extra cell means one of three things, depending on the symbol; each
\ meaning has its own accessors, all over the same cc-sym-extra array.
\   array length: an array local or global's element count; 0 for a scalar.
: cc-sym-array-len-of     cc-sym-extra     cell[] @ ;  \ ( id -- n    )
: cc-sym-set-array-len    cc-sym-extra     cell[] ! ;  \ ( n id --    )
\   struct descriptor: a struct or struct-pointer local or global's
\   descriptor (060-cc-types.fth).  Its type's base is ty-struct, which is
\   how readers tell this meaning from an array length (so the subset has
\   no arrays of structs).
: cc-sym-struct-desc-of
  cc-target-lp64 @ if, cc-sym-desc else, cc-sym-extra then, cell[] @ ;  \ ( id -- desc )
: cc-sym-set-struct-desc
  cc-target-lp64 @ if, cc-sym-desc else, cc-sym-extra then, cell[] ! ;
: cc-sym-array-inner-of cc-sym-inner cell[] @ ;
: cc-sym-set-array-inner cc-sym-inner cell[] ! ;  \ ( desc id -- )
\   call fixups: for an sk-func not yet defined, the head of the list of
\   `call rel32` sites waiting for its address.  This word gives the cell's
\   address, so the list code can push onto it (0 = no pending calls).
: cc-sym-call-fixups-default cc-sym-extra cell[] ;
defer cc-sym-call-fixups
' cc-sym-call-fixups-default is cc-sym-call-fixups    \ ( id -- cell )
\ The extra2 cell has one meaning, for sk-func only.
\   address fixups: the head of the list of `movabs rdi, imm64` sites that
\   load the function's address before it is defined (a forward-declared
\   function used as a value, e.g. `common_recursion(expression)` before
\   expression's body).  cc-parse-function patches each imm64 to the real
\   vaddr when it reaches the definition.  0 = no pending loads.
: cc-sym-addr-fixups-default cc-sym-extra2 cell[] ;
defer cc-sym-addr-fixups
' cc-sym-addr-fixups-default is cc-sym-addr-fixups
: cc-sym-object-size-of cc-sym-extra2 cell[] @ ;
: cc-sym-set-object-size cc-sym-extra2 cell[] ! ;    \ ( id -- cell )

\ ===========================================================================
\ Scopes
\ ===========================================================================

\ cc-scope-push ( -- )  Mark the current sym-count as a scope boundary.
\ Dies with code 61 past cc-scope-cap nested scopes.
: cc-scope-push
  cc-scope-depth @ 1+ cc-scope-cap [lit] 61 cc-check-cap
  cc-sym-count @
  cc-scope-depth @ cc-scope-stack cell[] !
  [lit] 1 cc-scope-depth +! ;

\ cc-scope-pop ( -- )  Discard any symbols added since the matching push;
\ pops the marker off cc-scope-stack.  A pop with no push to match is a
\ parser bug: die with code 62.
: cc-scope-pop
  cc-scope-depth @ 0= if, [lit] 62 cc-die then,
  [lit] 1 cc-scope-depth -!
  cc-scope-depth @ cc-scope-stack cell[] @       ( mark )
  begin, cc-sym-count @ over > while,
    [lit] 1 cc-sym-count -!  cc-sym-count @ cc-sym-unlink
  repeat, drop ;
