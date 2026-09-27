\ 110-cc-decl.fth — declaration parser for the C-subset compiler.
\
\ Parses base types, struct definitions, and local declarations (scalars,
\ pointers, arrays, function pointers, struct locals) for the C subset needed
\ to compile M2-Planet, plus the `return` statement.  The rest of the parser
\ follows in load order: statements in 112-cc-stmt.fth, function definitions
\ in 114-cc-func.fth, and file-scope forms, the entry stub, and the top-level
\ driver in 116-cc-prog.fth.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 080-cc-elf.fth, 090-cc-emit.fth, 100-cc-expr.fth.

\ ===========================================================================
\ Bookkeeping
\ ===========================================================================

variable cc-main-vaddr                            \ vaddr where main starts
variable cc-call-main-patch                       \ file-offset of rel32 to patch
variable cc-fn-local-count                        \ # locals in current function

\ Every function gets the same frame: cc-frame-slots 8-byte slots below rbp,
\ shared by its parameters and every local in every block of its body (a
\ slot is never reused).  cc-fn-add-slots ( n -- ) claims the next n; the
\ one that would pass the frame's end dies with code 162 instead of
\ silently overlapping the stack below it.
[lit] 32 constant cc-frame-slots
: cc-fn-add-slots
  dup cc-fn-local-count @ + cc-frame-slots [lit] 162 cc-check-cap
  cc-fn-local-count +! ;

