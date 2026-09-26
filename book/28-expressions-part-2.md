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
layer.  Function-call codegen, `cc-parse-call`, sits in this file
just above `cc-parse-primary` but is Ch 31's subject, and the
statements that call `cc-parse-expr` are Ch 30's.

---

## 1. Lvalue tracking: four globals, four kinds

```forth chunk=expr-lvalue
\ ===========================================================================
\ Lvalue tracking for assignment, address-of, and dereference.
\ ===========================================================================
\ Every parse function leaves a value in rdi and four facts about it here.
\ The cc-mark words below write the kind and slot and clear the struct
\ descriptor and the type, which the parser sets afterwards when it knows
\ them; cc-emit-materialize is the only other writer of the kind.
\
\   cc-last-lvalue-kind  what rdi holds — one of the lv-* constants:
\       lv-value      a value; not assignable
\       lv-local      a local's value, already loaded; the local is
\                     cc-last-ident-slot, so `x = ...` stores back there
\       lv-deref      the ADDRESS of a qword that has not been loaded yet
\       lv-deref-byte the ADDRESS of a single byte (a char) not loaded yet
\     A consumer that wants the value calls cc-emit-materialize, which loads
\     through a pending address; assignment instead stores through it.
\   cc-last-ident-slot   slot index of an lv-local (-1 otherwise).
\   cc-last-struct-desc  struct descriptor of a struct or struct-pointer
\                        value (0 if none), for a following '.' / '->'.
\   cc-last-expr-type    encoded C type (ty-base + ptr-depth) of the value,
\                        0 if unknown.  A following '[' or unary '*' reads it
\                        to pick byte or qword stride and width.
\
\ A binary operator's result is a plain value: it marks lv-value, which
\ clears all four.  cc-parse-assign reads kind and slot once, right after
\ parsing the left side, and keeps them on the data stack while the right
\ side's parse overwrites them.

[lit] 0 constant lv-value
[lit] 1 constant lv-local
[lit] 2 constant lv-deref
[lit] 3 constant lv-deref-byte

variable cc-last-lvalue-kind                       \ lv-value .. lv-deref-byte
variable cc-last-ident-slot
variable cc-last-struct-desc
variable cc-last-expr-type

\ cc-mark ( slot kind -- )  Record kind and slot; clear desc and type.
: cc-mark
  cc-last-lvalue-kind !
  cc-last-ident-slot !
  [lit] 0 cc-last-struct-desc !
  [lit] 0 cc-last-expr-type ! ;

\ cc-mark-not-lvalue ( -- )  rdi holds a plain value.
: cc-mark-not-lvalue     true lv-value cc-mark ;

\ cc-mark-local-lvalue ( slot -- )  rdi holds the loaded value of local slot.
: cc-mark-local-lvalue   lv-local cc-mark ;

\ cc-mark-deref ( byte? -- )  rdi holds an address not yet loaded; byte? is
\ true when it addresses a single byte (`s[i]` or `*s` with s a char*).
: cc-mark-deref
  if, lv-deref-byte else, lv-deref then,
  true swap cc-mark ;

\ cc-deref-pending? ( -- f )  True if rdi holds an address not yet loaded.
: cc-deref-pending?
  cc-last-lvalue-kind @ lv-deref =
  cc-last-lvalue-kind @ lv-deref-byte = or ;

\ cc-char-ptr? ( ty -- f )  True iff ty is char* (a subscript or '*' on it
\ reaches a single byte).
: cc-char-ptr?
  dup ty-base ty-char = swap ty-ptr [lit] 1 = and ;

\ cc-emit-materialize ( -- )  If rdi holds an address not yet loaded, load
\ through it (one byte or eight) so rdi holds the value, and mark it a plain
\ value.  The struct descriptor and type describe the value either way, so
\ they are kept.  A no-op for lv-value and lv-local.
: cc-emit-materialize
  cc-deref-pending? if,
    cc-last-lvalue-kind @ lv-deref-byte = if,
      cc-emit-load-byte-via-rdi
    else,
      cc-emit-load-via-rdi
    then,
    true cc-last-ident-slot !
    lv-value cc-last-lvalue-kind !
  then, ;

```

Four globals form the lvalue state.

- `cc-last-lvalue-kind` is the discriminator, one of four named
  constants: `lv-value` (a temp, not assignable), `lv-local` (a
  local's value, already in `rdi`, whose slot is in
  `cc-last-ident-slot`), `lv-deref` (`rdi` holds the *address* of a
  qword not yet loaded) and `lv-deref-byte` (the same for a single
  byte, as in `s[i]` with `s` a `char*`).  Width is part of the kind,
  so a pending deref can't be read without knowing how wide it is.
- `cc-last-ident-slot` carries the slot for `lv-local`.
- `cc-last-struct-desc` carries the struct descriptor (Ch 24 §1)
  for any struct-typed value just loaded.
- `cc-last-expr-type` is the encoded type word of the value just
  produced, so postfix `[]` and unary `*` can choose byte or qword.

Every binary-op fold in Ch 27 calls `cc-emit-materialize` before
consuming an operand.  For `lv-value` and `lv-local` (a local
already loaded into `rdi`) it's a no-op.  For a pending deref it
emits the actual `mov rdi, [rdi]` (or `movzx rdi, byte [rdi]` for
`lv-deref-byte`) and marks the result `lv-value`.  It keeps the
descriptor and the type: they describe the loaded value just as
well as the address, so no caller has to save them around the load.

All the setters go through `cc-mark ( slot kind -- )`, which writes
the kind and slot and clears the descriptor and type; the parser sets
those two afterwards when it knows them.  `cc-mark-not-lvalue`,
`cc-mark-local-lvalue` and `cc-mark-deref` (which takes a byte? flag
and picks the deref kind) are one-line wrappers.  A binary op ends
with `cc-mark-not-lvalue` because its result is a temp.

## 2. Struct-field lookup

