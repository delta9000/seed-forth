# Chapter 28 — Expressions, Part 2: Primary, Unary, Assignment

```text
Missing capability: expressions cannot address storage, handle postfix forms, or assign.
New pattern: lvalue metadata delays loads until context decides whether a value is read or written.
Artifact after this chapter: primary, unary, postfix, ternary, assignment, and lvalue-aware codegen.
Proof link: Stage-A pointer, array, struct, call, increment, and assignment expressions share one value model.
```

Ch 27's cascade assumes that something below it leaves an operand
in `rdi` and something above it decides what to do with the result.
This chapter writes both ends, and both run into the same problem:
the parser can't always know what an expression is *for* when it
parses it.  `p[i]` on the right of `=` is a load; on the left it is
the address of a store.  `head->next->prev` is a chain of loads until
the last link, which might be written.

The answer is to emit the address, record what kind of value `rdi`
holds, and let the consumer decide.  §1 sets up that record.  §§2–5
are the floor below the cascade: field lookup, array indexing,
`cc-parse-primary` with its postfix chain, and the unary operators.
§§6–8 are the tail above it: the ternary, assignment, and the
top-level `cc-parse-expr`.  §9 traces one condition through every
layer.  Function-call codegen lives in Ch 31 (reached through
`cc-parse-call-tramp`), and the statements that call `cc-parse-expr`
are Ch 30's.

---

## 1. Lvalue tracking: five globals, three kinds

```forth chunk=expr-lvalue
\ ===========================================================================
\ Lvalue tracking for assignment, address-of, and dereference.
\ ===========================================================================
\ Two pieces of state:
\
\   cc-last-lvalue-kind  : 0 = not an lvalue
\                          1 = local variable     (slot in cc-last-ident-slot)
\                          2 = pending dereference (rdi holds an ADDRESS that
\                              has not yet been loaded; consumer must
\                              materialize it via cc-emit-materialize before
\                              using the value, or use it directly to store
\                              into [rdi] for assignment).
\   cc-last-ident-slot   : slot index of a kind=1 local (irrelevant for other
\                          kinds, kept for the assignment helper).
\
\ cc-parse-primary clears these (kind=0, slot=-1) by default and writes them
\ when it parses a simple local IDENT.  cc-parse-unary may write kind=2 when
\ parsing `*expr`.  Any binary-op fold that fires (cc-parse-mul/add/rel/eq)
\ materializes operands first and then sets kind back to 0 (the result of
\ a binary op is not an lvalue).  cc-parse-assign reads BOTH globals AT MOST
\ ONCE — right after parsing the LHS — and snapshots them on the data stack
\ before recursing into the RHS (which would otherwise overwrite them).

variable cc-last-ident-slot
variable cc-last-lvalue-kind                       \ 0 / 1 / 2

\ cc-last-struct-desc holds the struct descriptor pointer of the most
\ recently loaded struct lvalue or struct-pointer rvalue.  Consumed by the
\ '.' / '->' postfix handler in cc-parse-primary; cleared by every other
\ lvalue-mark word so it never leaks across unrelated expressions.
variable cc-last-struct-desc

\ cc-last-deref-is-byte: -1 iff the current kind=2 deref-lvalue addresses a
\ single byte (e.g. `s[i]` where s is char*), 0 otherwise.  Read by
\ cc-emit-materialize and the kind=2 assignment path so they emit byte-width
\ load/store instead of qword.  Cleared by every other mark-* word.
variable cc-last-deref-is-byte

\ cc-last-expr-type: encoded C type (ty-base + ptr-depth) of the value most
\ recently produced by cc-parse-primary plus its postfix chain.  Used by the
\ postfix '[' handler so `obj->charstar[i]` knows to apply byte stride and
\ byte deref instead of qword.  0 means "type unknown" — postfix '[' falls
\ back to the legacy qword path in that case.  Reset to 0 by every cc-mark-*
\ word so it never leaks across unrelated expressions.
variable cc-last-expr-type

: cc-mark-not-lvalue
  [lit] 0 0= cc-last-ident-slot !                  \ slot := -1
  [lit] 0    cc-last-lvalue-kind !                 \ kind := 0
  [lit] 0    cc-last-struct-desc !
  [lit] 0    cc-last-deref-is-byte !
  [lit] 0    cc-last-expr-type ! ;

\ cc-mark-local-lvalue ( slot -- )  Record kind=1 with the given slot.
: cc-mark-local-lvalue
  cc-last-ident-slot !
  [lit] 1 cc-last-lvalue-kind !
  [lit] 0 cc-last-struct-desc !
  [lit] 0 cc-last-deref-is-byte !
  [lit] 0 cc-last-expr-type ! ;

\ cc-mark-deref-lvalue ( -- )  Record kind=2 (rdi holds a pending-deref addr).
: cc-mark-deref-lvalue
  [lit] 0 0= cc-last-ident-slot !
  [lit] 2    cc-last-lvalue-kind !
  [lit] 0    cc-last-struct-desc !
  [lit] 0    cc-last-deref-is-byte !
  [lit] 0    cc-last-expr-type ! ;

\ cc-mark-deref-byte-lvalue ( -- )  Same as cc-mark-deref-lvalue but flags the
\ deref as byte-width.  Used for `s[i]` on char* (and char[N]).
: cc-mark-deref-byte-lvalue
  cc-mark-deref-lvalue
  [lit] 0 0= cc-last-deref-is-byte ! ;

\ cc-emit-materialize ( -- )  If kind==2, load [rdi] into rdi and clear state.
\ A no-op for kind 0 or 1 (their rdi already holds a value).
: cc-emit-materialize
  cc-last-lvalue-kind @ [lit] 2 = if,
    cc-last-deref-is-byte @ if,
      cc-emit-load-byte-via-rdi
    else,
      cc-emit-load-via-rdi
    then,
    cc-mark-not-lvalue
  then, ;

```

Five globals form the lvalue state.

- `cc-last-lvalue-kind` is the discriminator: 0 means *not* an
  lvalue (a temp), 1 means a local-variable lvalue (whose slot
  is in `cc-last-ident-slot`), 2 means a pending dereference
  (`rdi` holds an *address* that needs loading).
- `cc-last-ident-slot` carries the slot for kind=1.
- `cc-last-struct-desc` carries the struct descriptor (Ch 24 §1)
  for any struct-typed value just loaded.
- `cc-last-deref-is-byte` flags whether a kind=2 deref is
  byte-width (for `char*[i]`) or qword (for everything else).
- `cc-last-expr-type` is the encoded type word of the value just
  produced, so postfix `[]` can choose byte or qword stride.

Every binary-op fold in Ch 27 calls `cc-emit-materialize` before
consuming an operand.  For kind=0 (a temp) and kind=1 (a local
already loaded into `rdi`), it's a no-op.  For kind=2 (a pending
deref), it emits the actual `mov rdi, [rdi]` (or `movzx rdi,
byte [rdi]` if byte-width) and clears the state.

The `cc-mark-*` words are mutually exclusive setters.  Each clears
the other slots and sets only the ones its kind needs.  Adding a new
lvalue kind means remembering to clear it in every `cc-mark-*`, but
with five words that is easy to check.  A binary op ends with
`cc-mark-not-lvalue` because its result is a temp.

## 2. Struct-field lookup

