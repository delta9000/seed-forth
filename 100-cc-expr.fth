\ 100-cc-expr.fth — recursive-descent expression parser for the C subset.
\ Emits code that leaves the expression's value in rdi.  Uses 090-cc-emit.fth's
\ instruction encoders.
\
\ Expression grammar, loosest-binding first (one cc-parse-LEVEL word each):
\   expr    := assign                                 \ then materialize
\   assign  := ternary (ASSIGN-OP assign)?            \ = += -= *= /= %= <<= >>= &= |= ^=
\   ternary := log-or ('?' assign ':' assign)?
\   log-or  := log-and ('||' log-and)*
\   log-and := bit-or ('&&' bit-or)*
\   bit-or  := bit-xor ('|' bit-xor)*
\   bit-xor := bit-and ('^' bit-and)*
\   bit-and := eq ('&' eq)*
\   eq      := rel (('=='|'!=') rel)*
\   rel     := shift (('<'|'<='|'>'|'>=') shift)*
\   shift   := add (('<<'|'>>') add)*
\   add     := mul (('+'|'-') mul)*
\   mul     := unary (('*'|'/'|'%') unary)*
\   unary   := ('*'|'&'|'-'|'!'|'~'|'++'|'--') unary | 'sizeof' '(' ... ')'
\            | primary
\   primary := (NUMBER | CHAR | STRING | IDENT | IDENT '(' args ')'
\               | IDENT '[' expr ']' | '(' expr ')')
\              ('.' IDENT | '->' IDENT | '[' expr ']' | '++' | '--')*
\
\ Tokens come from the lexer's interface (050-cc-lex.fth): cc-next-token-keep
\ reads the next one, and cc-putback-token hands the current one back when a
\ parser has read one token too many.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 090-cc-emit.fth.

\ ===========================================================================
\ Forward reference for recursive expr (used by '(' expr ')' in primary).
\ ===========================================================================

variable cc-parse-expr-vec                        \ xt of top-level expr parser

: cc-parse-expr-tramp
  cc-parse-expr-vec @ execute ;