```forth chunk=expr-struct-field
\ ===========================================================================
\ Struct-field name lookup.
\ ===========================================================================
\ Walks the descriptor's field array and returns the first matching field's
\ byte offset, leaving its pointee desc and encoded type in cc-ff-result-desc
\ and cc-ff-result-type for the caller.  Dies with code 90 if no field
\ matches (compile-time error: field not found).  Uses globals to stash the
\ needle so the loop body has predictable stack effect.

variable cc-ff-needle-addr
variable cc-ff-needle-len
variable cc-ff-desc
variable cc-ff-result-desc                           \ matched field's pointee desc (0 if not a struct ptr)
variable cc-ff-result-type                           \ matched field's encoded type (ty-base + ptr-depth)

\ cc-find-field ( name-addr name-len desc -- offset )
: cc-find-field
  cc-ff-desc           !
  cc-ff-needle-len     !
  cc-ff-needle-addr    !
  \ Loop i = 0..field-count-1.
  cc-ff-desc @ cc-sd-field-count                    ( count )
  [lit] 0                                            ( count i )
  begin,
    over over >                                      ( count i count>i? )
  while,
    \ Compare names at field i.
    cc-ff-desc @ over cc-sd-field-rec                ( count i rec )
    dup cc-sf-name-len cc-ff-needle-len @ = if,
      dup cc-sf-name-addr                           ( count i rec entry-addr )
      cc-ff-needle-addr @ swap                      ( count i rec needle entry )
      cc-ff-needle-len  @                           ( count i rec needle entry u )
      bytes-eq if,                                  ( count i rec )
        dup cc-sf-desc cc-ff-result-desc !
        dup cc-sf-type cc-ff-result-type !
        cc-sf-offset nip nip exit,                  ( offset )
      then,
    then,
    drop                                            ( count i )
    1+                                              ( count i+1 )
  repeat,
  [lit] 90 cc-die ;

```

`cc-find-field` walks the descriptor's field records (Ch 24 §1)
looking for one whose name matches the needle, returns its
offset, and stashes the matched field's pointee descriptor and
type in `cc-ff-result-{desc,type}` for the postfix handler.

The walk returns with `exit,` on the first match, as
`cc-check-keyword` (Ch 23) and `cc-sym-find` (Ch 24) do; `nip nip`
first clears the loop's count and index so only the offset is left.

A missing field is fatal (code 90).  By this point
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
\   inline local array  (sk-local,  len>0)  lea  rdi, [rbp+disp]      \ &arr[0]
\   local pointer       (sk-local,  len=0)  mov  rdi, [rbp+disp]      \ value of p
\   inline global array (sk-global, len>0)  movabs rdi, &globals[off]
\   global pointer      (sk-global, len=0)  movabs rdi, &globals[off]; mov rdi, [rdi]
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
\ This word then marks the result a pending deref (lv-deref) so the consumer
\ either does the load (rvalue use, via cc-emit-materialize) or treats rdi
\ as the destination address (lvalue use in assignment, the deref path).
: cc-parse-array-index                            ( id -- )
  \ Accept sk-local or sk-global.
  dup cc-sym-kind-of sk-local =
  over cc-sym-kind-of sk-global = or 0= if,
    drop
    [lit] 91 cc-die
  then,

  \ Emit base address into rdi.
  dup cc-sym-kind-of sk-global = if,
    dup cc-sym-val-of cc-emit-global-ref          \ rdi = &globals[off]
    dup cc-sym-array-len-of [lit] 0 = if,
      cc-emit-load-via-rdi                        \ pointer global: load slot value
    then,
  else,
    dup cc-sym-array-len-of [lit] 0 > if,
      dup cc-sym-val-of cc-emit-lea-rdi-local     \ inline array: address of slot
    else,
      dup cc-sym-val-of cc-emit-load-local        \ pointer local: load slot value
    then,
  then,

  \ Element type of arr[i] plus a byte-step flag, both stashed on the rstack
  \ so they survive the index-expression parse.  An inline array (len>0)
  \ keeps the symbol's type — the subscript consumes the array dimension, not
  \ a pointer level; a pointer (len==0) drops one pointer level.  The step
  \ is one byte iff the element is a plain char, so a chained `[j]` (e.g.
  \ char* v[]; v[i][j]) reads cc-last-expr-type and picks byte stride/deref.
  dup cc-sym-array-len-of [lit] 0 > if,
    cc-sym-type-of                                ( elem-ty )         \ array: keep type
  else,
    cc-sym-type-of                                ( ty )
    dup ty-base swap ty-ptr 1- ty-make            ( elem-ty )         \ ptr: depth-1
  then,
  dup >r                                          ( elem-ty ; R: elem-ty )
  dup ty-base ty-char = swap ty-ptr [lit] 0 = and ( char-step? ; R: elem-ty )
  >r                                              ( ; R: elem-ty char-step? )

  cc-emit-push-rdi

  \ Parse the index expression.  cc-parse-expr-fwd ends with a materialize
  \ so rdi holds an actual integer.
  cc-parse-expr-fwd

  r@ 0= if,
    cc-emit-shl-rdi-3                             \ rdi *= 8 (non-char step)
  then,

  \ Pop the base, add to scaled index.
  cc-emit-pop-rcx
  cc-emit-add-rdi-rcx

  \ Expect ']'.
  cc-next-token-keep
  tok-kind @ tk-punct <> tok-num @ [char] ] <> or if,
    [lit] 92 cc-die
  then,

  \ rdi now holds the element address; mark it a pending deref so the
  \ consumer either loads or stores depending on context.  A char-step
  \ element (flag still on rstack) is a byte-wide deref, so the eventual
  \ load/store is 1 byte, not 8.  The mark zeroes cc-last-expr-type, so
  \ republish the element type afterwards for any chained postfix `[j]`.
  r> cc-mark-deref
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
The choice comes from the *element type* of `arr[i]`.  An inline
array keeps the symbol's own type (the subscript spends the array
dimension, not a pointer level); a pointer drops one pointer level.  The step is one byte exactly when
the element type is a plain `char`.  The helper keeps the element
type on the return stack and writes it back to `cc-last-expr-type`
after the mark, which clears it.  That is what makes a chained
subscript work: in `char* v[]; v[i][j]`, the second `[` sees that
`v[i]` is a `char*` and steps by one byte.

## 4. `cc-parse-primary`: the operand and its postfix chain

A primary is an operand (a literal, a name, or a parenthesised
expression) followed by any number of postfix operators: `.`, `->`,
`[`, `++`, `--`.  The code is a family of small words, one per form.
Each one tests for its cases in turn and returns with `exit,` (Ch 11)
as soon as it has compiled one, so each reads top to bottom as a list
of cases rather than a ladder of nested `else,`s.  The chunk below
lists them in load order: a word must come after the words it calls.