```forth chunk=expr-struct-field
\ ===========================================================================
\ Struct-field name lookup.
\ ===========================================================================
\ Walks the descriptor's field array; returns the matched field's byte offset.
\ Aborts with status 92 if no field matches (compile-time error: field not
\ found).  Uses globals to stash the needle so the loop body has predictable
\ stack effect.

variable cc-ff-needle-addr
variable cc-ff-needle-len
variable cc-ff-desc
variable cc-ff-result                                \ -1 = not-yet-found, else offset
variable cc-ff-result-desc                           \ matched field's pointee desc (0 if not a struct ptr)
variable cc-ff-result-type                           \ matched field's encoded type (ty-base + ptr-depth)
variable cc-ff-found                                 \ flag: -1 if found

\ cc-find-field ( name-addr name-len desc -- offset )
: cc-find-field
  cc-ff-desc           !
  cc-ff-needle-len     !
  cc-ff-needle-addr    !
  [lit] 0 cc-ff-found  !                            \ found? = 0
  [lit] 0 cc-ff-result !
  [lit] 0 cc-ff-result-desc !
  [lit] 0 cc-ff-result-type !
  \ Loop i = 0..field-count-1.
  cc-ff-desc @ cc-sd-field-count                    ( count )
  [lit] 0                                            ( count i )
  begin,
    over over >                                      ( count i count>i? )
  while,
    cc-ff-found @ 0= if,
      \ Compare names at field i.
      cc-ff-desc @ over cc-sd-field-rec              ( count i rec )
      dup cc-sf-name-len cc-ff-needle-len @ = if,
        dup cc-sf-name-addr                         ( count i rec entry-addr )
        cc-ff-needle-addr @ swap                    ( count i rec needle entry )
        cc-ff-needle-len  @                         ( count i rec needle entry u )
        bytes-eq if,
          dup cc-sf-offset cc-ff-result !
          dup cc-sf-desc cc-ff-result-desc !
          dup cc-sf-type cc-ff-result-type !
          [lit] 0 0= cc-ff-found !
        then,
      then,
      drop                                          ( count i )
    then,
    [lit] 1 +                                       ( count i+1 )
  repeat,
  drop drop                                          ( -- )
  cc-ff-found @ 0= if,
    [lit] 92 die
  then,
  cc-ff-result @ ;

```

`cc-find-field` walks the descriptor's field records (Ch 24 §1)
looking for one whose name matches the needle, returns its
offset, and stashes the matched field's pointee descriptor and
type in `cc-ff-result-{desc,type}` for the postfix handler.

The walk uses the same "no `exit`" idiom as
`cc-check-keyword` (Ch 23) and `cc-sym-find` (Ch 24): record the
hit in a flag variable, keep iterating but skip work after the
hit.

A missing field is fatal (status 92).  By this point
`cc-last-struct-desc` has confirmed that the value *is* a struct,
so a missing field is an error in the program being compiled, not
a parsing ambiguity.

## 3. Array indexing helper

```forth chunk=expr-array-index
\ ===========================================================================
\ cc-parse-array-index — handle `arr[expr]`.
\ ===========================================================================
\ Called from cc-parse-primary AFTER finding an IDENT that resolves to a
\ local-array symbol, local pointer, global array, or global pointer, AND
\ after peeking the next token and seeing '['.  At entry the symbol id is
\ on TOS and the '[' token has been read into tok-* (so the next
\ cc-next-token-keep will advance past it).
\
\ The base is loaded into rdi by one of four paths:
\   inline local array  (sk-local,  extra>0)  lea  rdi, [rbp+disp]      \ &arr[0]
\   local pointer       (sk-local,  extra=0)  mov  rdi, [rbp+disp]      \ value of p
\   inline global array (sk-global, extra>0)  movabs rdi, &globals[off]
\   global pointer      (sk-global, extra=0)  movabs rdi, &globals[off]; mov rdi, [rdi]
\
\ Then `arr[i]` becomes:
\     push rdi
\     <eval i>                                 ; rdi = i
\     (shl  rdi, 3)                            ; iff element size is 8
\     pop  rcx
\     add  rdi, rcx                            ; rdi = element address
\
\ Element size is 1 for raw char data (so `argv[i]` and `int arr[N]` work
\ together); 8 for everything else (pointers, ints, struct-pointer slots).
\ The char-step decision is based on the symbol's type after one indexing
\ step yields a single char:
\   inline array of T:  step=1 iff base==ty-char AND ptr-depth==0
\   pointer-to-T:       step=1 iff base==ty-char AND ptr-depth==1
\
\ After this the caller marks lvalue-kind=2 (pending deref) so the consumer
\ either does the load (rvalue use, via cc-emit-materialize) or treats rdi
\ as the destination address (lvalue use in assignment, kind=2 path).
: cc-parse-array-index                            ( id -- )
  \ Accept sk-local or sk-global.
  dup cc-sym-kind-of sk-local =
  over cc-sym-kind-of sk-global = or 0= if,
    drop
    [lit] 80 die
  then,

  \ Emit base address into rdi.
  dup cc-sym-kind-of sk-global = if,
    dup cc-sym-val-of cc-emit-global-ref          \ rdi = &globals[off]
    dup cc-sym-extra-of [lit] 0 = if,
      cc-emit-load-via-rdi                        \ pointer global: load slot value
    then,
  else,
    dup cc-sym-extra-of [lit] 0 > if,
      dup cc-sym-val-of cc-emit-lea-rdi-local     \ inline array: address of slot
    else,
      dup cc-sym-val-of cc-emit-load-local        \ pointer local: load slot value
    then,
  then,

  \ Element type of arr[i] plus a byte-step flag, both stashed on the rstack
  \ so they survive the index-expression parse.  An inline array (extra>0)
  \ keeps the symbol's type — the subscript consumes the array dimension, not
  \ a pointer level; a pointer (extra==0) drops one pointer level.  The step
  \ is one byte iff the element is a plain char, so a chained `[j]` (e.g.
  \ char* v[]; v[i][j]) reads cc-last-expr-type and picks byte stride/deref.
  dup cc-sym-extra-of [lit] 0 > if,
    cc-sym-type-of                                ( elem-ty )         \ array: keep type
  else,
    cc-sym-type-of                                ( ty )
    dup ty-base swap ty-ptr [lit] 1 - ty-make     ( elem-ty )         \ ptr: depth-1
  then,
  dup >r                                          ( elem-ty ; R: elem-ty )
  dup ty-base ty-char = swap ty-ptr [lit] 0 = and ( char-step? ; R: elem-ty )
  >r                                              ( ; R: elem-ty char-step? )

  cc-emit-push-rdi

  \ Parse the index expression.  cc-parse-expr-tramp ends with a materialize
  \ so rdi holds an actual integer.
  cc-parse-expr-tramp

  r@ 0= if,
    cc-emit-shl-rdi-3                             \ rdi *= 8 (non-char step)
  then,

  \ Pop the base, add to scaled index.
  cc-emit-pop-rcx
  cc-emit-add-rdi-rcx

  \ Expect ']'.
  cc-next-token-keep
  tok-kind @ tk-punct <> tok-num @ [lit] 93 <> or if,
    [lit] 82 die
  then,

  \ rdi now holds the element address; mark as pending-deref lvalue so the
  \ consumer either loads or stores depending on context.  char-step element
  \ accesses (flag still on rstack) mark byte-width so the eventual load/store
  \ is 1 byte, not 8.  The mark zeroes cc-last-expr-type, so republish the
  \ element type afterwards for any chained postfix `[j]`.
  r> if,
    cc-mark-deref-byte-lvalue
  else,
    cc-mark-deref-lvalue
  then,
  r> cc-last-expr-type ! ;

```

`cc-parse-array-index` is the `[` handler that `cc-parse-primary`
calls once it has read `IDENT [`.  It loads the base address, parses
the index expression, scales the index by the element size (1 for
char data, 8 for everything else), adds, and marks the result as a
pending-deref lvalue.

The four base-loading paths (local array, local pointer, global
array, global pointer) cover every way a name can head a `[]`.
`argv[i]` (a `char**`) and `int arr[N]` use qword stride, while
`s[i]` on a `char*` loads a single byte, as `is_digit(s[i])` needs.
The choice comes from the *element type* of `arr[i]`.  An inline array keeps the symbol's own type (the
subscript spends the array dimension, not a pointer level); a
pointer drops one pointer level.  The step is one byte exactly when
the element type is a plain `char`.  The helper keeps the element
type on the return stack and writes it back to `cc-last-expr-type`
after the mark, which clears it.  That is what makes a chained
subscript work: in `char* v[]; v[i][j]`, the second `[` sees that
`v[i]` is a `char*` and steps by one byte.

## 4. `cc-parse-primary`: the leaf and its postfix chain

`cc-parse-primary` is the longest word in the file, a single
definition that first dispatches on the token kind and then loops
over postfix operators.  The chunk below lists its pieces in order;
each piece is a slice of one deeply nested `if, … else, … then,`
ladder, so the `else,` that opens a piece belongs to the `if,` that
ended the piece before.