\ cc-pending-struct-desc is set by cc-parse-base-type when it parses a
\ `struct TAG` base, and consumed by cc-parse-decl / cc-parse-param-list when
\ they record the symbol-table entry (so the struct descriptor pointer ends
\ up in the symbol's struct-desc cell).  For non-struct types it stays at 0.
variable cc-pending-struct-desc

\ ===========================================================================
\ Token-expectation helpers
\ ===========================================================================

\ Each error path dies through cc-die with its own code, so a failure names
\ its site.  This file's codes are 140..169; 112, 114 and 116 have
\ 170..179, 180..189 and 190..219 (Appendix G).

\ cc-expect-kw-id ( kw-id -- )  Consume one token; abort if not the given kw.
: cc-expect-kw-id
  cc-next-token-keep
  tok-kind @ tk-kw <> if,
    drop
    [lit] 140 cc-die
  then,
  tok-kw-id @ <> if,
    [lit] 141 cc-die
  then, ;

\ cc-expect-punct-c ( char -- )  Consume one token; abort if not that punct.
: cc-expect-punct-c
  cc-next-token-keep
  tok-kind @ tk-punct <> if,
    drop
    [lit] 142 cc-die
  then,
  tok-num @ <> if,
    [lit] 143 cc-die
  then, ;

\ cc-expect-ident ( -- )  Consume one token; abort if not tk-ident.
: cc-expect-ident
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 144 cc-die
  then, ;

\ ===========================================================================
\ Statement parsing
\ ===========================================================================

\ cc-qualifier? ( -- f )  True if the current token is a type qualifier
\ (const / volatile / restrict).  They change nothing in this subset, so
\ every place that reads a type skips them.
: cc-qualifier?
  tok-kind @ tk-kw =
    tok-kw-id @ kw-const    =
    tok-kw-id @ kw-volatile = or
    tok-kw-id @ kw-restrict = or
  and ;

\ cc-skip-qualifiers ( -- )  Read past any qualifiers; the first token that
\ isn't one is left pending.
: cc-skip-qualifiers
  begin,
    cc-next-token-keep cc-qualifier?
  while,
  repeat,
  cc-putback-token ;

\ cc-count-stars ( -- depth )  After consuming a base type (e.g. 'int'), peek
\ zero or more '*' tokens and return the resulting pointer depth.  A
\ qualifier may follow each '*' (`char * const msg`).  Leaves the first
\ other token pending for the caller.
: cc-count-stars                                  ( -- depth )
  [lit] 0
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
  while,
    1+ cc-skip-qualifiers
  repeat,
  cc-putback-token ;

\ Skip storage-class specifiers (static / extern / auto / register) and
\ type qualifiers (const / volatile / restrict).  Reads tokens via
\ cc-next-token-keep; whenever one of these keywords is seen, it's consumed
\ and the loop continues.  When a non-qualifier is encountered it is put back
\ so the caller sees it as the next token.
\
\ Only `static` matters: cc-decl-static records whether it was seen, and a
\ local declared static gets file-scope storage instead of a frame slot
\ (cc-parse-local-declarator).  The rest are no-ops.
variable cc-decl-static

: cc-skip-storage-quals
  [lit] 0 cc-decl-static !
  begin,
    cc-next-token-keep
    kw-static cc-tok-kw? if, true cc-decl-static ! then,
    tok-kind @ tk-kw =
      tok-kw-id @ kw-static    =
      tok-kw-id @ kw-extern    = or
      tok-kw-id @ kw-auto      = or
      tok-kw-id @ kw-register  = or
      tok-kw-id @ kw-const     = or
      tok-kw-id @ kw-volatile  = or
      tok-kw-id @ kw-restrict  = or
    and
  while,
    \ already consumed; just loop
  repeat,
  cc-putback-token ;

\ cc-skip-enum-tag ( -- )  The current token is `enum` used as a type
\ (`enum BINDING kind`): consume the tag.  An enum's values are ints, so
\ the type is int.
: cc-skip-enum-tag
  cc-next-token-keep
  tok-kind @ tk-ident <> if, cc-putback-token then, ;

\ ===========================================================================
\ Struct definition and base-type parsing.
\ ===========================================================================

\ Scratch globals used while building one struct descriptor.  cc-parse-struct-
\ def runs single-threaded (no recursion / nested struct defs), so a
\ single set of globals is enough — they're saved here and read back when the
\ field loop body needs them.
variable cc-sd-build-desc                         \ descriptor under construction
variable cc-sd-build-fname-a
variable cc-sd-build-fname-u
variable cc-sd-build-field-ty
variable cc-sd-build-field-desc                   \ pointee desc for struct-ptr fields (0 if none)

\ cc-sd-append-field ( -- )  Append the field whose name is in cc-sd-build-
\ fname-{a,u}, type in cc-sd-build-field-ty, pointee descriptor in
\ cc-sd-build-field-desc, to the descriptor in cc-sd-build-desc.  Assigns
\ offset = total-size BEFORE this field, then bumps total-size by 8.  This
\ subset stores every field in an 8-byte slot.  Increments field-count.
: cc-sd-append-field                              ( -- )
  cc-sd-build-desc @ cc-sd-field-count            ( i )
  cc-sd-build-desc @ swap cc-sd-field-rec         ( rec )
  cc-sd-build-fname-a @ over cc-sf-set-name-addr
  cc-sd-build-fname-u @ over cc-sf-set-name-len
  cc-sd-build-field-ty @ over cc-sf-set-type
  cc-sd-build-field-desc @ over cc-sf-set-desc
  cc-sd-build-desc @ cc-sd-total-size swap cc-sf-set-offset
  \ Increment field-count and total-size by 8.
  cc-sd-build-desc @ cc-sd-field-count 1+
  cc-sd-build-desc @ cc-sd-set-field-count
  cc-sd-build-desc @ cc-sd-total-size [lit] 8 +
  cc-sd-build-desc @ cc-sd-set-total-size ;

\ cc-parse-struct-def ( -- )  Called with the 'struct' keyword ALREADY consumed
\ (it's the current token).  Handles ONLY the definition form:
\
\    struct TAG '{' (field-decl)* '}' ';'
\
\ Registers TAG in the symbol table as sk-struct with val = descriptor pointer.
\ Descriptor layout: see 060-cc-types.fth.
\ cc-lookup-struct-tag ( -- desc )  Reads an IDENT token (must be the current
\ position; will be advanced past), looks it up as sk-struct in the symbol
\ table, returns the descriptor pointer.  Aborts on lookup failure.
: cc-lookup-struct-tag                            ( -- desc )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 145 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id-or-neg1 )
  dup 0< if,
    drop
    [lit] 146 cc-die
  then,
  dup cc-sym-kind-of sk-struct <> if,
    drop
    [lit] 147 cc-die
  then,
  cc-sym-val-of ;                                  \ descriptor pointer

\ cc-lookup-struct-tag-soft ( -- desc-or-0 )  Like cc-lookup-struct-tag, but
\ returns 0 if the tag isn't found or isn't registered as a struct.  Lets the
\ parser tolerate opaque/incomplete struct references in headers that declare
\ but don't define the struct (e.g. cc_globals.c's `struct type* foo;`).
: cc-lookup-struct-tag-soft                       ( -- desc-or-0 )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 148 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id-or-neg1 )
  dup 0< if,
    drop [lit] 0
  else,
    dup cc-sym-kind-of sk-struct <> if,
      drop [lit] 0
    else,
      cc-sym-val-of
    then,
  then, ;