```forth chunk=expr-primary
<<expr-primary-literals>>
<<expr-primary-fn-rvalue>>
<<expr-primary-global>>
<<expr-primary-local>>
<<expr-primary-ident>>
<<expr-primary-paren>>
<<expr-primary-operand>>
<<expr-primary-postfix-incdec>>
<<expr-primary-postfix-index>>
<<expr-primary-postfix-field>>
<<expr-primary-postfix>>
```

### The top: operand, then postfix loop

```forth chunk=expr-primary-postfix
\ cc-postfix-op? ( -- f )  True if the current token is a postfix operator.
: cc-postfix-op?
  [char] . cc-tok-punct?
  pt-arrow cc-tok-punct? or
  pt-plus-plus cc-tok-punct? or
  pt-minus-minus cc-tok-punct? or
  [char] [ cc-tok-punct? or ;

\ cc-parse-primary ( -- )  An operand, then zero or more postfix operators.
: cc-parse-primary
  cc-mark-not-lvalue                              \ default: not an lvalue
  cc-parse-operand
  begin,
    cc-next-token-keep
    cc-postfix-op?
  while,
    tok-num @                                     ( op )
    dup pt-plus-plus = over pt-minus-minus = or if,
      cc-parse-postfix-inc-dec
    else,
      dup [char] [ = if,
        drop cc-parse-postfix-index
      else,
        cc-parse-postfix-field
      then,
    then,
  repeat,
  cc-putback-token ;                              \ not a postfix operator

```

`cc-parse-primary` marks "not an lvalue", compiles one operand, then
loops while the next token is a postfix operator, dispatching on its
code to one of three words below.  The first token that isn't one
goes back to the caller.  `cc-parse-operand` picks the operand's
form from the token kind:

```forth chunk=expr-primary-operand
\ cc-parse-operand ( -- )  Read one token and compile the operand it starts.
: cc-parse-operand
  cc-next-token-keep
  tok-kind @ tk-num = if,
    tok-num @ cc-emit-mov-rdi-int exit,           \ widen to imm64 if out of imm32 range
  then,
  tok-kind @ tk-chr = if,
    \ Character literal — value is in tok-num just like a number.
    tok-num @ cc-emit-mov-rdi-imm32 exit,
  then,
  tok-kind @ tk-str   = if, cc-parse-string-literal exit, then,
  tok-kind @ tk-ident = if, cc-parse-ident          exit, then,
  lparen cc-tok-punct? if, cc-parse-paren exit, then,
  [lit] 97 cc-die ;

```

Every failure in these words is a `cc-die` with its own code
(Appendix G).  A number goes through `cc-emit-mov-rdi-int` (Ch 26),
which widens to a 64-bit `movabs` when the value doesn't fit a
sign-extended `imm32`, so `0x80000000` keeps its value instead of
loading negative.  A character literal is always in `0..255` and
takes the plain `imm32` path.  A token that can't start an operand
at all is code 97.

### String literals

```forth chunk=expr-primary-literals
\ ===========================================================================
\ cc-parse-primary: the operand, then its postfix operators
\ ===========================================================================
\ A primary is an operand (a literal, a name, or a parenthesised expression)
\ followed by any number of postfix operators ('.' '->' '[' '++' '--').
\ Each word below handles one form and returns with exit, as soon as it has
\ compiled it.  Each failure dies through cc-die (020-cc-arena.fth) with its
\ own code; Appendix G of the book lists them.

\ cc-parse-string-literal ( -- )  The current token is a string literal.
\ We emit the bytes inline in the code stream and jump over them, then load
\ their absolute vaddr into rdi:
\     jmp +N            E9 <rel32>          (5 bytes; rel32 patched)
\     <decoded string bytes + NUL>
\   skip:
\     movabs rdi, vaddr 48 BF <imm64>       (10 bytes)
: cc-parse-string-literal
  cc-emit-jmp-rel32-placeholder                   ( fixup-off )
  \ Capture the vaddr where the string bytes will start (= current emit
  \ position, NOT the rel32 fixup, so we keep it on the stack under the
  \ fixup).
  cc-here-vaddr                                   ( fixup-off str-vaddr )
  swap                                            ( str-vaddr fixup-off )
  \ Copy decoded string bytes (with NUL terminator).
  tok-str-addr @ tok-str-len @ cc-emit-string-bytes
  \ Patch the jmp's rel32 to land here (right after the string bytes).
  cc-patch-rel32-to-here                          ( str-vaddr )
  \ Emit the movabs rdi, str-vaddr.
  cc-emit-movabs-rdi-imm64 ;

```

A string literal is emitted *inline in the code segment*: a `jmp`
over the bytes, the bytes and their NUL, then a `movabs` of their
address into `rdi`.  There is no separate string pool, at the cost
of 5 bytes of `jmp` per literal.

### Identifiers, calls, and subscripts

```forth chunk=expr-primary-ident
\ cc-parse-ident ( -- )  The current token is an identifier.  Look it up,
\ then peek one token to tell a call, a subscript and a plain reference
\ apart.
: cc-parse-ident
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id | -1 )
  dup 0< if,
    drop
    [lit] 93 cc-die
  then,
  \ Enum constants resolve to their integer value (mov rdi, imm32).
  \ Handle this BEFORE the suffix peek so RED, GREEN etc. work in any
  \ expression context — they're never callable / indexable / assignable.
  dup cc-sym-kind-of sk-enum = if,
    cc-sym-val-of cc-emit-mov-rdi-imm32
    cc-mark-not-lvalue exit,
  then,
  cc-next-token-keep                              \ peek the suffix
  lparen cc-tok-punct? if,
    \ Function call.  The id must refer either to an sk-func (direct call)
    \ or to an sk-local function pointer (indirect call).
    dup cc-sym-kind-of sk-func <> if,
      dup cc-sym-kind-of sk-local =
      over cc-sym-type-of ty-base ty-func = and 0= if,
        drop
        [lit] 94 cc-die
      then,
    then,
    \ cc-parse-call (above) consumes the '(' (already peeked), parses the
    \ args, emits the call, and leaves the return value in rdi.
    cc-parse-call
    cc-mark-not-lvalue exit,
  then,
  [char] [ cc-tok-punct? if,
    \ Array index.  '[' has been read into tok-*; cc-parse-array-index
    \ consumes through ']'.
    cc-parse-array-index exit,
  then,
  \ A plain reference.  Put back the peeked token.
  cc-putback-token
  dup cc-sym-kind-of sk-func   = if, cc-parse-func-ref   exit, then,
  dup cc-sym-kind-of sk-global = if, cc-parse-global-ref exit, then,
  dup cc-sym-kind-of sk-local  = if, cc-parse-local-ref  exit, then,
  drop
  [lit] 95 cc-die ;

```