```forth chunk=expr-primary
<<expr-primary-literals>>
<<expr-primary-ident>>
<<expr-primary-fn-rvalue>>
<<expr-primary-global>>
<<expr-primary-local>>
<<expr-primary-paren>>
<<expr-primary-postfix>>
<<expr-primary-postfix-index>>
<<expr-primary-postfix-field>>
```

### Literals

```forth chunk=expr-primary-literals
\ ===========================================================================
\ cc-parse-primary
\ ===========================================================================

\ Abort helper — exits with status 30+code (so we can tell parse errors apart
\ from runtime exits and the existing cc-decl error codes 2..6).
\ Inlined where used because we have no `exit` primitive.

: cc-parse-primary
  cc-mark-not-lvalue                              \ default: not an lvalue
  cc-next-token-keep
  tok-kind @ tk-num = if,
    tok-num @ cc-emit-mov-rdi-int                 \ widen to imm64 if out of imm32 range
  else,
    tok-kind @ tk-chr = if,
      \ Character literal — value is in tok-num just like a number.
      tok-num @ cc-emit-mov-rdi-imm32
    else,
    tok-kind @ tk-str = if,
      \ String literal.  We emit the bytes inline in the code stream and
      \ jump over them, then load their absolute vaddr into rdi:
      \     jmp +N            E9 <rel32>          (5 bytes; rel32 patched)
      \     <decoded string bytes + NUL>
      \   skip:
      \     movabs rdi, vaddr 48 BF <imm64>       (10 bytes)
      cc-emit-jmp-rel32-placeholder               ( fixup-off )
      \ Capture the vaddr where the string bytes will start (= current emit
      \ position, NOT the rel32 fixup, so we keep it on the stack under the
      \ fixup).
      cc-base-vaddr cc-out-pos @ +                ( fixup-off str-vaddr )
      swap                                        ( str-vaddr fixup-off )
      \ Copy decoded string bytes (with NUL terminator).
      tok-str-addr @ tok-str-len @ cc-emit-string-bytes
      \ Patch the jmp's rel32 to land here (right after the string bytes).
      cc-patch-rel32-to-here                      ( str-vaddr )
      \ Emit the movabs rdi, str-vaddr.
      cc-emit-movabs-rdi-imm64
```

The word starts by marking "not an lvalue".  The "abort helper"
comment describes the `die` codes (30 and up) used inline below;
there is no helper word.

A number goes through `cc-emit-mov-rdi-int` (Ch 26), which widens
to a 64-bit `movabs` when the value doesn't fit a sign-extended
`imm32`, so `0x80000000` keeps its value instead of loading
negative.  A character literal is always in `0..255` and takes the
plain `imm32` path.

A string literal is emitted *inline in the code segment*: a `jmp`
over the bytes, the bytes and their NUL, then a `movabs` of their
address into `rdi`.  There is no separate string pool, at the cost
of 5 bytes of `jmp` per literal.

### Identifiers, calls, and subscripts

```forth chunk=expr-primary-ident
    else,
      tok-kind @ tk-ident = if,
      \ Identifier reference.  Could be a local variable, or a function call
      \ if the next token is '('.  Look up the name first.
      tok-str-addr @ tok-str-len @ cc-sym-find
      \ -1 means "not found" (cc-sym-find result encoding: -1 == [lit] 0 0=).
      dup [lit] 0 < if,
        drop
        [lit] 30 die
      then,
      \ Enum constants resolve to their integer value (mov rdi, imm32).
      \ Handle this BEFORE the suffix peek so RED, GREEN etc. work in any
      \ expression context — they're never callable / indexable / assignable.
      dup cc-sym-kind-of sk-enum = if,
        cc-sym-val-of cc-emit-mov-rdi-imm32
        cc-mark-not-lvalue
      else,
      \ Peek the next token without consuming it.  Possible suffixes:
      \   '(' -> function call
      \   '[' -> array index
      \ Otherwise it's a plain variable reference (with array decay for
      \ array-typed locals).
      cc-next-token-keep
      tok-kind @ tk-punct = tok-num @ [lit] 40 = and if,
        \ Function call.  The id (still on TOS) must refer either to an
        \ sk-func (direct call) or to an sk-local function pointer
        \ (indirect call).
        dup cc-sym-kind-of sk-func = if,
          \ direct call — accepted
        else,
          \ Indirect call?  Must be sk-local with ty-base==ty-func.
          dup cc-sym-kind-of sk-local =
          over cc-sym-type-of ty-base ty-func = and 0= if,
            drop
            [lit] 34 die
          then,
        then,
        \ Hand the id off to cc-parse-call (in 110-cc-decl.fth via trampoline).
        \ It will consume the '(' (already peeked), parse args, emit the
        \ call, and leave the return value in rdi.  The result is not an
        \ lvalue.
        cc-parse-call-tramp
        cc-mark-not-lvalue
      else,
        tok-kind @ tk-punct = tok-num @ [lit] 91 = and if,
          \ Array index.  '[' has been read into tok-*; cc-parse-array-
          \ index consumes through ']'.  The id is on TOS.
          cc-parse-array-index
```

An identifier is looked up first; an unknown name dies with status
30.  An enum constant becomes `mov rdi, imm32` before anything else
is considered, since it can't be called, indexed, or assigned.

For any other name the parser peeks one token.  A `(` means a call.
The name must be a function or a local function pointer (the
`ty-func` type from Ch 29 §4), otherwise status 34.  The symbol id
goes to `cc-parse-call` in `110-cc-decl.fth` through the trampoline
from Ch 27 §4; Ch 31 covers the call itself.  A `[` hands the id to
`cc-parse-array-index` (§3).

### A function name as a value

```forth chunk=expr-primary-fn-rvalue
        else,
          \ Variable reference.  Put back the peeked token.
          cc-putback-token
          \ Function name as rvalue — `op = square;`.  Load the function's
          \ absolute vaddr into rdi via movabs.  Result is not an lvalue.
          \ When val == 0 the function is still a forward prototype; emit a
          \ 10-byte movabs placeholder and thread the imm64 patch-offset onto
          \ cc-sym-extra2 so cc-parse-function can patch it once the real
          \ vaddr is known.  Without this, M2-Planet code like
          \ `common_recursion(expression)` (where `expression` is forward-
          \ declared) loads 0 into rdi and crashes at the indirect call.
          dup cc-sym-kind-of sk-func = if,
            dup cc-sym-val-of [lit] 0 = if,
              cc-emit-movabs-rdi-imm64-placeholder    ( id patch-off )
              swap cc-sym-extra2 sym-slot             ( patch-off extra2-cell )
              cc-add-fixup-to-list
            else,
              cc-sym-val-of cc-emit-movabs-rdi-imm64
            then,
            cc-mark-not-lvalue
```

Anything else is a plain reference, so the peeked token goes back.
A function name used as a value (`op = square;`) loads the
function's address with `movabs`.  If the function has only been
declared so far, its address isn't known.  The parser then emits a
10-byte `movabs rdi, imm64` with a zero immediate and adds the
patch site to the list threaded through `cc-sym-extra2` (Ch 26 §1).
Ch 31's `cc-parse-function` patches the list when the definition
arrives.  M2-Planet needs this: it passes forward-declared functions
such as `expression` as arguments.

### Globals

```forth chunk=expr-primary-global
          else,
          \ File-scope global.  Emit movabs rdi, <vaddr-placeholder>
          \ with a deferred fixup.  Scalar globals are deref-pending lvalues
          \ (kind=2); array globals decay to their address (kind=0).
          \
          \ cc-sym-extra's meaning depends on the type:
          \   ty-struct base -> struct descriptor pointer (NOT an array length).
          \   any other      -> array element count (>0 for arrays, 0 otherwise).
          dup cc-sym-kind-of sk-global = if,
            dup cc-sym-type-of ty-base ty-struct = if,
              \ Struct or struct-pointer global.  Treat like a scalar (deref-
              \ pending lvalue) so assignment works; the descriptor is recorded
              \ below for any postfix '.' / '->'.
              dup cc-sym-val-of cc-emit-global-ref
              cc-mark-deref-lvalue
              cc-sym-extra-of cc-last-struct-desc !
            else,
              dup cc-sym-extra-of [lit] 0 > if,
                \ Global array: rdi := &globals[slot]; not an lvalue.
                cc-sym-val-of cc-emit-global-ref
                cc-mark-not-lvalue
              else,
                \ Global scalar: rdi := &globals[slot]; mark deref-pending so
                \ consumer either loads (rvalue) or stores via that address
                \ (assignment kind=2 path).  Record the scalar's type (across
                \ the mark, which clears it) so a following unary '*' knows
                \ whether this is a char* (1-byte deref) or a wider pointer.
                dup cc-sym-type-of >r
                cc-sym-val-of cc-emit-global-ref
                cc-mark-deref-lvalue
                r> cc-last-expr-type !
              then,
            then,
```