: cc-parse-struct-def                             ( -- )
  \ Expect IDENT tag.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 149 cc-die
  then,
  \ Snapshot tag bytes on data stack (rstack would be clobbered by ';' etc.).
  tok-str-addr @ tok-str-len @                    ( tag-addr tag-len )
  \ Expect '{'.
  [char] { cc-expect-punct-c

  \ Allocate descriptor: 16-byte header + room for up to 16 fields = 656 bytes.
  cc-sd-bytes cc-alloc                            ( tag-addr tag-len desc )
  dup cc-sd-build-desc !
  [lit] 0 over cc-sd-set-total-size
  [lit] 0 over cc-sd-set-field-count
  drop                                            ( tag-addr tag-len )

  \ Pre-register the struct tag (with the still-empty descriptor) BEFORE
  \ parsing the body, so self-referential field types `struct T* next` can
  \ resolve their own tag.  We snapshot tag-addr/tag-len off-stack via 2>r so
  \ the symbol-add doesn't disturb the stack layout the loop expects.
  over over                                       ( tag-a tag-u tag-a tag-u )
  sk-struct
  [lit] 0
  cc-sd-build-desc @
  cc-sym-add drop                                 ( tag-a tag-u )

  \ Field-parsing loop.  Each iteration parses `T '*'* IDENT ;` where T is
  \ one of: int / char / void / struct TAG / IDENT (typedef-name).  All
  \ fields are 8 bytes in our codegen, so the *type* is mostly cosmetic;
  \ what matters is correctness of name+offset.
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    cc-putback-token
    \ Parse base type.  Default the pointee-descriptor to 0; the struct-tag
    \ branch overrides when the field is `struct TAG ...`.
    [lit] 0 cc-sd-build-field-desc !
    cc-skip-qualifiers
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-int     = if, ty-int  cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-char    = if, ty-char cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-void    = if, ty-void cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-enum    = if,
        cc-skip-enum-tag ty-int cc-sd-build-field-ty !
      else,
      tok-kw-id @ kw-struct  = if,
        \ Look up the tag's descriptor (soft — self-referential `struct T*
        \ next` inside `struct T {...}` works because cc-parse-struct-def
        \ pre-registers the tag with a still-empty descriptor before parsing
        \ fields, and forward refs return 0).  Stored in the field record so
        \ chained '->' can propagate the type.
        cc-lookup-struct-tag-soft cc-sd-build-field-desc !
        ty-struct cc-sd-build-field-ty !
      else,
        [lit] 150 cc-die
      then, then, then, then, then,
    else,
      \ tk-ident — treat as typedef-name used as a type.  Record as int
      \ (we only care about the storage size = 8).
      tok-kind @ tk-ident <> if,
        [lit] 151 cc-die
      then,
      ty-int cc-sd-build-field-ty !
    then,

    cc-count-stars                                ( ... ptr-depth )
    \ Re-pack the type word with the ptr-depth.
    cc-sd-build-field-ty @ swap ty-make cc-sd-build-field-ty !

    \ Read field name.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 152 cc-die
    then,
    tok-str-addr @ cc-sd-build-fname-a !
    tok-str-len  @ cc-sd-build-fname-u !
    [char] ; cc-expect-punct-c
    cc-sd-append-field
  repeat,
  \ '}' was the loop test; we consumed it via cc-next-token-keep but DIDN'T
  \ putback this time (the test went 0=, so we entered the exit path).
  \ Expect ';' after '}'.
  [char] ; cc-expect-punct-c
  drop drop ;                                     \ discard tag-a tag-u

\ ===========================================================================
\ Function-pointer declaration parsing.
\ ===========================================================================
\ A function-pointer decl has the shape:
\
\    RETURN_TYPE '(' '*' NAME ')' '(' PARAM_TYPES ')' (= expr)? ';'
\
\ Detection: after the base type is parsed, we need 2-token lookahead to
\ distinguish `int (*fp)(int);` from `int x;` and `int *p;`.  Putback holds
\ only one token, so we mark the lexer state in cc-peek-mark (050-cc-lex.fth),
\ read ahead, and reset to the mark.

\ cc-peek-fnptr? ( -- f )  Look ahead 2 tokens; -1 iff we see '(' then '*'.
\ The first may be a token put back (the mark saves the putback flag too).
\ Always restores the lexer state so the caller resumes at the original
\ position regardless of the result.
: cc-peek-fnptr?
  cc-peek-mark cc-lex-mark
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ lparen = and 0= if,
    cc-peek-mark cc-lex-reset
    [lit] 0
  else,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
    cc-peek-mark cc-lex-reset
  then, ;

\ cc-skip-fnptr-params ( -- )  Skip everything from the current position
\ through the matching ')'.  Uses paren-depth counter starting at 1
\ (the opening '(' has just been consumed).  Tokens are consumed one at
\ a time via cc-next-token-keep so cc-tok-pending is left clear at exit.
: cc-skip-fnptr-params
  [lit] 1
  begin,
    dup [lit] 0 >
  while,
    cc-next-token-keep
    tok-kind @ tk-punct = if,
      tok-num @ lparen = if, 1+ then,
      tok-num @ [char] ) = if, 1- then,
    then,
  repeat,
  drop ;

\ cc-parse-fnptr-decl ( -- )  The base type has been consumed by the caller;
\ the next two tokens are '(' and '*'.  Parses
\
\    '(' '*' NAME ')' '(' PARAM_TYPES ')' ('=' expr)? ';'
\
\ and registers NAME as an sk-local with type ty-func + ptr-depth=1.  The
\ parameter types are skipped; signatures are not validated.
: cc-parse-fnptr-decl
  \ Consume '(' and '*'.
  lparen cc-expect-punct-c
  [char] * cc-expect-punct-c

  \ NAME (IDENT).
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 153 cc-die
  then,
  tok-str-addr @ tok-str-len @                    ( name-a name-u )

  \ ')' '(' PARAM-TYPES ')'
  [char] ) cc-expect-punct-c
  lparen cc-expect-punct-c
  cc-skip-fnptr-params

  \ Register as an sk-local function pointer: ty-func + ptr-depth=1.
  sk-local
  ty-func [lit] 1 ty-make                         ( a u kind type )
  cc-fn-local-count @                             ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-add-slots

  \ Optional '= expr;' initializer.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] = = and if,
    cc-parse-expr
    cc-fn-local-count @ 1- cc-emit-store-local
    [char] ; cc-expect-punct-c
  else,
    tok-kind @ tk-punct = tok-num @ [char] ; = and 0= if,
      [lit] 154 cc-die
    then,
  then, ;

variable cc-decl-base                              \ base type kind

\ cc-parse-local-declarator ( init-ptr -- )  One declarator of a local
\ declaration whose base type is in cc-decl-base: '*'* NAME, then
\ '[' SIZE ']' or ('=' EXPR)? .  SIZE is a constant expression.  Ends with
\ the token after the declarator read (the caller wants ',' or ';').
\ init-ptr is non-zero only when the base came from a pointer-typed
\ typedef (`typedef int* int_ptr;`).
\
\ An array's element 0 sits in its deepest slot.  A `static` local
\ (cc-decl-static) gets file-scope storage instead of frame slots, so it
\ keeps its value between calls: the symbol is an sk-global that only
\ this block can see, an array in the bss, a scalar in the data area with
\ its constant initializer.
: cc-parse-local-declarator                       ( init-ptr -- )
  cc-count-stars +                                 ( ptr-depth )
  cc-expect-ident
  tok-str-addr @ tok-str-len @ rot                 ( a u ptr-depth )
  cc-decl-base @ swap ty-make                      ( a u type )
  cc-next-token-keep
  [char] [ cc-tok-punct? if,
    \ -------- Array: T name [ N ] --------
    cc-parse-const                                 ( a u type N )
    dup [lit] 0 <= if, [lit] 156 cc-die then,
    cc-next-token-keep
    [char] ] cc-tok-punct? 0= if, [lit] 157 cc-die then,
    >r                                             ( a u type ; R: N )
    cc-decl-static @ if,
      sk-global swap  r@ [lit] 8 * cc-bss-alloc    ( a u kind type slot )
    else,
      sk-local swap  cc-fn-local-count @ r@ + 1-
    then,
    cc-sym-add                                     ( id ; R: N )
    r@ swap cc-sym-set-array-len
    cc-decl-static @ 0= if, r@ cc-fn-add-slots then,
    r> drop
    cc-next-token-keep exit,
  then,
  \ -------- Scalar: T name ('=' expr)? --------
  cc-decl-static @ if,
    sk-global swap  [lit] 8 cc-globals-alloc       ( a u kind type slot )
    dup >r cc-sym-add drop                         ( ; R: slot )
    [char] = cc-tok-punct? if,
      cc-parse-const r@ cc-globals-store-8le
      cc-next-token-keep
    then,
    r> drop exit,
  then,
  sk-local swap  cc-fn-local-count @               ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-add-slots
  [char] = cc-tok-punct? if,
    cc-parse-expr
    cc-fn-local-count @ 1- cc-emit-store-local
    cc-next-token-keep
  then, ;

\ cc-parse-decl-with-base ( base initial-ptr -- )
\ A local declaration after its base type: one or more declarators
\ separated by ',', then ';' (else die 159).  The caller has consumed the
\ keyword or typedef-name that gave the base type, and supplies (base,
\ initial-ptr-depth).
\
\ If the next two tokens after the base are '(' '*', dispatch to
\ cc-parse-fnptr-decl instead (function-pointer declaration).
: cc-parse-decl-with-base                         ( base init-ptr -- )
  swap cc-decl-base !                              ( init-ptr )
  \ Detect function-pointer decl shape.  Only when there are no leading
  \ stars from the caller (init-ptr=0) — `int* (*fp)()` is a func-ptr returning
  \ int*, which is outside this subset.
  dup [lit] 0 = cc-peek-fnptr? and if,
    drop cc-parse-fnptr-decl exit,
  then,
  begin,
    dup cc-parse-local-declarator                  ( init-ptr )
    [char] , cc-tok-punct?
  while,
  repeat,
  drop
  [char] ; cc-tok-punct? 0= if,
    [lit] 159 cc-die
  then, ;

\ cc-tok-is-basic-type-kw? ( -- f )  -1 iff current token is a basic-type
\ keyword that introduces a local declaration: int / char / void / long /
\ short / unsigned / signed.  All are treated as 8-byte slot in codegen.
: cc-tok-is-basic-type-kw?
  tok-kind @ tk-kw =
    tok-kw-id @ kw-int      =
    tok-kw-id @ kw-char     = or
    tok-kw-id @ kw-void     = or
    tok-kw-id @ kw-long     = or
    tok-kw-id @ kw-short    = or
    tok-kw-id @ kw-unsigned = or
    tok-kw-id @ kw-signed   = or
  and ;

\ cc-more-type-kws ( base -- base' )  After a basic-type keyword, read any
\ more (`unsigned int`, `long long`, `unsigned char`): they all name the
\ one 8-byte integer, except that a char among them makes the type char.
: cc-more-type-kws
  begin,
    cc-next-token-keep cc-tok-is-basic-type-kw?
  while,
    kw-char cc-tok-kw? if, drop ty-char then,
  repeat,
  cc-putback-token ;

\ cc-parse-decl ( -- )  Entry from cc-parse-stmt.  The basic-type kw is
\ the current token (still in tok-*); pick ty-char for `char`, ty-int for the
\ rest (int / long / short / unsigned / signed), then read any further type
\ keywords.  ty-char matters because the
\ array-index path uses base==ty-char + ptr-depth==1 to decide on a byte-wide
\ load/store for `s[i]` where s is `char*` — without this distinction every
\ char pointer is treated like an int pointer (qword stride / qword load).
\ void as a local doesn't make sense; it would have been rejected anyway.
: cc-parse-decl
  tok-kw-id @ kw-char = if,
    ty-char
  else,
    ty-int
  then,
  cc-more-type-kws
  [lit] 0 cc-parse-decl-with-base ;

\ ===========================================================================
\ Type names and casts
\ ===========================================================================
\ A cast `( TYPE ) operand` names a type without declaring anything:
\ qualifiers, a base (a type keyword or several, struct TAG, enum TAG, or
\ a typedef-name), then '*'s.  Its value is the operand's; only the type
\ the parser tracks changes, so `*(char*)p` loads one byte and
\ `((struct T*)p)->f` finds the field.  A (char) cast keeps the low byte.

variable cc-cast-desc                              \ struct TAG's descriptor, or 0

\ cc-type-start? ( -- f )  Does the current token begin a type name?
: cc-type-start?
  cc-tok-is-basic-type-kw?  cc-qualifier? or
  kw-struct cc-tok-kw? or  kw-enum cc-tok-kw? or
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, drop else, cc-sym-kind-of sk-typedef = or then,
  then, ;

\ cc-parse-type-name ( -- ty )  The current token begins a type name; read
\ it, stars and all, and leave the token after it pending.
: cc-parse-type-name
  [lit] 0 cc-cast-desc !
  begin, cc-qualifier? while, cc-next-token-keep repeat,
  kw-struct cc-tok-kw? if,
    cc-lookup-struct-tag-soft cc-cast-desc !
    ty-struct [lit] 0
  else,
  kw-enum cc-tok-kw? if,
    cc-skip-enum-tag ty-int [lit] 0
  else,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find cc-sym-val-of
    dup ty-base swap ty-ptr
  else,
    \ Keywords: int, char, void, and combinations such as `unsigned int`
    \ or `long long`; any char makes it char.
    ty-int
    begin,
      kw-char cc-tok-kw? if, drop ty-char then,
      kw-void cc-tok-kw? if, drop ty-void then,
      cc-next-token-keep cc-tok-is-basic-type-kw?
    while,
    repeat,
    cc-putback-token
    [lit] 0
  then, then, then,                                ( base ptr )
  cc-skip-qualifiers
  cc-count-stars + ty-make ;

\ cc-try-cast ( -- f )  The current token is '('.  If a type name follows,
\ compile the whole cast — type, ')', then the operand, a unary
\ expression — and answer true.  Otherwise answer false with the token
\ after the '(' put back, for cc-parse-paren.
: cc-try-cast
  cc-next-token-keep
  cc-type-start? 0= if,
    cc-putback-token [lit] 0 exit,
  then,
  cc-parse-type-name >r                            ( ; R: ty )
  [char] ) cc-expect-punct-c
  cc-cast-desc @ >r                                ( ; R: ty desc )
  cc-parse-unary
  cc-emit-materialize
  r> r>                                            ( desc ty )
  dup ty-base ty-char =  over ty-ptr 0= and if,
    cc-emit-zx-byte-rdi
  then,
  cc-mark-not-lvalue
  cc-last-expr-type !
  cc-last-struct-desc !
  true ;

' cc-try-cast is cc-try-cast-fwd

\ ===========================================================================
\ cc-parse-struct-local-decl
\ ===========================================================================
\ Called with 'struct' keyword ALREADY consumed (it was the dispatch token).
\ Parses:
\
\    struct TAG '*'* IDENT ';'
\
\ ptr-depth=0 form (`struct TAG name;`): reserves total-size/8 local slots
\ (one per int field) with field-0 at the LOWEST address (deepest slot).
\ Symbol entry: val = slot of field 0; struct-desc = descriptor pointer.
\
\ ptr-depth>=1 form (`struct TAG* p;`): reserves a single slot for the pointer.
\ Symbol entry: val = slot, struct-desc = descriptor pointer of the pointee
\ (so '->field' can resolve field offsets).
\
\ Uses globals to avoid deep stack juggling.

variable cc-sld-desc
variable cc-sld-ptr-depth
variable cc-sld-name-a
variable cc-sld-name-u

: cc-parse-struct-local-decl                      ( -- )
  cc-lookup-struct-tag cc-sld-desc !
  cc-count-stars cc-sld-ptr-depth !
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 160 cc-die
  then,
  tok-str-addr @ cc-sld-name-a !
  tok-str-len  @ cc-sld-name-u !

  cc-sld-ptr-depth @ [lit] 0 = if,
    \ struct TAG name; — reserve slot-count slots.  No initializer support.
    [char] ; cc-expect-punct-c
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct [lit] 0 ty-make
    cc-fn-local-count @ cc-sld-desc @ cc-sd-total-size [lit] 8 / + 1-
                                                  ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-struct-desc
    \ Reserve slots.
    cc-sld-desc @ cc-sd-total-size [lit] 8 / cc-fn-add-slots
  else,
    \ struct TAG* p ('=' expr)? ; — one slot for the pointer.
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct cc-sld-ptr-depth @ ty-make          ( a u kind ty )
    cc-fn-local-count @                           ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-struct-desc
    [lit] 1 cc-fn-add-slots

    \ Optional '= expr;' initializer (M2-Planet uses `struct T* i = expr;`).
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] = = and if,
      cc-parse-expr
      cc-fn-local-count @ 1- cc-emit-store-local
      [char] ; cc-expect-punct-c
    else,
      tok-kind @ tk-punct = tok-num @ [char] ; = and 0= if,
        [lit] 161 cc-die
      then,
    then,
  then, ;

\ ===========================================================================
\ Switch-scrutinee unwind
\ ===========================================================================
\ cc-parse-switch (112-cc-stmt.fth) parks the outer rbx with
\ `push rbx` and restores it with `pop rbx` at the switch's end label.  Any
\ statement that jumps out of the switch body without passing the end label —
\ return, continue, goto — must first emit compensating pops, or each
\ traversal leaks 8 bytes of stack per open switch (and return hands the
\ caller a clobbered callee-saved rbx).
\
\ cc-switch-depth counts the switches lexically open at the current parse
\ point; cc-loop-switch-depth snapshots it at the innermost enclosing loop.
\   return:    pop cc-switch-depth times (every open switch in the function),
\   continue:  pop (cc-switch-depth - cc-loop-switch-depth) times (the
\              switches between the statement and the loop it continues),
\   goto:      pop cc-switch-depth times — correct for labels outside any
\              switch; goto to a label INSIDE a switch is unsupported.
\ break needs nothing: it targets the innermost loop or switch end label,
\ so it never jumps across a scrutinee push.
variable cc-switch-depth
variable cc-loop-switch-depth

\ cc-emit-switch-unwind ( n -- )  Emit n `pop rbx` instructions.
: cc-emit-switch-unwind                           ( n -- )
  begin,
    dup [lit] 0 >
  while,
    cc-emit-pop-rbx
    1-
  repeat,
  drop ;

\ cc-parse-return ( -- )  "return" already consumed; parse [expr] ';'.
\ Bare `return;` (no expression) is legal C — emit rax := 0 + epilogue.
\ Peek the next token: if it's ';' the peek already consumed it, so do NOT
\ call cc-expect-punct-c again.  Otherwise putback and parse the expression.
\ Either way, unwind any open switch scrutinees so rbx is restored before
\ the epilogue's ret.
: cc-parse-return
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ; = and if,
    cc-emit-xor-rax-rax                           \ rax := 0 (no value returned)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
  else,
    cc-putback-token
    cc-parse-expr
    cc-emit-mov-rax-rdi                           \ result -> rax (SYS-V)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
    [char] ; cc-expect-punct-c
  then, ;