An identifier is looked up first; an unknown name dies with code
93.  An enum constant becomes `mov rdi, imm32` before anything else
is considered, since it can't be called, indexed, or assigned.

For any other name the parser peeks one token.  A `(` means a call.
The name must be a function or a local function pointer (the
`ty-func` type from Ch 29 §4), otherwise code 94, and the symbol id
goes to `cc-parse-call`, which sits just above `cc-parse-primary` in
this file and is Ch 31's subject.  A `[` hands the id to
`cc-parse-array-index` (§3).  Anything else is a plain reference, so
the peeked token goes back and the symbol's kind picks one of three
words: a function name, a global, or a local.  Any other kind (a
typedef name or a struct tag used as a value) is code 95.

### A function name as a value

```forth chunk=expr-primary-fn-rvalue
\ cc-parse-func-ref ( id -- )  A function name as a value — `op = square;`.
\ Load the function's absolute vaddr into rdi via movabs.  Result is not an
\ lvalue.  When val == 0 the function is still a forward prototype; emit a
\ 10-byte movabs placeholder and thread the imm64 patch-offset onto its
\ cc-sym-addr-fixups list so cc-parse-function can patch it once the real
\ vaddr is known.  Without this, M2-Planet code like
\ `common_recursion(expression)` (where `expression` is forward-declared)
\ loads 0 into rdi and crashes at the indirect call.
: cc-parse-func-ref
  dup cc-sym-val-of [lit] 0 = if,
    cc-emit-movabs-rdi-imm64-placeholder          ( id patch-off )
    swap cc-sym-addr-fixups                       ( patch-off list-cell )
    cc-add-fixup-to-list
  else,
    cc-sym-val-of cc-emit-movabs-rdi-imm64
  then,
  cc-mark-not-lvalue ;

```

A function name used as a value (`op = square;`) loads the
function's address with `movabs`.  If the function has only been
declared so far, its address isn't known.  The parser then emits a
10-byte `movabs rdi, imm64` with a zero immediate and adds the
patch site to the function's `cc-sym-addr-fixups` list (Ch 26 §1).
Ch 31's `cc-parse-function` patches the list when the definition
arrives.  M2-Planet needs this: it passes forward-declared functions
such as `expression` as arguments.

### Globals

```forth chunk=expr-primary-global
\ cc-parse-global-ref ( id -- )  A file-scope global.  Emit movabs rdi,
\ <vaddr-placeholder> with a deferred fixup.  Scalar globals are
\ deref-pending lvalues (lv-deref); array globals decay to their address
\ (lv-value).
\
\ The type decides which extra fact the symbol carries (070):
\   ty-struct base -> cc-sym-struct-desc-of (NOT an array length).
\   any other      -> cc-sym-array-len-of (>0 for arrays, 0 otherwise).
: cc-parse-global-ref
  dup cc-sym-type-of ty-base ty-struct = if,
    \ Struct or struct-pointer global.  Treat like a scalar (deref-pending
    \ lvalue) so assignment works; record the descriptor for any postfix
    \ '.' / '->'.
    dup cc-sym-val-of cc-emit-global-ref
    [lit] 0 cc-mark-deref
    cc-sym-struct-desc-of cc-last-struct-desc ! exit,
  then,
  dup cc-sym-array-len-of [lit] 0 > if,
    \ Global array: rdi := &globals[slot]; not an lvalue.
    cc-sym-val-of cc-emit-global-ref
    cc-mark-not-lvalue exit,
  then,
  \ Global scalar: rdi := &globals[slot]; mark deref-pending so the consumer
  \ either loads (rvalue) or stores via that address (assignment's deref
  \ path).  Record the scalar's type (across the mark, which clears it) so a
  \ following unary '*' knows whether this is a char* (1-byte deref) or a
  \ wider pointer.
  dup cc-sym-type-of >r
  cc-sym-val-of cc-emit-global-ref
  [lit] 0 cc-mark-deref
  r> cc-last-expr-type ! ;

```

A global's address comes from `cc-emit-global-ref`, and what the
parser does next depends on the type.  A struct or struct-pointer
global becomes a pending deref and records its descriptor for a
following `.` or `->`.  A global array decays to its address and is
not an lvalue.  A scalar global becomes a pending deref (`lv-deref`),
and its type is saved across the mark so that a following unary `*`
knows whether it points to `char`.

### Locals

```forth chunk=expr-primary-local
\ cc-parse-local-ref ( id -- )  A local: struct, struct pointer, array or
\ scalar, told apart by its type.
: cc-parse-local-ref
  dup cc-sym-type-of ty-base ty-struct =
  over cc-sym-type-of ty-ptr [lit] 0 = and if,
    \ struct T x;  Emit lea on the first-element slot so rdi holds the
    \ address of the struct.  Then record the descriptor for any following
    \ '.field'.  This is NOT a normal lvalue (you can't assign to a whole
    \ struct); '.field' will mark a deref.
    dup cc-sym-struct-desc-of                     \ descriptor pointer
    swap cc-sym-val-of                            \ slot of field 0 (deepest)
    cc-emit-lea-rdi-local
    cc-mark-not-lvalue
    cc-last-struct-desc ! exit,
  then,
  dup cc-sym-type-of ty-base ty-struct = if,
    \ struct T* p;  Load the pointer value; treat as an lvalue local
    \ (lv-local) so plain `p = q;` still works, AND record the descriptor
    \ for '->field'.
    dup cc-sym-struct-desc-of                     \ descriptor pointer
    swap cc-sym-val-of                            \ slot index
    dup cc-mark-local-lvalue
    cc-emit-load-local
    cc-last-struct-desc ! exit,
  then,
  dup cc-sym-array-len-of [lit] 0 > if,
    \ An array decays to &arr[0] — emit lea, not load.  The result is a
    \ pointer value (not an lvalue).
    cc-sym-val-of                                 \ slot of arr[0]
    cc-emit-lea-rdi-local
    cc-mark-not-lvalue exit,
  then,
  \ Plain scalar local.  Save its type across the mark (which clears
  \ cc-last-expr-type) so a following unary '*' can tell a char* (1-byte
  \ deref) from a wider pointer.
  dup cc-sym-type-of >r
  cc-sym-val-of                                   \ slot index
  dup cc-mark-local-lvalue                        \ lv-local, remember slot
  cc-emit-load-local
  r> cc-last-expr-type ! ;

```