A global's address comes from `cc-emit-global-ref`, and what the
parser does next depends on the type.  A struct or struct-pointer
global becomes a pending deref and records its descriptor for a
following `.` or `->`.  A global array decays to its address and is
not an lvalue.  A scalar global becomes a pending deref (kind=2),
and its type is saved across the mark so that a following unary `*`
knows whether it points to `char`.

### Locals

```forth chunk=expr-primary-local
          else,
          dup cc-sym-kind-of sk-local <> if,
            drop
            [lit] 31 die
          then,
          \ Dispatch on the local's type — struct vs struct-pointer vs
          \ array vs scalar.
          dup cc-sym-type-of ty-base ty-struct = if,
            \ Struct-typed local.
            dup cc-sym-type-of ty-ptr [lit] 0 = if,
              \ struct T x;  Emit lea on the first-element slot so rdi holds
              \ the address of the struct.  Then record the descriptor for any
              \ following '.field'.  This is NOT a normal lvalue (you can't
              \ assign to a whole struct); '.field' will mark deref-lvalue.
              dup cc-sym-extra-of                    \ descriptor pointer
              swap cc-sym-val-of                     \ slot of field 0 (deepest)
              cc-emit-lea-rdi-local
              cc-mark-not-lvalue
              cc-last-struct-desc !
            else,
              \ struct T* p;  Load the pointer value; treat as an lvalue local
              \ (kind=1) so plain `p = q;` still works, AND record descriptor
              \ for '->field'.
              dup cc-sym-extra-of                    \ descriptor pointer
              swap cc-sym-val-of                     \ slot index
              dup cc-mark-local-lvalue
              cc-emit-load-local
              cc-last-struct-desc !
            then,
          else,
            \ If this local is an array, decay to &arr[0] — emit lea, not
            \ load.  The result is a pointer value (not an lvalue).
            dup cc-sym-extra-of [lit] 0 > if,
              cc-sym-val-of                           \ slot of arr[0]
              cc-emit-lea-rdi-local
              cc-mark-not-lvalue
            else,
              \ Plain scalar local.  Save its type across the mark (which
              \ clears cc-last-expr-type) so a following unary '*' can tell a
              \ char* (1-byte deref) from a wider pointer.
              dup cc-sym-type-of >r
              cc-sym-val-of                           \ slot index
              dup cc-mark-local-lvalue                \ kind=1, remember slot
              cc-emit-load-local
              r> cc-last-expr-type !
            then,
          then,
          then,                                       \ end of sk-global if/else
          then,                                       \ end of sk-func-name-rvalue if/else
        then,
      then,
      then,                                           \ end of sk-enum if/else
```

Any other symbol kind dies with status 31.  A local dispatches on
its type:

- `struct T x;` emits `lea` of field 0's slot, so `rdi` holds the
  struct's address.  It is not an lvalue (a whole struct can't be
  assigned), but its descriptor is recorded for `.field`.
- `struct T* p;` loads the pointer and marks a kind=1 local, so
  `p = q;` still works, and records the descriptor for `->field`.
- An array decays to `&arr[0]` with `lea`, not an lvalue.
- A plain scalar is loaded and marked kind=1 with its slot.  Its
  type is saved across the mark, as for globals.

The run of `then,` at the end closes the ladder back to the enum
test.

### Parentheses

```forth chunk=expr-primary-paren
    else,
      tok-kind @ tk-punct = tok-num @ [lit] 40 = and if,
        \ '(' expr ')' — the parenthesised expr is not an lvalue (cc-parse-
        \ primary inside the recursive call will set/clear cc-last-ident-slot;
        \ we re-clear it here so e.g. `(x) = 1` doesn't get treated as lvalue).
        cc-parse-expr-tramp
        cc-mark-not-lvalue
        cc-next-token-keep
        tok-kind @ tk-punct <> tok-num @ [lit] 41 <> or if,
          [lit] 32 die
        then,
      else,
        [lit] 33 die
      then,
    then,
    then,
    then,
  then,
```

`( expr )` recurses through the trampoline and then clears the
lvalue state, so `(x) = 1` is rejected.  A missing `)` is status 32,
and a token that can't start an expression at all is status 33.

### The postfix loop

```forth chunk=expr-primary-postfix
  \ Handle zero or more postfix '.field' / '->field' applied to whatever
  \ value cc-parse-primary just produced.  Both '.' / '->' ops require
  \ cc-last-struct-desc to be non-zero (set by the variable-reference branch
  \ for struct locals or struct-pointer locals).  Also handles postfix '++' / '--'
  \ to the same loop — they apply to simple local lvalues (kind=1 in
  \ cc-last-ident-slot) and bump the slot in place while leaving the OLD value
  \ in rdi.
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = if,
      tok-num @ [lit] 46 =
      tok-num @ pt-arrow         = or
      tok-num @ pt-plus-plus     = or
      tok-num @ pt-minus-minus   = or
      tok-num @ [lit] 91 =       or            \ '[' postfix subscript
    else,
      [lit] 0
    then,
  while,
    tok-num @                                       ( op-code )
    dup pt-plus-plus = over pt-minus-minus = or if,
      \ Postfix '++' / '--' on a simple local.  cc-parse-primary already
      \ loaded the old value into rdi and recorded the slot in
      \ cc-last-ident-slot (kind=1).  Bump the slot in place; rdi keeps the
      \ old value.  Result is not an lvalue.
      cc-last-lvalue-kind @ [lit] 1 = 0= if,
        drop
        [lit] 53 die
      then,
      pt-plus-plus = if,
        cc-last-ident-slot @ cc-emit-inc-mem-local
      else,
        cc-last-ident-slot @ cc-emit-dec-mem-local
      then,
      cc-mark-not-lvalue
```

After the leaf, the loop consumes `.`, `->`, `++`, `--`, and `[`
until it reads some other token, which it puts back.  Postfix `++`
and `--` accept only a kind=1 local (anything else is status 53).
They bump the slot in memory with `inc`/`dec` and leave the old
value, already loaded, in `rdi`.

```forth chunk=expr-primary-postfix-index
    else,
    dup [lit] 91 = if,
      \ Postfix '[' INDEX ']' applied to whatever value cc-parse-primary just
      \ produced (typically after a chain of '.' / '->').  Materialize so rdi
      \ holds the actual pointer value (not a deref-pending address), push it,
      \ parse the index, scale, add, mark deref.  Stride is 1 (byte) iff the
      \ subscripted value is a char pointer (e.g. `head->s[i]` where s is
      \ char*) — M2-Planet's tokenizer compares `global_token->s[0]` against
      \ digit/letter sets, which only works when each byte is loaded
      \ individually.  Everything else (int*, struct*, untyped) uses qword
      \ stride and qword deref.
      drop                                           ( -- )
      \ Snapshot the just-finished expression's type before materialize zeros
      \ it out, then dispatch.
      cc-last-expr-type @ >r                         \ R: pre-subscript ty
      cc-emit-materialize
      cc-emit-push-rdi
      cc-parse-expr-tramp
      r@ ty-base ty-char =
      r@ ty-ptr [lit] 1 = and if,
        \ char* subscript: rdi already holds the byte offset (no shift).
      else,
        cc-emit-shl-rdi-3
      then,
      cc-emit-pop-rcx
      cc-emit-add-rdi-rcx
      cc-next-token-keep
      tok-kind @ tk-punct <> tok-num @ [lit] 93 <> or if,
        [lit] 82 die
      then,
      \ Mark deref: byte-width iff we just subscripted a char*.  The
      \ post-step expression type drops one level of indirection — record
      \ it so chained `[i][j]` (char**) and following postfix ops can see
      \ the right type.
      r@ ty-base ty-char =
      r@ ty-ptr [lit] 1 = and if,
        cc-mark-deref-byte-lvalue
      else,
        cc-mark-deref-lvalue
      then,
      r@ ty-ptr [lit] 0 > if,
        r@ ty-base r@ ty-ptr [lit] 1 - ty-make cc-last-expr-type !
      then,
      r> drop
```