\ cc-parse-assign is defined AFTER cc-parse-ternary (mutual recursion:
\ ternary's arms parse via cc-parse-assign for right-associativity).  Route
\ ternary's recursive calls through this vec so the binding resolves at
\ ternary-execution time, not at compile time.
variable cc-parse-assign-vec                      \ xt of cc-parse-assign

: cc-parse-assign-tramp
  cc-parse-assign-vec @ execute ;

\ ===========================================================================
\ Forward reference for function-call codegen.  cc-parse-call is defined in
\ 110-cc-decl.fth, which loads after this file, so cc-parse-primary reaches it
\ through this vector once it has spotted `IDENT (`.  The callee consumes the
\ '(' (already peeked but not consumed), parses comma-separated arg
\ expressions, emits the SYS-V argument-passing prologue and the call.
\ ===========================================================================

variable cc-parse-call-vec                        \ xt of cc-parse-call

\ cc-parse-call-tramp ( id -- )  Stack: function symbol-id; consumes it.
: cc-parse-call-tramp
  cc-parse-call-vec @ execute ;

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

\ ===========================================================================
\ cc-parse-primary
\ ===========================================================================

\ Each failure below dies through cc-die (020-cc-arena.fth) with its own
\ code; Appendix G of the book lists them.

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
      cc-here-vaddr                               ( fixup-off str-vaddr )
      swap                                        ( str-vaddr fixup-off )
      \ Copy decoded string bytes (with NUL terminator).
      tok-str-addr @ tok-str-len @ cc-emit-string-bytes
      \ Patch the jmp's rel32 to land here (right after the string bytes).
      cc-patch-rel32-to-here                      ( str-vaddr )
      \ Emit the movabs rdi, str-vaddr.
      cc-emit-movabs-rdi-imm64
    else,
      tok-kind @ tk-ident = if,
      \ Identifier reference.  Could be a local variable, or a function call
      \ if the next token is '('.  Look up the name first.
      tok-str-addr @ tok-str-len @ cc-sym-find
      \ -1 means "not found" (cc-sym-find's result encoding).
      dup 0< if,
        drop
        [lit] 93 cc-die
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
      tok-kind @ tk-punct = tok-num @ lparen = and if,
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
            [lit] 94 cc-die
          then,
        then,
        \ Hand the id off to cc-parse-call (in 110-cc-decl.fth via trampoline).
        \ It will consume the '(' (already peeked), parse args, emit the
        \ call, and leave the return value in rdi.  The result is not an
        \ lvalue.
        cc-parse-call-tramp
        cc-mark-not-lvalue
      else,
        tok-kind @ tk-punct = tok-num @ [char] [ = and if,
          \ Array index.  '[' has been read into tok-*; cc-parse-array-
          \ index consumes through ']'.  The id is on TOS.
          cc-parse-array-index
        else,
          \ Variable reference.  Put back the peeked token.
          cc-putback-token
          \ Function name as rvalue — `op = square;`.  Load the function's
          \ absolute vaddr into rdi via movabs.  Result is not an lvalue.
          \ When val == 0 the function is still a forward prototype; emit a
          \ 10-byte movabs placeholder and thread the imm64 patch-offset onto
          \ its cc-sym-addr-fixups list so cc-parse-function can patch it
          \ once the real vaddr is known.  Without this, M2-Planet code like
          \ `common_recursion(expression)` (where `expression` is forward-
          \ declared) loads 0 into rdi and crashes at the indirect call.
          dup cc-sym-kind-of sk-func = if,
            dup cc-sym-val-of [lit] 0 = if,
              cc-emit-movabs-rdi-imm64-placeholder    ( id patch-off )
              swap cc-sym-addr-fixups                 ( patch-off list-cell )
              cc-add-fixup-to-list
            else,
              cc-sym-val-of cc-emit-movabs-rdi-imm64
            then,
            cc-mark-not-lvalue
          else,
          \ File-scope global.  Emit movabs rdi, <vaddr-placeholder>
          \ with a deferred fixup.  Scalar globals are deref-pending lvalues
          \ (lv-deref); array globals decay to their address (lv-value).
          \
          \ The type decides which extra fact the symbol carries (070):
          \   ty-struct base -> cc-sym-struct-desc-of (NOT an array length).
          \   any other      -> cc-sym-array-len-of (>0 for arrays, 0 otherwise).
          dup cc-sym-kind-of sk-global = if,
            dup cc-sym-type-of ty-base ty-struct = if,
              \ Struct or struct-pointer global.  Treat like a scalar (deref-
              \ pending lvalue) so assignment works; the descriptor is recorded
              \ below for any postfix '.' / '->'.
              dup cc-sym-val-of cc-emit-global-ref
              [lit] 0 cc-mark-deref
              cc-sym-struct-desc-of cc-last-struct-desc !
            else,
              dup cc-sym-array-len-of [lit] 0 > if,
                \ Global array: rdi := &globals[slot]; not an lvalue.
                cc-sym-val-of cc-emit-global-ref
                cc-mark-not-lvalue
              else,
                \ Global scalar: rdi := &globals[slot]; mark deref-pending so
                \ consumer either loads (rvalue) or stores via that address
                \ (assignment's deref path).  Record the scalar's type (across
                \ the mark, which clears it) so a following unary '*' knows
                \ whether this is a char* (1-byte deref) or a wider pointer.
                dup cc-sym-type-of >r
                cc-sym-val-of cc-emit-global-ref
                [lit] 0 cc-mark-deref
                r> cc-last-expr-type !
              then,
            then,
          else,
          dup cc-sym-kind-of sk-local <> if,
            drop
            [lit] 95 cc-die
          then,
          \ Dispatch on the local's type — struct vs struct-pointer vs
          \ array vs scalar.
          dup cc-sym-type-of ty-base ty-struct = if,
            \ Struct-typed local.
            dup cc-sym-type-of ty-ptr [lit] 0 = if,
              \ struct T x;  Emit lea on the first-element slot so rdi holds
              \ the address of the struct.  Then record the descriptor for any
              \ following '.field'.  This is NOT a normal lvalue (you can't
              \ assign to a whole struct); '.field' will mark a deref.
              dup cc-sym-struct-desc-of              \ descriptor pointer
              swap cc-sym-val-of                     \ slot of field 0 (deepest)
              cc-emit-lea-rdi-local
              cc-mark-not-lvalue
              cc-last-struct-desc !
            else,
              \ struct T* p;  Load the pointer value; treat as an lvalue local
              \ (lv-local) so plain `p = q;` still works, AND record descriptor
              \ for '->field'.
              dup cc-sym-struct-desc-of              \ descriptor pointer
              swap cc-sym-val-of                     \ slot index
              dup cc-mark-local-lvalue
              cc-emit-load-local
              cc-last-struct-desc !
            then,
          else,
            \ If this local is an array, decay to &arr[0] — emit lea, not
            \ load.  The result is a pointer value (not an lvalue).
            dup cc-sym-array-len-of [lit] 0 > if,
              cc-sym-val-of                           \ slot of arr[0]
              cc-emit-lea-rdi-local
              cc-mark-not-lvalue
            else,
              \ Plain scalar local.  Save its type across the mark (which
              \ clears cc-last-expr-type) so a following unary '*' can tell a
              \ char* (1-byte deref) from a wider pointer.
              dup cc-sym-type-of >r
              cc-sym-val-of                           \ slot index
              dup cc-mark-local-lvalue                \ lv-local, remember slot
              cc-emit-load-local
              r> cc-last-expr-type !
            then,
          then,
          then,                                       \ end of sk-global if/else
          then,                                       \ end of sk-func-name-rvalue if/else
        then,
      then,
      then,                                           \ end of sk-enum if/else
    else,
      tok-kind @ tk-punct = tok-num @ lparen = and if,
        \ '(' expr ')' — the parenthesised expr is not an lvalue (cc-parse-
        \ primary inside the recursive call will set/clear cc-last-ident-slot;
        \ we re-clear it here so e.g. `(x) = 1` doesn't get treated as lvalue).
        cc-parse-expr-tramp
        cc-mark-not-lvalue
        cc-next-token-keep
        tok-kind @ tk-punct <> tok-num @ [char] ) <> or if,
          [lit] 96 cc-die
        then,
      else,
        [lit] 97 cc-die
      then,
    then,
    then,
    then,
  then,
  \ Handle zero or more postfix '.field' / '->field' applied to whatever
  \ value cc-parse-primary just produced.  Both '.' / '->' ops require
  \ cc-last-struct-desc to be non-zero (set by the variable-reference branch
  \ for struct locals or struct-pointer locals).  Also handles postfix '++' / '--'
  \ to the same loop — they apply to simple local lvalues (lv-local in
  \ cc-last-ident-slot) and bump the slot in place while leaving the OLD value
  \ in rdi.
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = if,
      tok-num @ [char] . =
      tok-num @ pt-arrow         = or
      tok-num @ pt-plus-plus     = or
      tok-num @ pt-minus-minus   = or
      tok-num @ [char] [ =       or            \ '[' postfix subscript
    else,
      [lit] 0
    then,
  while,
    tok-num @                                       ( op-code )
    dup pt-plus-plus = over pt-minus-minus = or if,
      \ Postfix '++' / '--' on a simple local.  cc-parse-primary already
      \ loaded the old value into rdi and recorded the slot in
      \ cc-last-ident-slot (lv-local).  Bump the slot in place; rdi keeps the
      \ old value.  Result is not an lvalue.
      cc-last-lvalue-kind @ lv-local <> if,
        drop
        [lit] 98 cc-die
      then,
      pt-plus-plus = if,
        cc-last-ident-slot @ cc-emit-inc-mem-local
      else,
        cc-last-ident-slot @ cc-emit-dec-mem-local
      then,
      cc-mark-not-lvalue
    else,
    dup [char] [ = if,
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
      \ Keep the subscripted value's type on the rstack: the index parse
      \ overwrites cc-last-expr-type.
      cc-emit-materialize
      cc-last-expr-type @ >r                         \ R: pre-subscript ty
      cc-emit-push-rdi
      cc-parse-expr-tramp
      r@ cc-char-ptr? 0= if,
        cc-emit-shl-rdi-3                            \ char*: byte offset, no shift
      then,
      cc-emit-pop-rcx
      cc-emit-add-rdi-rcx
      cc-next-token-keep
      tok-kind @ tk-punct <> tok-num @ [char] ] <> or if,
        [lit] 99 cc-die
      then,
      \ Mark deref: byte-width iff we just subscripted a char*.  The
      \ post-step expression type drops one level of indirection — record
      \ it so chained `[i][j]` (char**) and following postfix ops can see
      \ the right type.
      r@ cc-char-ptr? cc-mark-deref
      r@ ty-ptr [lit] 0 > if,
        r@ ty-base r@ ty-ptr 1- ty-make cc-last-expr-type !
      then,
      r> drop
    else,
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
      cc-find-field                                 ( offset )
      cc-emit-add-rdi-imm32
      [lit] 0 cc-mark-deref
      \ Propagate the field's pointee descriptor so chained '->' / '.' (e.g.
      \ `head->next->prev`) can resolve subsequent field lookups.  Stays 0
      \ when the field isn't a struct pointer.
      cc-ff-result-desc @ cc-last-struct-desc !
      \ Record the field's type so a following postfix '[' can detect
      \ char-pointer subscripts (e.g. `head->s[0]`) and emit byte stride/load
      \ instead of qword.  cc-mark-deref cleared this slot above, so
      \ set it after the mark.
      cc-ff-result-type @ cc-last-expr-type !
    then,
    then,
  repeat,
  cc-putback-token ;

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

variable cc-parse-unary-vec                       \ xt of cc-parse-unary

: cc-parse-unary-tramp
  cc-parse-unary-vec @ execute ;

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

: cc-parse-unary
  cc-next-token-keep
  tok-kind @ tk-kw = tok-kw-id @ kw-sizeof = and if,
    \ sizeof(TYPE).  The `sizeof` keyword is the current token; we just
    \ leave it as "consumed" (no putback) and dispatch into cc-parse-sizeof.
    cc-parse-sizeof
  else,
    tok-kind @ tk-punct = tok-num @ [char] & = and if,
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
    cc-mark-not-lvalue                            \ &x is a value, not an lvalue
  else,
    tok-kind @ tk-punct = tok-num @ [char] * = and if,
      \ '*' = dereference.  A char* operand (ty-char, ptr-depth 1) derefs to a
      \ single byte; int*, T**, etc. deref to a qword.  The operand's type sits
      \ in cc-last-expr-type when it came from a scalar variable (recorded in
      \ cc-parse-primary), so `*p = c` on a char* emits a 1-byte store instead
      \ of clobbering 8 bytes.  The mark clears the type; keep it on the stack.
      cc-parse-unary-tramp
      cc-emit-materialize                          \ operand is now a value (an address)
      cc-last-expr-type @                          ( ty ; 0 if untracked )
      dup cc-char-ptr? cc-mark-deref               \ defer the load; *char* is 1 byte
      dup ty-ptr [lit] 0 > if,                     \ record pointee type for chained ops
        dup ty-base swap ty-ptr 1- ty-make cc-last-expr-type !
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
          tok-kind @ tk-punct = tok-num @ [char] - = and if,
            \ Unary '-'.
            cc-parse-unary-tramp
            cc-emit-materialize
            cc-emit-neg-rdi
            cc-mark-not-lvalue
          else,
            tok-kind @ tk-punct = tok-num @ [char] ! = and if,
              \ Unary '!'.  rdi := (rdi == 0).
              cc-parse-unary-tramp
              cc-emit-materialize
              cc-emit-not-zero-flag
              cc-mark-not-lvalue
            else,
              tok-kind @ tk-punct = tok-num @ [char] ~ = and if,
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

\ ===========================================================================
\ cc-parse-mul: unary (('*'|'/'|'%') unary)*
\ ===========================================================================

\ cc-mul-op? ( -- f )  After cc-next-token-keep, returns -1 if the current
\ token is one of *, /, %.
: cc-mul-op?
  tok-kind @ tk-punct = if,
    tok-num @ [char] * =
    tok-num @ [char] / = or
    tok-num @ [char] % = or
  else,
    [lit] 0
  then, ;

\ The op byte is kept on the data stack across the recursive call to
\ cc-parse-primary so nested operator parsing (via parenthesised exprs)
\ can't clobber a shared global.  cc-parse-primary preserves the data
\ stack (0-in / 0-out), so the op survives across the call.

: cc-parse-mul
  cc-parse-unary                                  \ rdi = first operand (may be pending-deref)
  begin,
    cc-next-token-keep
    cc-mul-op?
  while,
    cc-emit-materialize                           \ left must be a value before push
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi                              \ save left
    cc-parse-unary                                \ rdi = right (may be pending-deref)
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi                           \ rcx = right
    cc-emit-pop-rdi                               \ rdi = left
    r>                                            ( op )
    dup [char] * = if,
      drop cc-emit-imul-rdi-rcx
    else,
      [char] / = if,
        cc-emit-idiv-quotient
      else,
        cc-emit-idiv-remainder
      then,
    then,
    cc-mark-not-lvalue                            \ result is not an lvalue
  repeat,
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-add: mul (('+'|'-') mul)*
\ ===========================================================================

: cc-add-op?
  tok-kind @ tk-punct = if,
    tok-num @ [char] + =
    tok-num @ [char] - = or
  else,
    [lit] 0
  then, ;

: cc-parse-add
  cc-parse-mul
  begin,
    cc-next-token-keep
    cc-add-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-mul
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    [char] + = if,
      cc-emit-add-rdi-rcx
    else,
      cc-emit-sub-rdi-rcx
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ cc-parse-shift: add (('<<' | '>>') add)*
\ ===========================================================================
\ C precedence: shift is BETWEEN relational and additive (binds tighter than
\ relational, looser than additive).  Variable-count shifts use rcx (CL).

: cc-shift-op?
  tok-kind @ tk-punct = if,
    tok-num @ pt-shl =
    tok-num @ pt-shr = or
  else,
    [lit] 0
  then, ;

: cc-parse-shift
  cc-parse-add
  begin,
    cc-next-token-keep
    cc-shift-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-add
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    \ rdi=left, rcx=right (low byte cl = count).
    pt-shl = if,
      cc-emit-shl-rdi-cl
    else,
      cc-emit-sar-rdi-cl                          \ '>>' is arithmetic (signed)
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ cc-parse-rel: shift (('<' | '<=' | '>' | '>=') shift)*
\ ===========================================================================
\ Punct codes: '<'=60, '>'=62, pt-le=258, pt-ge=259.

: cc-rel-op?
  tok-kind @ tk-punct = if,
    tok-num @ [char] < =
    tok-num @ [char] > = or
    tok-num @ pt-le      = or
    tok-num @ pt-ge      = or
  else,
    [lit] 0
  then, ;

: cc-parse-rel
  cc-parse-shift
  begin,
    cc-next-token-keep
    cc-rel-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-shift
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    \ Now rdi=left, rcx=right.  Dispatch on op code.
    dup [char] < = if,
      drop cc-emit-cmp-lt
    else,
      dup [char] > = if,
        drop cc-emit-cmp-gt
      else,
        pt-le = if,
          cc-emit-cmp-le
        else,
          cc-emit-cmp-ge
        then,
      then,
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ cc-parse-eq: rel (('==' | '!=') rel)*
\ ===========================================================================

: cc-eq-op?
  tok-kind @ tk-punct = if,
    tok-num @ pt-eq-eq   =
    tok-num @ pt-bang-eq = or
  else,
    [lit] 0
  then, ;

: cc-parse-eq
  cc-parse-rel
  begin,
    cc-next-token-keep
    cc-eq-op?
  while,
    cc-emit-materialize                           \ left must be a value
    tok-num @ >r                                  ( ; R: op )
    cc-emit-push-rdi
    cc-parse-rel
    cc-emit-materialize                           \ right must be a value
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    r>                                            ( op )
    pt-eq-eq = if,
      cc-emit-cmp-eq
    else,
      cc-emit-cmp-ne
    then,
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ Bitwise AND / XOR / OR — three layers, each above the next.
\ ===========================================================================
\ Precedence (high to low among these):
\   eq  >  bit-and (&)  >  bit-xor (^)  >  bit-or (|)
\ So cc-parse-bit-and folds over cc-parse-eq; cc-parse-bit-xor over bit-and;
\ cc-parse-bit-or over bit-xor.  Each handles a single punct char.
\
\ Note that '&' here is the BINARY (infix) bitwise-and.  The unary '&'
\ (address-of) is handled in cc-parse-unary at operand position — operator
\ position vs operand position disambiguates the two.

: cc-parse-bit-and
  cc-parse-eq
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] & = and
  while,
    cc-emit-materialize
    cc-emit-push-rdi
    cc-parse-eq
    cc-emit-materialize
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    cc-emit-and-rdi-rcx
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

: cc-parse-bit-xor
  cc-parse-bit-and
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] ^ = and
  while,
    cc-emit-materialize
    cc-emit-push-rdi
    cc-parse-bit-and
    cc-emit-materialize
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    cc-emit-xor-rdi-rcx
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

: cc-parse-bit-or
  cc-parse-bit-xor
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] | = and
  while,
    cc-emit-materialize
    cc-emit-push-rdi
    cc-parse-bit-xor
    cc-emit-materialize
    cc-emit-mov-rcx-rdi
    cc-emit-pop-rdi
    cc-emit-or-rdi-rcx
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ Short-circuit logical && and || — produce 1 or 0 (not the operand).
\ ===========================================================================
\ For `a && b`:
\   eval a; if zero, skip b and produce 0; else eval b; if zero, produce 0;
\   else produce 1.
\
\ Codegen sketch (with three rel32 fixups stashed on rstack):
\   <eval a>
\   test rdi,rdi
\   jz   .false_LHS
\   <eval b>
\   test rdi,rdi
\   jz   .false_RHS
\   mov rdi, 1
\   jmp  .end
\ .false_LHS:
\ .false_RHS:
\   mov rdi, 0
\ .end:
\
\ We push the three fixups onto rstack so the data stack stays clear for the
\ nested parse calls and any pending operator codes.

: cc-parse-log-and
  cc-parse-bit-or
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ pt-and-and = and
  while,
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jz-rel32-placeholder >r               \ R: fixup-false-LHS
    cc-parse-bit-or
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jz-rel32-placeholder >r               \ R: f-LHS f-RHS
    [lit] 1 cc-emit-mov-rdi-imm32
    cc-emit-jmp-rel32-placeholder >r              \ R: f-LHS f-RHS f-end
    \ False-target lands here for both fixups.
    r> r>                                         ( f-end f-RHS ; R: f-LHS )
    cc-patch-rel32-to-here                        \ patch f-RHS
    r>                                            ( f-end f-LHS )
    cc-patch-rel32-to-here                        \ patch f-LHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

: cc-parse-log-or
  cc-parse-log-and
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ pt-or-or = and
  while,
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jnz-rel32-placeholder >r              \ R: fixup-true-LHS
    cc-parse-log-and
    cc-emit-materialize
    cc-emit-test-rdi
    cc-emit-jnz-rel32-placeholder >r              \ R: t-LHS t-RHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-emit-jmp-rel32-placeholder >r              \ R: t-LHS t-RHS f-end
    \ True-target lands here for both fixups.
    r> r>                                         ( f-end t-RHS ; R: t-LHS )
    cc-patch-rel32-to-here
    r>                                            ( f-end t-LHS )
    cc-patch-rel32-to-here
    [lit] 1 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  repeat,
  cc-putback-token ;

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
    cc-parse-assign-tramp                         \ then-arm (right-assoc)
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
    cc-parse-assign-tramp                         \ else-arm
    cc-emit-materialize
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-not-lvalue
  else,
    cc-putback-token
  then, ;

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
    tok-num @ [char] =      =
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
                      [lit] 118 cc-die
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

\ Wire the trampolines.
' cc-parse-expr   cc-parse-expr-vec   !
' cc-parse-assign cc-parse-assign-vec !