A local dispatches on its type:

- `struct T x;` emits `lea` of field 0's slot, so `rdi` holds the
  struct's address.  It is not an lvalue (a whole struct can't be
  assigned), but its descriptor is recorded for `.field`.
- `struct T* p;` loads the pointer and marks it `lv-local`, so
  `p = q;` still works, and records the descriptor for `->field`.
- An array decays to `&arr[0]` with `lea`, not an lvalue.
- A plain scalar is loaded and marked `lv-local` with its slot.  Its
  type is saved across the mark, as for globals.

### Parentheses

```forth chunk=expr-primary-paren
\ cc-parse-paren ( -- )  '(' expr ')'.  The parenthesised expr is not an
\ lvalue (cc-parse-primary inside the recursive call will set/clear
\ cc-last-ident-slot; we re-clear it here so e.g. `(x) = 1` doesn't get
\ treated as lvalue).
: cc-parse-paren
  cc-parse-expr-fwd
  cc-mark-not-lvalue
  cc-next-token-keep
  [char] ) cc-tok-punct? 0= if,
    [lit] 96 cc-die
  then, ;

```

`( expr )` recurses through `cc-parse-expr-fwd` (Ch 27 §4) and then
clears the lvalue state, so `(x) = 1` is rejected.  A missing `)` is
code 96.

### The postfix operators

```forth chunk=expr-primary-postfix-incdec
\ cc-parse-postfix-inc-dec ( op -- )  Postfix '++' / '--' on a simple local.
\ The operand parse already loaded the old value into rdi and recorded the
\ slot in cc-last-ident-slot (lv-local).  Bump the slot in place; rdi keeps
\ the old value.  Result is not an lvalue.
: cc-parse-postfix-inc-dec
  cc-last-lvalue-kind @ lv-local <> if,
    drop
    [lit] 98 cc-die
  then,
  pt-plus-plus = if,
    cc-last-ident-slot @ cc-emit-inc-mem-local
  else,
    cc-last-ident-slot @ cc-emit-dec-mem-local
  then,
  cc-mark-not-lvalue ;

```

Postfix `++` and `--` accept only an `lv-local` (anything else is
code 98).  They bump the slot in memory with `inc`/`dec` and leave
the old value, already loaded, in `rdi`.  A subscript:

```forth chunk=expr-primary-postfix-index
\ cc-parse-postfix-index ( -- )  Postfix '[' INDEX ']' applied to whatever
\ value the primary has produced so far (typically after a chain of '.' /
\ '->').  Materialize so rdi holds the actual pointer value (not a
\ deref-pending address), push it, parse the index, scale, add, mark deref.
\ Stride is 1 (byte) iff the subscripted value is a char pointer (e.g.
\ `head->s[i]` where s is char*) — M2-Planet's tokenizer compares
\ `global_token->s[0]` against digit/letter sets, which only works when each
\ byte is loaded individually.  Everything else (int*, struct*, untyped)
\ uses qword stride and qword deref.
: cc-parse-postfix-index
  \ Keep the subscripted value's type on the rstack: the index parse
  \ overwrites cc-last-expr-type.
  cc-emit-materialize
  cc-last-expr-type @ >r                          \ R: pre-subscript ty
  cc-emit-push-rdi
  cc-parse-expr-fwd
  r@ cc-char-ptr? 0= if,
    cc-emit-shl-rdi-3                             \ char*: byte offset, no shift
  then,
  cc-emit-pop-rcx
  cc-emit-add-rdi-rcx
  cc-next-token-keep
  [char] ] cc-tok-punct? 0= if,
    [lit] 99 cc-die
  then,
  \ Mark deref: byte-width iff we just subscripted a char*.  The post-step
  \ expression type drops one level of indirection — record it so chained
  \ `[i][j]` (char**) and following postfix ops can see the right type.
  r@ cc-char-ptr? cc-mark-deref
  r@ ty-ptr [lit] 0 > if,
    r@ ty-base r@ ty-ptr 1- ty-make cc-last-expr-type !
  then,
  r> drop ;

```

A postfix `[` applies to whatever value the chain has produced so
far, as in `head->s[i]`.  Unlike §3's helper it starts from a value
rather than a symbol, so it takes the element type from
`cc-last-expr-type`, kept on the return stack while the index
expression is parsed.  `cc-char-ptr?` decides: a `char*` gets byte
stride and a byte-width deref; everything
else gets qword.  If the value was a pointer, the pointee type is
written back so that `[i][j]` on a `char**` works.  The last word
handles `.` and `->`:

```forth chunk=expr-primary-postfix-field
\ cc-parse-postfix-field ( op -- )  '.' or '->' followed by a field name.
: cc-parse-postfix-field
  cc-last-struct-desc @ [lit] 0 = if,
    [lit] 100 cc-die
  then,
  \ '->': rdi must hold the pointer's value.  A struct-pointer local is
  \ already loaded (lv-local, materialize is a no-op); a struct-pointer
  \ global or field is still an address (lv-deref), so load it.
  \ '.': rdi holds the struct's base address (lv-value); no load.
  \ Materialize keeps cc-last-struct-desc, which the lookup reads.
  pt-arrow = if,
    cc-emit-materialize
  then,
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 101 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-last-struct-desc @
  cc-find-field                                   ( offset )
  cc-emit-add-rdi-imm32
  [lit] 0 cc-mark-deref
  \ Propagate the field's pointee descriptor so chained '->' / '.' (e.g.
  \ `head->next->prev`) can resolve subsequent field lookups.  Stays 0
  \ when the field isn't a struct pointer.
  cc-ff-result-desc @ cc-last-struct-desc !
  \ Record the field's type so a following postfix '[' can detect
  \ char-pointer subscripts (e.g. `head->s[0]`) and emit byte stride/load
  \ instead of qword.  cc-mark-deref cleared this slot above, so set it
  \ after the mark.
  cc-ff-result-type @ cc-last-expr-type ! ;

```