A postfix `[` applies to whatever value the chain has produced so
far, as in `head->s[i]`.  Unlike §3's helper it starts from a value
rather than a symbol, so it takes the element type from
`cc-last-expr-type`, snapshotted before `cc-emit-materialize` clears
it.  A `char*` gets byte stride and a byte-width deref; everything
else gets qword.  If the value was a pointer, the pointee type is
written back so that `[i][j]` on a `char**` works.

```forth chunk=expr-primary-postfix-field
    else,
      cc-last-struct-desc @ [lit] 0 = if,
        [lit] 90 die
      then,
      \ Save the struct descriptor across cc-emit-materialize — materialize
      \ ends in cc-mark-not-lvalue which clears cc-last-struct-desc.  For
      \ kind=1 (local) materialize is a no-op so the clear didn't matter; for
      \ kind=2 (struct-ptr global / deref) it does.  Restore right after.
      cc-last-struct-desc @ >r                      \ R: desc
      \ If '->' the pointer value should already be in rdi (kind=1 after load).
      \ Materialize anyway (no-op for kind=1) — defensive; clears kind to 0.
      \ For '.' rdi holds the struct base address (kind=0); no materialize.
      dup pt-arrow = if,
        cc-emit-materialize
      then,
      drop                                          ( -- )
      r> cc-last-struct-desc !                      \ restore desc
      cc-next-token-keep
      tok-kind @ tk-ident <> if,
        [lit] 91 die
      then,
      tok-str-addr @ tok-str-len @ cc-last-struct-desc @
      cc-find-field                                 ( offset )
      cc-emit-add-rdi-imm32
      cc-mark-deref-lvalue
      \ Propagate the field's pointee descriptor so chained '->' / '.' (e.g.
      \ `head->next->prev`) can resolve subsequent field lookups.  Stays 0
      \ when the field isn't a struct pointer.
      cc-ff-result-desc @ cc-last-struct-desc !
      \ Record the field's type so a following postfix '[' can detect
      \ char-pointer subscripts (e.g. `head->s[0]`) and emit byte stride/load
      \ instead of qword.  cc-mark-deref-lvalue cleared this slot above, so
      \ set it after the mark.
      cc-ff-result-type @ cc-last-expr-type !
    then,
    then,
  repeat,
  cc-putback-token ;

```

`.` and `->` need a descriptor in `cc-last-struct-desc`, or the
compile dies with status 90.  The descriptor is saved across
`cc-emit-materialize`, which clears it.  For `->`, materialize turns
a pending-deref pointer into its value; for `.`, `rdi` already holds
the struct's address.  The field name goes to `cc-find-field` (§2),
the offset is added to `rdi`, and the result is a pending deref.
Finally the field's pointee descriptor and type are recorded, so
`head->next->prev` and `head->s[0]` resolve their next step.

## 5. `cc-parse-unary`: prefix operators

```forth chunk=expr-unary
\ ===========================================================================
\ cc-parse-unary: ('&' unary | '*' unary | primary)
\ ===========================================================================
\ Disambiguation: at unary position, '*' is dereference and '&' is address-of;
\ at binary position (handled by cc-parse-mul) '*' means multiply.
\
\ The address-of operand is restricted to a simple local IDENT; it emits
\ `lea rdi, [rbp - 8*(slot+1)]`.  More complex address expressions such as
\ `&*p` or `&arr[i]` are not implemented.
\
\ For dereference, the operand is parsed as a (recursive) unary expression so
\ `**p` works.  We materialize the operand (turning any pending deref into a
\ loaded value) so rdi holds the *address* that the outer '*' should target,
\ then mark cc-last-lvalue-kind=2 — leaving the load for the consumer.

variable cc-parse-unary-vec                       \ xt of cc-parse-unary

: cc-parse-unary-tramp
  cc-parse-unary-vec @ execute ;

```

`cc-parse-unary` reaches itself (for `**p`, say) through a vec and
trampoline like those in Ch 27 §4, wired at the end of this chunk.

`sizeof` comes first.  It accepts either a type or an identifier and
evaluates at compile time:

```forth chunk=expr-unary
\ cc-parse-sizeof — `sizeof '(' (type-spec | EXPR) ')'`.
\ Called with the `sizeof` keyword token already consumed.
\
\ Type-spec forms:
\   sizeof(int)            sizeof(char)        sizeof(void)
\   sizeof(int*)           sizeof(int**)       ...
\   sizeof(struct TAG)
\   sizeof(typedef-name)
\
\ EXPR forms supported here are bare identifiers:
\   sizeof(scalar-local)   -> sizeof(scalar-type)
\   sizeof(array-local)    -> N * 8                            (no decay)
\   sizeof(struct-local)   -> descriptor->total-size
\
\ Always emits `mov rdi, imm32` with the size in bytes; result is not an lvalue.
\
\ Implementation note: this routine stages the computed byte count in
\ cc-sizeof-bytes so the deeply-nested if/else dispatch needn't preserve
\ a value on the data stack across the recursive '*'-counting / lookup paths.
\ Pointer modifiers '*+' are accepted on every type-spec branch (struct,
\ typedef, primitive).
variable cc-sizeof-bytes

\ cc-sizeof-count-stars-add ( -- )  Read zero-or-more '*' tokens.  Each star
\ overrides the result with 8 (a pointer is always 8 bytes regardless of
\ pointee).  The first non-'*' token is left current for the caller.
: cc-sizeof-count-stars-add
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [lit] 42 = and
  while,
    [lit] 8 cc-sizeof-bytes !
  repeat, ;

```

```forth chunk=expr-unary
: cc-parse-sizeof
  \ Expect '('.  We inline the check because cc-expect-punct-c lives in
  \ 110-cc-decl.fth (loaded AFTER 100-cc-expr.fth) and isn't visible yet.
  cc-next-token-keep
  tok-kind @ tk-punct <> tok-num @ [lit] 40 <> or if,
    [lit] 76 die
  then,
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-struct = if,
      \ struct TAG — look up descriptor.
      cc-next-token-keep
      tok-kind @ tk-ident <> if,
        [lit] 77 die
      then,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup [lit] 0 < if,
        [lit] 78 die
      then,
      dup cc-sym-kind-of sk-struct <> if,
        [lit] 79 die
      then,
      cc-sym-val-of cc-sd-total-size cc-sizeof-bytes !
      cc-sizeof-count-stars-add
    else,
      tok-kw-id @ kw-int = if,
        [lit] 8 cc-sizeof-bytes !
      else,
        tok-kw-id @ kw-char = if,
          [lit] 1 cc-sizeof-bytes !
        else,
          tok-kw-id @ kw-void = if,
            [lit] 0 cc-sizeof-bytes !
          else,
            [lit] 74 die
          then,
        then,
      then,
      cc-sizeof-count-stars-add
    then,
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup [lit] 0 < if,
        [lit] 73 die
      then,
      dup cc-sym-kind-of sk-typedef = if,
        \ Typedef name -> compute base size, then any extra stars override to 8.
        cc-sym-val-of ty-size cc-sizeof-bytes !
        cc-sizeof-count-stars-add
      else,
        dup cc-sym-kind-of sk-local = if,
          \ Local — branch on struct vs array vs scalar.
          dup cc-sym-type-of ty-base ty-struct = if,
            dup cc-sym-type-of ty-ptr [lit] 0 = if,
              \ struct T x; — total-size of the descriptor.
              cc-sym-extra-of cc-sd-total-size cc-sizeof-bytes !
            else,
              \ struct T* p; — 8 bytes.
              drop [lit] 8 cc-sizeof-bytes !
            then,
          else,
            dup cc-sym-extra-of [lit] 0 > if,
              \ Array — N * 8 (this subset assumes int elements here).
              cc-sym-extra-of [lit] 8 * cc-sizeof-bytes !
            else,
              \ Scalar.
              cc-sym-type-of ty-size cc-sizeof-bytes !
            then,
          then,
          cc-next-token-keep                       \ should land on ')'
        else,
          drop
          [lit] 73 die
        then,
      then,
    else,
      [lit] 73 die
    then,
  then,
  \ Current token must be ')'.
  tok-kind @ tk-punct <> tok-num @ [lit] 41 <> or if,
    [lit] 75 die
  then,
  cc-sizeof-bytes @ cc-emit-mov-rdi-imm32
  cc-mark-not-lvalue ;

```