`.` and `->` need a descriptor in `cc-last-struct-desc`, or the
compile dies with code 100 (a missing field name after them is
101).  For `->`, `cc-emit-materialize` turns a pending-deref pointer
into its value, keeping the descriptor; for `.`, `rdi` already holds
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
\ then mark it lv-deref — leaving the load for the consumer.

```

`cc-parse-unary` calls itself directly for `**p` or `-~x`: `:`
makes a word findable as soon as its header exists, so only calls to
words defined *later* need Ch 27 §4's deferred words.

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
    tok-kind @ tk-punct = tok-num @ [char] * = and
  while,
    [lit] 8 cc-sizeof-bytes !
  repeat, ;

```

`cc-parse-sizeof` itself dispatches on the token after `(`: a type
keyword, `struct TAG`, a typedef name, or a local variable.

```forth chunk=expr-unary
: cc-parse-sizeof
  \ Expect '('.  We inline the check because cc-expect-punct-c lives in
  \ 110-cc-decl.fth (loaded AFTER 100-cc-expr.fth) and isn't visible yet.
  cc-next-token-keep
  tok-kind @ tk-punct <> tok-num @ lparen <> or if,
    [lit] 102 cc-die
  then,
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-struct = if,
      \ struct TAG — look up descriptor.
      cc-next-token-keep
      tok-kind @ tk-ident <> if,
        [lit] 103 cc-die
      then,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup 0< if,
        [lit] 104 cc-die
      then,
      dup cc-sym-kind-of sk-struct <> if,
        [lit] 105 cc-die
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
            [lit] 106 cc-die
          then,
        then,
      then,
      cc-sizeof-count-stars-add
    then,
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup 0< if,
        [lit] 107 cc-die
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
              cc-sym-struct-desc-of cc-sd-total-size cc-sizeof-bytes !
            else,
              \ struct T* p; — 8 bytes.
              drop [lit] 8 cc-sizeof-bytes !
            then,
          else,
            dup cc-sym-array-len-of [lit] 0 > if,
              \ Array — N * 8 (this subset assumes int elements here).
              cc-sym-array-len-of [lit] 8 * cc-sizeof-bytes !
            else,
              \ Scalar.
              cc-sym-type-of ty-size cc-sizeof-bytes !
            then,
          then,
          cc-next-token-keep                       \ should land on ')'
        else,
          drop
          [lit] 108 cc-die
        then,
      then,
    else,
      [lit] 109 cc-die
    then,
  then,
  \ Current token must be ')'.
  tok-kind @ tk-punct <> tok-num @ [char] ) <> or if,
    [lit] 110 cc-die
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
    [lit] 111 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find
  dup 0< if,
    drop drop
    [lit] 112 cc-die
  then,
  dup cc-sym-kind-of sk-local <> if,
    drop drop
    [lit] 113 cc-die
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

Prefix `++` and `--` accept only a local identifier (codes 111, 112
and 113).  They bump the slot in memory, then load the new value into
`rdi`.

```forth chunk=expr-unary
: cc-parse-unary
  cc-next-token-keep
  kw-sizeof cc-tok-kw? if,
    \ sizeof(TYPE).  The `sizeof` keyword is the current token; we just
    \ leave it as "consumed" (no putback) and dispatch into cc-parse-sizeof.
    cc-parse-sizeof exit,
  then,
  [char] & cc-tok-punct? if,
    \ '&' = address-of.  Operand must be a simple local IDENT.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 114 cc-die
    then,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if,
      drop
      [lit] 115 cc-die
    then,
    dup cc-sym-kind-of sk-local <> if,
      drop
      [lit] 116 cc-die
    then,
    cc-sym-val-of                                 \ slot
    cc-emit-lea-rdi-local
    cc-mark-not-lvalue exit,                      \ &x is a value, not an lvalue
  then,
  [char] * cc-tok-punct? if,
    \ '*' = dereference.  A char* operand (ty-char, ptr-depth 1) derefs to a
    \ single byte; int*, T**, etc. deref to a qword.  The operand's type sits
    \ in cc-last-expr-type when it came from a scalar variable (recorded in
    \ cc-parse-primary), so `*p = c` on a char* emits a 1-byte store instead
    \ of clobbering 8 bytes.  The mark clears the type; keep it on the stack.
    cc-parse-unary
    cc-emit-materialize                           \ operand is now a value (an address)
    cc-last-expr-type @                           ( ty ; 0 if untracked )
    dup cc-char-ptr? cc-mark-deref                \ defer the load; *char* is 1 byte
    dup ty-ptr [lit] 0 > if,                      \ record pointee type for chained ops
      dup ty-base swap ty-ptr 1- ty-make cc-last-expr-type !
    else,
      drop
    then,
    exit,
  then,
  \ Prefix '++' / '--'.  Bump the operand in place, leave the new value in
  \ rdi.  cc-parse-prefix-inc-dec takes 1 for ++, anything else for --.
  pt-plus-plus   cc-tok-punct? if, [lit] 1 cc-parse-prefix-inc-dec exit, then,
  pt-minus-minus cc-tok-punct? if, [lit] 0 cc-parse-prefix-inc-dec exit, then,
  \ '-', '!' and '~' parse their operand, materialize it, and emit one
  \ operation on rdi ('!' gives rdi := (rdi == 0)).
  [char] - cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-emit-neg-rdi cc-mark-not-lvalue exit,
  then,
  [char] ! cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-emit-not-zero-flag cc-mark-not-lvalue exit,
  then,
  [char] ~ cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-emit-not-rdi cc-mark-not-lvalue exit,
  then,
  \ Not a unary operator — putback so primary sees the same token.
  cc-putback-token
  cc-parse-primary ;