`cc-parse-sizeof` stores the answer in `cc-sizeof-bytes` rather
than on the stack, so the nested dispatch doesn't have to thread it
through every branch.  A `*` after any type spec overrides the
answer to 8, since a pointer is 8 bytes whatever it points to.
Every path ends in `mov rdi, imm32`.

```forth chunk=expr-unary
\ cc-parse-prefix-inc-dec ( delta -- )  delta = 1 (for ++) else dec.
\ Called with the '++' / '--' punct ALREADY consumed.  Operand must be a
\ simple IDENT referring to a local (other lvalue forms — pointer deref,
\ struct member, array element — are not implemented).  Emits:
\   inc/dec qword [rbp+disp]    ; bump slot in-place
\   mov rdi, [rbp+disp]         ; load new value
: cc-parse-prefix-inc-dec                         ( delta -- )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    drop
    [lit] 50 die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup [lit] 0 < if,
    drop drop
    [lit] 51 die
  then,
  dup cc-sym-kind-of sk-local <> if,
    drop drop
    [lit] 52 die
  then,
  cc-sym-val-of                                   ( delta slot )
  swap                                            ( slot delta )
  [lit] 1 = if,
    dup cc-emit-inc-mem-local
  else,
    dup cc-emit-dec-mem-local
  then,
  cc-emit-load-local                              \ rdi := updated value
  cc-mark-not-lvalue ;

```

Prefix `++` and `--` accept only a local identifier (statuses
50–52).  They bump the slot in memory, then load the new value into
`rdi`.

```forth chunk=expr-unary
: cc-parse-unary
  cc-next-token-keep
  tok-kind @ tk-kw = tok-kw-id @ kw-sizeof = and if,
    \ sizeof(TYPE).  The `sizeof` keyword is the current token; we just
    \ leave it as "consumed" (no putback) and dispatch into cc-parse-sizeof.
    cc-parse-sizeof
  else,
    tok-kind @ tk-punct = tok-num @ [lit] 38 = and if,
    \ '&' = address-of.  Operand must be a simple local IDENT.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 70 die
    then,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup [lit] 0 < if,
      drop
      [lit] 71 die
    then,
    dup cc-sym-kind-of sk-local <> if,
      drop
      [lit] 72 die
    then,
    cc-sym-val-of                                 \ slot
    cc-emit-lea-rdi-local
    cc-mark-not-lvalue                            \ &x is a value, not an lvalue
  else,
    tok-kind @ tk-punct = tok-num @ [lit] 42 = and if,
      \ '*' = dereference.  A char* operand (ty-char, ptr-depth 1) derefs to a
      \ single byte; int*, T**, etc. deref to a qword.  The operand's type sits
      \ in cc-last-expr-type when it came from a scalar variable (recorded in
      \ cc-parse-primary); snapshot it before cc-emit-materialize clears it, so
      \ `*p = c` on a char* emits a 1-byte store instead of clobbering 8 bytes.
      cc-parse-unary-tramp
      cc-last-expr-type @ >r                       \ R: operand type (0 if untracked)
      cc-emit-materialize                          \ operand is now a value (an address)
      r@ ty-base ty-char = r@ ty-ptr [lit] 1 = and if,
        cc-mark-deref-byte-lvalue                  \ *char-ptr -> 1-byte deref
      else,
        cc-mark-deref-lvalue                       \ rdi holds an addr; defer the load
      then,
      r> dup ty-ptr [lit] 0 > if,                  \ record pointee type for chained ops
        dup ty-base swap ty-ptr [lit] 1 - ty-make cc-last-expr-type !
      else,
        drop
      then,
    else,
      tok-kind @ tk-punct = tok-num @ pt-plus-plus = and if,
        \ Prefix '++'.  Bump operand in place, leave new value in rdi.
        [lit] 1 cc-parse-prefix-inc-dec
      else,
        tok-kind @ tk-punct = tok-num @ pt-minus-minus = and if,
          \ Prefix '--'.  Pass any value other than 1; cc-parse-prefix-
          \ inc-dec branches to the dec encoder for non-1.
          [lit] 0 cc-parse-prefix-inc-dec
        else,
          tok-kind @ tk-punct = tok-num @ [lit] 45 = and if,
            \ Unary '-'.
            cc-parse-unary-tramp
            cc-emit-materialize
            cc-emit-neg-rdi
            cc-mark-not-lvalue
          else,
            tok-kind @ tk-punct = tok-num @ [lit] 33 = and if,
              \ Unary '!'.  rdi := (rdi == 0).
              cc-parse-unary-tramp
              cc-emit-materialize
              cc-emit-not-zero-flag
              cc-mark-not-lvalue
            else,
              tok-kind @ tk-punct = tok-num @ [lit] 126 = and if,
                \ Unary '~'.
                cc-parse-unary-tramp
                cc-emit-materialize
                cc-emit-not-rdi
                cc-mark-not-lvalue
              else,
                \ Not a unary operator — putback so primary sees the same token.
                cc-putback-token
                cc-parse-primary
              then,
            then,
          then,
        then,
      then,
    then,
  then,
  then, ;

' cc-parse-unary cc-parse-unary-vec !

```

`cc-parse-unary` itself is a chain of `if, … else,` clauses, one per
operator: `sizeof`, `&`, `*`, prefix `++` and `--`, `-`, `!`, `~`.
Any other token goes back, and `cc-parse-primary` takes over.

Unary `&` accepts only a bare local, as in `&p` or `&arr`.  The
forms `&*p`, `&arr[i]`, and `&s->field` aren't supported, and
M2-Planet doesn't use them.

Unary `*` parses its operand through the trampoline, materializes
it so `rdi` holds a clean address, and marks kind=2, leaving the
load to the consumer.  That is how `*p = q;` works: the assignment
sees kind=2 and stores through the address.