```

`cc-parse-unary` is a list of cases, one per operator: `sizeof`,
`&`, `*`, prefix `++` and `--`, `-`, `!`, `~`.  Each tests the
current token with Ch 27's `cc-tok-kw?` or `cc-tok-punct?`, compiles
its operator and returns with `exit,`.  A token that matches none of
them goes back, and `cc-parse-primary` takes over.

Unary `&` accepts only a bare local, as in `&p` or `&arr`.  The
forms `&*p`, `&arr[i]`, and `&s->field` aren't supported, and
M2-Planet doesn't use them.

Unary `*` parses its operand with a recursive call, materializes
it so `rdi` holds a clean address, and marks a pending deref,
leaving the load to the consumer.  That is how `*p = q;` works: the
assignment sees `lv-deref` and stores through the address.

On a `char*` the deref must be byte-width, or `*p = c` would store
8 bytes and clobber the seven after the target.  The operand's type
arrives in `cc-last-expr-type` (set by §4's scalar branches) and
survives `cc-emit-materialize`; the `*` clause reads it, passes
`cc-char-ptr?`'s answer to `cc-mark-deref`, and records the pointee
type for any following postfix.  This is the rule §3 applies to `p[i]`.

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
  tok-kind @ tk-punct = tok-num @ [char] ? = and if,
    \ '?' — consume and emit branch.
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jz-rel32-placeholder >r               \ R: f-else
    cc-parse-assign-fwd                         \ then-arm (right-assoc)
    cc-emit-materialize
    cc-emit-jmp-rel32-placeholder >r              \ R: f-else f-end
    \ Expect ':' — inline check (cc-expect-punct-c lives in 110-cc-decl.fth).
    cc-next-token-keep
    tok-kind @ tk-punct <> tok-num @ [char] : <> or if,
      [lit] 117 cc-die
    then,
    \ Pop fixups: top of rstack is f-end, second is f-else.
    r> r>                                         ( f-end f-else )
    cc-patch-rel32-to-here                        \ patch f-else
    cc-parse-assign-fwd                         \ else-arm
    cc-emit-materialize
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  else,
    cc-putback-token
  then, ;

```

`cc-parse-ternary` is `cc-parse-log-or` plus an optional
`? then : else` tail.  On a `?` it emits a test and a conditional
jump, parses each arm through `cc-parse-assign-fwd`, and patches
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
\ cc-parse-assign: ternary (ASSIGN-OP assign)?
\ ===========================================================================
\ Right-recursive.  After parsing the LHS via cc-parse-ternary, snapshot
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
\ current token is '=' or the compound form of an operator in the table
\ ('+=' '-=' '*=' '/=' '%=' '<<=' '>>=' '&=' '|=' '^=').
: cc-assign-op?
  tok-kind @ tk-punct = if,
    tok-num @ [char] = =
    tok-num @ bo-compound cc-binop-row 0= 0= or
  else,
    [lit] 0
  then, ;

```

`cc-assign-op?` recognises plain `=` and the ten compound forms.  It
doesn't list the compound forms: each is the `compound` column of a
row in Ch 27 §5's operator table, and a code that some row names
there is a compound assignment.

```forth chunk=expr-assign
\ cc-apply-compound-op ( op -- )  After rdi=LHS-value, rcx=RHS-value: apply
\ the compound-assign op to rdi with the emitter of its row in the operator
\ table.  Consumes op.  Plain '=' must be filtered by the caller.
: cc-apply-compound-op
  bo-compound cc-binop-row                        ( row | 0 )
  dup 0= if,
    [lit] 118 cc-die                              \ not a compound operator
  then,
  bo-emitter + @ execute ;

```

`cc-apply-compound-op` finds the row whose `compound` is the operator
and runs that row's emitter, the same one the binary operator uses:
`+=` emits the `add rdi, rcx` that `+` does.  It runs after `rdi`
holds the left value and `rcx` the right.  Code 118 would mean the
table has no row for the operator, which `cc-assign-op?` has already
ruled out.

```forth chunk=expr-assign
: cc-parse-assign
  cc-parse-ternary
  \ Snapshot lvalue state BEFORE the recursive RHS parse can clobber it.
  cc-last-lvalue-kind @                           ( kind )
  cc-last-ident-slot @                            ( kind slot )
  cc-next-token-keep
  cc-assign-op? if,
    \ Some assignment operator confirmed.  Dispatch on lvalue kind.
    \ Stack layout: ( kind slot ).  lv-local -> store to the slot;
    \ lv-deref / lv-deref-byte -> store through the address in rdi;
    \ lv-value -> not an lvalue (error).
    over lv-local = if,
      \ ---- Local lvalue (lv-local) ---------------------------------------
      \ The LHS load was already emitted by cc-parse-primary; we'll just
      \ overwrite the local slot with the RHS / RHS-folded value.
      nip                                         ( slot )
      tok-num @                                   ( slot op )
      swap >r                                     \ stash slot ( op ; R: slot )
      \ For compound assignment, save current LHS value before parsing RHS.
      dup [char] = = 0= if,
        cc-emit-push-rdi
      then,
      >r                                          \ stash op ( ; R: slot op )
      cc-parse-assign
      cc-emit-materialize                         \ ensure rdi holds a value
      r> r>                                       ( op slot )
      swap                                        ( slot op )
      dup [char] = = if,
        drop                                      ( slot )
      else,
        cc-emit-mov-rcx-rdi                       \ rcx = RHS
        cc-emit-pop-rdi                           \ rdi = LHS (saved earlier)
        cc-apply-compound-op                      \ rdi := rdi <op> rcx
      then,
      cc-emit-store-local                         \ [rbp - 8*(slot+1)] := rdi
      cc-mark-not-lvalue
    else,
      over dup lv-deref = swap lv-deref-byte = or if,
        \ ---- Dereference lvalue (lv-deref / lv-deref-byte) ---------------
        \ rdi already holds the destination address (no load was emitted by
        \ cc-parse-unary).  Plain `=` is supported on derefs; compound
        \ +=/-= would require load-modify-store and is deferred.
        drop                                      ( kind )
        tok-num @ [char] = <> if,
          [lit] 119 cc-die
        then,
        >r                                        \ R: kind
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
        r> lv-deref-byte = if,
          cc-emit-store-byte-via-rcx              \ [rcx] := dil  (1 byte)
        else,
          cc-emit-store-via-rcx                   \ [rcx] := rdi  (8 bytes)
        then,
        cc-mark-not-lvalue
      else,
        \ Not an lvalue at all.
        2drop
        [lit] 120 cc-die
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
4. For `lv-local`, the left value is already in `rdi`.  Plain
   `=` just parses the right side and stores.  A compound operator
   pushes the left value first, then pops it back and folds with
   `cc-apply-compound-op` before the store.
5. For `lv-deref` or `lv-deref-byte`, `rdi` holds the destination
   address.  The code keeps the kind on the return stack, pushes the
   address, parses the right side, swaps the registers so `rdi` holds
   the value and `rcx` the address, and emits a byte store for
   `lv-deref-byte`, a qword store otherwise.  Only plain `=` is
   accepted (code 119 otherwise).
6. `lv-value` is not an lvalue, as in `1 = 2`, and dies with code 120.

**tri.c at this stage.**  tri.c writes `t.rows` on line 14 and reads
it on line 15, in the `for` condition.  With tri.c compiled to
`/tmp/cc-out` (Ch 21), disassemble both:

```sh
for r in 0x2ed:0x312 0x326:0x33a; do
  objdump -D -b binary -m i386:x86-64 -M intel \
      --start-address=${r%:*} --stop-address=${r#*:} /tmp/cc-out | grep '^ '
done
```

```
 2ed:   48 bf c9 04 40 00 00    movabs rdi,0x4004c9
 2f4:   00 00 00 
 2f7:   48 81 c7 00 00 00 00    add    rdi,0x0
 2fe:   57                      push   rdi
 2ff:   48 c7 c7 04 00 00 00    mov    rdi,0x4
 306:   48 89 f9                mov    rcx,rdi
 309:   5f                      pop    rdi
 30a:   57                      push   rdi
 30b:   48 89 cf                mov    rdi,rcx
 30e:   59                      pop    rcx
 30f:   48 89 39                mov    QWORD PTR [rcx],rdi
 326:   48 bf c9 04 40 00 00    movabs rdi,0x4004c9
 32d:   00 00 00 
 330:   48 81 c7 00 00 00 00    add    rdi,0x0
 337:   48 8b 3f                mov    rdi,QWORD PTR [rdi]
```

Both start the same way: the address of `t` (0x4004c9, a placeholder
until `cc-finalize-globals` patched it; Ch 26 §5) plus the offset of `rows`, 0.  On line 14
the `=` arrives while `rdi` is still an address, so this is the
deref path: push the address, evaluate `ROWS` (already the number
4), swap through the stack, store at 0x30f.  On line 15, `t.rows`
is the right operand of `<`, whose materialize turns the same
address into the load at 0x337.  The parser emitted identical code
for `t.rows` both times and decided afterward what it was for.

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

\ Fill in the forward references declared at the top of the file.
' cc-parse-expr   is cc-parse-expr-fwd
' cc-parse-assign is cc-parse-assign-fwd
```

`cc-parse-expr` is the only entry point the rest of the compiler
uses.  It calls `cc-parse-assign` and then materializes, so every
consumer sees a value in `rdi`, never a pending dereference.

It leaves the caller's data stack as it found it, so a statement
can keep its fixups there, or a call its `( callee-id arg-count )`,
across the parse: every parse word above consumes exactly what it
pushes.

The last two lines fill in the deferred words declared in Ch 27 §4,
so `cc-parse-expr-fwd` and `cc-parse-assign-fwd` reach the real
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
   `lv-deref` with `cc-mark-deref`, updates `cc-last-struct-desc` to
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

**Small check:** choose one focused fixture and trace the lvalue,
postfix, assignment, or `sizeof` path it exercises: `tests/cc/G7.c`
(pointer `&`/`*`), `G8.c` (array indexing), `G9a.c` (struct `.`
access), `G9b.c` (struct field arithmetic), `G10c.c` (`sizeof`), or
`G11.c` (postfix `++`/`--` and compound assignment in a dense mix).

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

## Exercises

1. **★ Trace.** Trace what `cc-parse-primary` emits for the literal `'X'`.
   Where does the character value end up?

2. **★★ Trace.** Construct a C expression that chains the postfix
   operators `.`, `->` and `[]` (say, `s.next->arr[1]` with a
   local `struct N s`).  Sketch the lvalue-kind transitions as it
   parses.  Then append `++`: the compile dies with code 98, and
   so do `b[1]++` and `x++--`.  Which lvalue kind does postfix `++` accept, and why
   does every one of these operands fail that test?

3. **★★★ Extend.** Compound assignment of dereference targets (`*p += 1`) is
   *not* supported (§7's deref branch errors on anything but
   plain `=`).  Sketch a patch.  What new state would
   `cc-parse-assign` need to thread?

4. **★★★ Extend.** `cc-parse-sizeof` accepts `sizeof(struct TAG)` and
   `sizeof(typedef-name)` but not `sizeof(*p)`.  Add the
   missing case.  What does the compile-time evaluation look
   like?

5. **★★ Trace.** The function-name-as-value placeholder in §4 is threaded
   onto a linked list via `cc-sym-addr-fixups`.  Trace how Ch 31's `cc-parse-function`
   patches that list when the definition arrives.  How is the
   list head set to 0 again?

## After this chapter

The compiler can lower the floor and tail of expressions: primary
(literals, identifiers, calls, postfix `.`/`->`/`[]`/`++`/`--`),
unary (`*`, `&`, prefix `++`/`--`, `sizeof`, `!`, `-`, `~`), the
ternary `?:`, and the assignment family, all with lvalue tracking
that defers each load until the consumer decides between reading
and writing.

You can read `cc-parse-primary`'s postfix chain, explain the four
lvalue kinds and when `cc-emit-materialize` fires, and follow how
`p[i] = c;` reaches the right byte-width store without a separate
codegen path.

All of it assumes the names are already known: the parser above
looked up `t`'s address, `rows`'s offset and `w`'s frame slot.
Something has to put those rows in the symbol table before any
expression uses them, and that is Ch 29's declaration parser.

## Takeaways

- An expression's value in `rdi` is a temp, a loaded local, or a
  pending-deref address (qword or byte), and `cc-emit-materialize`
  turns a pending deref into a load only when a consumer needs the
  value.
- Every C expression bottoms out in `cc-parse-primary`, which
  dispatches on the token kind, resolves the symbol by storage and
  type, and then loops over postfix `.`, `->`, `[]`, `++`, and `--`.
- Assignment snapshots `( kind slot )` on the data stack before
  parsing its right side, so nested assignments can't overwrite the
  left side's lvalue state.

Next: Chapter 29 — Declarations: Types, Structs, Locals.