On a `char*` the deref must be byte-width, or `*p = c` would store
8 bytes and clobber the seven after the target.  The operand's type
arrives in `cc-last-expr-type` (set by §4's scalar branches); the
`*` clause snapshots it before `cc-emit-materialize` clears it,
picks the byte or qword mark, and records the pointee type for any
following postfix.  This is the rule §3 applies to `p[i]`.

## 6. Ternary

```forth chunk=expr-ternary
\ ===========================================================================
\ Ternary  cond '?' then ':' else
\ ===========================================================================
\ Right-associative; the two arms recurse through cc-parse-assign so that
\ chained `a ? b : c ? d : e` parses as `a ? b : (c ? d : e)` and lower-
\ precedence comma-free assignment lives inside an arm.
\
\ Codegen:
\   <eval cond>
\   test rdi,rdi
\   jz   .else
\   <eval then-arm>
\   jmp  .end
\ .else:
\   <eval else-arm>
\ .end:

: cc-parse-ternary
  cc-parse-log-or
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [lit] 63 = and if,
    \ '?' — consume and emit branch.
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jz-rel32-placeholder >r               \ R: f-else
    cc-parse-assign-tramp                         \ then-arm (right-assoc)
    cc-emit-materialize
    cc-emit-jmp-rel32-placeholder >r              \ R: f-else f-end
    \ Expect ':' — inline check (cc-expect-punct-c lives in 110-cc-decl.fth).
    cc-next-token-keep
    tok-kind @ tk-punct <> tok-num @ [lit] 58 <> or if,
      [lit] 35 die
    then,
    \ Pop fixups: top of rstack is f-end, second is f-else.
    r> r>                                         ( f-end f-else )
    cc-patch-rel32-to-here                        \ patch f-else
    cc-parse-assign-tramp                         \ else-arm
    cc-emit-materialize
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  else,
    cc-putback-token
  then, ;

```

`cc-parse-ternary` is `cc-parse-log-or` plus an optional
`? then : else` tail.  On a `?` it emits a test and a conditional
jump, parses each arm through `cc-parse-assign-tramp`, and patches
two fixups, one for the jump to the else-arm and one for the jump
past it.

Because the arms recurse through `cc-parse-assign` rather than
`cc-parse-ternary`, each arm can hold an assignment.  For the
middle arm that matches C.  For the last arm it doesn't: in C,
`a ? b = 1 : c = 2` is a syntax error, because the else-arm is a
conditional-expression and can't contain a bare `=`.  This compiler
accepts it and parses the tail as `c = 2` (a program returning that
expression with `a` false gets `2`).  M2-Planet never writes this,
so Stage A never notices.

## 7. Assignment: snapshot, recurse, store

```forth chunk=expr-assign
\ ===========================================================================
\ cc-parse-assign: eq ('=' assign)?
\ ===========================================================================
\ Right-recursive.  After parsing the LHS via cc-parse-eq, snapshot
\ cc-last-ident-slot on the data stack BEFORE recursing into the RHS (which
\ would otherwise overwrite it).
\
\ We test the next token without immediately committing: if it's '=', we use
\ the snapshot to emit a store; otherwise we put the token back and discard
\ the snapshot.
\
\ NOTE: assignment is right-associative, so the RHS recurses through
\ cc-parse-assign (not cc-parse-eq) — chained `a = b = 1` works.

\ cc-assign-op? ( -- f )  After cc-next-token-keep, returns -1 if the
\ current token is any of: '=' '+=' '-=' '*=' '/=' '%=' '<<=' '>>=' '&='
\ '|=' '^='.
: cc-assign-op?
  tok-kind @ tk-punct = if,
    tok-num @ [lit] 61      =
    tok-num @ pt-plus-eq    = or
    tok-num @ pt-minus-eq   = or
    tok-num @ pt-star-eq    = or
    tok-num @ pt-slash-eq   = or
    tok-num @ pt-percent-eq = or
    tok-num @ pt-shl-eq     = or
    tok-num @ pt-shr-eq     = or
    tok-num @ pt-amp-eq     = or
    tok-num @ pt-pipe-eq    = or
    tok-num @ pt-caret-eq   = or
  else,
    [lit] 0
  then, ;

```

`cc-assign-op?` recognises plain `=` and the ten compound forms.
(The header's mention of `cc-parse-eq` is out of date: the left side
is parsed by `cc-parse-ternary`.)

```forth chunk=expr-assign
\ cc-apply-compound-op ( op -- )  After rdi=LHS-value, rcx=RHS-value: apply
\ the compound-assign op to rdi.  Consumes op.  Plain '=' must be filtered
\ by the caller before invoking this.
: cc-apply-compound-op
  dup pt-plus-eq = if,
    drop cc-emit-add-rdi-rcx
  else,
    dup pt-minus-eq = if,
      drop cc-emit-sub-rdi-rcx
    else,
      dup pt-star-eq = if,
        drop cc-emit-imul-rdi-rcx
      else,
        dup pt-slash-eq = if,
          drop cc-emit-idiv-quotient
        else,
          dup pt-percent-eq = if,
            drop cc-emit-idiv-remainder
          else,
            dup pt-shl-eq = if,
              drop cc-emit-shl-rdi-cl
            else,
              dup pt-shr-eq = if,
                drop cc-emit-sar-rdi-cl
              else,
                dup pt-amp-eq = if,
                  drop cc-emit-and-rdi-rcx
                else,
                  dup pt-pipe-eq = if,
                    drop cc-emit-or-rdi-rcx
                  else,
                    pt-caret-eq = if,
                      cc-emit-xor-rdi-rcx
                    else,
                      \ Unknown compound op — abort.
                      [lit] 43 die
                    then,
                  then,
                then,
              then,
            then,
          then,
        then,
      then,
    then,
  then, ;

```

`cc-apply-compound-op` maps each of the ten `pt-*-eq` codes to the
matching binary-op emitter from Ch 25 §5 and Ch 26 §4.  It runs
after `rdi` holds the left value and `rcx` the right.

```forth chunk=expr-assign
: cc-parse-assign
  cc-parse-ternary
  \ Snapshot lvalue state BEFORE the recursive RHS parse can clobber it.
  cc-last-lvalue-kind @                           ( kind )
  cc-last-ident-slot @                            ( kind slot )
  cc-next-token-keep
  cc-assign-op? if,
    \ Some assignment operator confirmed.  Dispatch on lvalue kind.
    \ Stack layout: ( kind slot ).  kind=1 -> local; kind=2 -> deref;
    \ kind=0 (or other) -> not an lvalue (error).
    over [lit] 1 = if,
      \ ---- Local lvalue (kind=1) -----------------------------------------
      \ The LHS load was already emitted by cc-parse-primary; we'll just
      \ overwrite the local slot with the RHS / RHS-folded value.
      nip                                         ( slot )
      tok-num @                                   ( slot op )
      swap >r                                     \ stash slot ( op ; R: slot )
      \ For compound assignment, save current LHS value before parsing RHS.
      dup [lit] 61 = 0= if,
        cc-emit-push-rdi
      then,
      >r                                          \ stash op ( ; R: slot op )
      cc-parse-assign
      cc-emit-materialize                         \ ensure rdi holds a value
      r> r>                                       ( op slot )
      swap                                        ( slot op )
      dup [lit] 61 = if,
        drop                                      ( slot )
      else,
        cc-emit-mov-rcx-rdi                       \ rcx = RHS
        cc-emit-pop-rdi                           \ rdi = LHS (saved earlier)
        cc-apply-compound-op                      \ rdi := rdi <op> rcx
      then,
      cc-emit-store-local                         \ [rbp - 8*(slot+1)] := rdi
      cc-mark-not-lvalue
    else,
      over [lit] 2 = if,
        \ ---- Dereference lvalue (kind=2) ---------------------------------
        \ rdi already holds the destination address (no load was emitted by
        \ cc-parse-unary).  Plain `=` is supported on derefs; compound
        \ +=/-= would require load-modify-store and is deferred.
        2drop                                     \ discard saved kind/slot
        tok-num @ [lit] 61 <> if,
          [lit] 42 die
        then,
        \ Snapshot the byte-width flag BEFORE cc-parse-assign clobbers it.
        cc-last-deref-is-byte @ >r                \ R: byte?
        cc-emit-push-rdi                          \ save dest address
        cc-parse-assign
        cc-emit-materialize                       \ rdi holds RHS value
        cc-emit-mov-rcx-rdi                       \ rcx := RHS
        cc-emit-pop-rdi                           \ rdi := dest address
        \ End-of-sequence wants rdi=value, rcx=address.  We currently have
        \ rcx=value, rdi=address.  Swap via push/pop:
        \    push rdi ; mov rdi, rcx ; pop rcx
        cc-emit-push-rdi                          \ push address
        \ mov rdi, rcx: 48 89 CF (mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111=0xCF)
        [lit]  72 cc-emit-byte
        [lit] 137 cc-emit-byte
        [lit] 207 cc-emit-byte
        cc-emit-pop-rcx                           \ rcx := address
        r> if,
          cc-emit-store-byte-via-rcx              \ [rcx] := dil  (1 byte)
        else,
          cc-emit-store-via-rcx                   \ [rcx] := rdi  (8 bytes)
        then,
        cc-mark-not-lvalue
      else,
        \ Not an lvalue at all.
        2drop
        [lit] 41 die
      then,
    then,
  else,
    2drop                                         \ discard kind/slot snapshot
    cc-putback-token
  then, ;

```

`cc-parse-assign` is where the lvalue tracking from §1 is consumed:

1. Parse the left side with `cc-parse-ternary`, which leaves
   `cc-last-lvalue-kind` and `cc-last-ident-slot` describing it.
2. Copy both onto the data stack as `( kind slot )`, because the
   recursive parse of the right side will overwrite the globals.
3. Read the next token.  If it isn't an assignment operator, put it
   back and drop the snapshot.
4. For kind=1 (a local), the left value is already in `rdi`.  Plain
   `=` just parses the right side and stores.  A compound operator
   pushes the left value first, then pops it back and folds with
   `cc-apply-compound-op` before the store.
5. For kind=2 (a deref), `rdi` holds the destination address.  The
   code pushes it, parses the right side, swaps the registers so
   `rdi` holds the value and `rcx` the address, and emits a byte or
   qword store.  Only plain `=` is accepted (status 42 otherwise).
6. Kind=0 is not an lvalue, as in `1 = 2`, and dies with status 41.

## 8. The top-level driver

```forth chunk=expr-top
\ ===========================================================================
\ cc-parse-expr: top-level entry
\ ===========================================================================

\ cc-parse-expr always ends with a materialize so any consumer (return,
\ if/while cond, expression-statement, function-call argument, decl
\ initializer, ...) receives an actual value in rdi rather than a pending
\ deref-address.
: cc-parse-expr
  cc-parse-assign
  cc-emit-materialize ;

\ cc-parse-expr-balanced ( -- )
\ Parse an expression while preserving the caller's Forth data stack item.
\ The generated target value still lives in machine rdi; this only fences the
\ seed-Forth parser stack so statement/control-flow fixups remain on top.
: cc-parse-expr-balanced
  >r [lit] 0 cc-parse-expr drop r> ;

\ cc-parse-expr-balanced-2 ( a b -- a b )
\ Variant for callers that thread two parser-stack values under an expression,
\ currently function-call parsing's (callee-id arg-count).
: cc-parse-expr-balanced-2
  >r >r [lit] 0 cc-parse-expr drop r> r> ;

\ Wire the trampolines.
' cc-parse-expr   cc-parse-expr-vec   !
' cc-parse-assign cc-parse-assign-vec !
```

`cc-parse-expr` is the only entry point the rest of the compiler
uses.  It calls `cc-parse-assign` and then materializes, so every
consumer sees a value in `rdi`, never a pending dereference.

`cc-parse-expr-balanced` and `cc-parse-expr-balanced-2` protect one
or two of the caller's parser-stack items, such as a statement's
fixups or a call's `( callee-id arg-count )`.  They move the items
to the return stack, push a 0, parse, drop the 0, and bring the
items back.

The last two lines fill the vecs declared in Ch 27 §4, so
`cc-parse-expr-tramp` and `cc-parse-assign-tramp` reach the real
words.

## 9. Putting the cascade together: full expression flow

A condition like `if (x->next != NULL && x->next->val > 0)` uses
everything in Chs 27–28:

1. `cc-parse-expr` enters at the if-condition.
2. `cc-parse-assign` cascades down through ternary, log-or,
   log-and, bit-or, bit-xor, bit-and, eq, rel, shift, add, mul,
   unary, primary.
3. Primary reads `x`, looks it up, sees `sk-local` with type
   `ty-struct ptr-depth=1`, emits `mov rdi, [rbp - 8]`, marks
   `cc-mark-local-lvalue 0`, sets `cc-last-struct-desc` to the
   struct's descriptor.
4. The postfix loop reads `->`, calls `cc-find-field next`,
   gets the offset, emits `add rdi, <offset>`, marks
   `cc-mark-deref-lvalue`, updates `cc-last-struct-desc` to
   `next`'s pointee descriptor.
5. We come back up the cascade.  `cc-parse-rel` reads `!=`, which
   is an `eq` op, so it puts the token back.  `cc-parse-eq`
   matches, emits the binary-op template, and recurses into
   `cc-parse-rel` for the right side.
6. The right side parses `NULL` (a preprocessor macro for 0).
7. `cc-emit-cmp-ne` produces 0/1 in `rdi`.  Mark not-lvalue.
8. Back at `cc-parse-log-and`, the next token is `&&`.  Match.
   Test, jz-fixup, recurse for the right side.
9. The right side parses `x->next->val > 0`: the same chained
   arrows, then a `>` and a literal `0`.
10. `cc-parse-log-and` finishes the short-circuit with three
    fixups and leaves `1` or `0` in `rdi`.
11. `cc-parse-expr` materializes, a no-op since `rdi` already holds
    a value.
12. The if-statement codegen (Ch 30) emits its own
    test-and-jump using the value in `rdi`.

## Try it

**Small check:** choose one focused fixture below and trace the
lvalue, postfix, assignment, or `sizeof` path it exercises.

**Layer check:** `./test.sh` exercises the expression parser through
the focused C fixtures.

```sh
./build.sh
./test.sh                                   # exercises the expression parser
```

**Bootstrap relevance:** the full Stage-A gate confirms that lvalues,
postfix forms, assignment, and `sizeof` behave correctly inside the
M2-Planet compile.  Two byte-width paths that compile never takes
have their own gates.  `tests/cc/D-charptr-store.c` stores through a
dereferenced `char*` and fails if that store is a qword `mov` that
clobbers the seven bytes past the target.
`tests/cc/E-chained-subscript.c` chains `v[i][j]` on a `char*` array
and fails if the second subscript uses qword stride.  Stage-A's bytes
are the same either way, so parity alone can't catch these.

```sh
tests/cc/stage-a-check.sh
```

`tests/cc/G7.c` (pointer `&`/`*`), `G8.c` (array indexing), `G9a.c`
(struct `.` access), `G9b.c` (struct field arithmetic), `G10c.c`
(`sizeof`), and `G11.c` (postfix `++`/`--` and compound assignment
in a dense mix) exercise this chapter's machinery in isolation.

## Exercises

1. **★ Trace.** Trace what `cc-parse-primary` emits for the literal `'X'`.
   Where does the character value end up?

2. **★★ Trace.** Construct a C expression that chains the postfix
   operators `.`, `->` and `[]` (say, `s.next->arr[1]` with a
   local `struct N s`).  Sketch the lvalue-kind transitions as it
   parses.  Then append `++`: the compile dies with status 53, and
   so do `b[1]++` and `x++--`.  Which lvalue kind does postfix `++` accept, and why
   does every one of these operands fail that test?

3. **★★★ Extend.** Compound assignment of dereference targets (`*p += 1`) is
   *not* supported (§7's kind=2 branch errors on anything but
   plain `=`).  Sketch a patch.  What new state would
   `cc-parse-assign` need to thread?

4. **★★★ Extend.** `cc-parse-sizeof` accepts `sizeof(struct TAG)` and
   `sizeof(typedef-name)` but not `sizeof(*p)`.  Add the
   missing case.  What does the compile-time evaluation look
   like?

5. **★★ Trace.** The forward-call placeholder in §4 walks a linked list via
   `cc-sym-extra2`.  Trace how Ch 31's `cc-parse-function`
   patches that list when the definition arrives.  How is the
   list head set to 0 again?

## After this chapter

The compiler can lower the floor and tail of expressions: primary
(literals, identifiers, calls, postfix `.`/`->`/`[]`/`++`/`--`),
unary (`*`, `&`, prefix `++`/`--`, `sizeof`, `!`, `-`, `~`), the
ternary `?:`, and the assignment family, all with lvalue tracking
that defers each load until the consumer decides between reading
and writing.

You can read `cc-parse-primary`'s postfix chain, explain the three
lvalue kinds and when `cc-emit-materialize` fires, and follow how
`p[i] = c;` reaches the right byte-width store without a separate
codegen path.

## Takeaways

- An expression's value in `rdi` is a temp, a loaded local, or a
  pending-deref address, and `cc-emit-materialize` turns the third
  into a load only when a consumer needs the value.
- Every C expression bottoms out in `cc-parse-primary`, which
  dispatches on the token kind, resolves the symbol by storage and
  type, and then loops over postfix `.`, `->`, `[]`, `++`, and `--`.
- Assignment snapshots `( kind slot )` on the data stack before
  parsing its right side, so nested assignments can't overwrite the
  left side's lvalue state.

Next: Chapter 29 — Declarations: Types, Structs, Locals.

