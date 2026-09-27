\ 116-cc-prog.fth — file-scope forms and the top-level driver for the C-subset
\ compiler.
\
\ Parses enums, typedefs, prototypes, and global variables, skips the forms
\ it has no code for, and compiles a whole translation unit (cc-parse-program).
\
\ The compiled output begins with a 26-byte entry stub at vaddr 0x400078:
\     mov rdi, [rsp]   ; 48 8B 3C 24             (4 bytes, argc)
\     lea rsi, [rsp+8] ; 48 8D 74 24 08          (5 bytes, argv)
\     call <main>      ; E8 <rel32>             (5 bytes)
\     mov rdi, rax     ; 48 89 C7                (3 bytes)
\     mov rax, 60      ; 48 C7 C0 3C 00 00 00    (7 bytes)
\     syscall          ; 0F 05                    (2 bytes)
\
\ Then come the shims, declarations, and function bodies.  main returns its
\ value in rax (SYS-V); the stub moves it to rdi and exits.  The call's rel32
\ is patched after main's vaddr is known.
\
\ Depends on 114-cc-func.fth and everything it depends on.

\ ===========================================================================
\ Enum and typedef definitions (file-scope only).
\ ===========================================================================
\ Enum:  `enum [TAG] { NAME (= CONSTANT)?, NAME, ... };`
\ Typedef: `typedef BASE '*'* NAME ;`   (BASE = int / char / void / struct TAG)
\
\ Both register their introduced names in the symbol table so later code can
\ reference them via the standard cc-sym-find path.

variable cc-enum-next-val

\ cc-parse-enum-def ( -- )  'enum' keyword has been consumed by the dispatcher.
\ Parses an optional tag, then `{ enumerator-list };`.
\ Each enumerator becomes an sk-enum entry whose val is the enumerator's
\ integer value (0-based by default, restart-from-N after `= N`, where N
\ is a constant expression, which may use the enumerators before it).
: cc-parse-enum-def
  \ Optional tag — discard.
  cc-next-token-keep
  tok-kind @ tk-ident = if,
    \ Tag IDENT — ignore.
  else,
    cc-putback-token
  then,

  [char] { cc-expect-punct-c

  [lit] 0 cc-enum-next-val !

  \ Enumerator loop.  Each pass ends with a continue (-1) / stop (0) flag.
  begin,
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 190 cc-die
    then,
    tok-str-addr @ tok-str-len @                  ( a u )

    \ Optional `= CONSTANT` (cc-parse-const).
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] = = and if,
      cc-parse-const cc-enum-next-val !
    else,
      cc-putback-token
    then,

    \ Add to symbol table as sk-enum.  ( a u kind type val )
    sk-enum
    [lit] 0                                       \ type unused
    cc-enum-next-val @                            \ val
    cc-sym-add drop

    [lit] 1 cc-enum-next-val +!

    \ Separator: ',' continues, '}' terminates.  A trailing ',' before '}'
    \ is allowed: peek the next token; if it's '}', stop.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] , = and if,
      \ Peek to allow trailing comma.
      cc-next-token-keep
      tok-kind @ tk-punct = tok-num @ [char] } = and if,
        cc-putback-token                           \ leave '}' for the close
        [lit] 0                                    \ stop
      else,
        cc-putback-token                           \ not '}', let next iter read
        true                                       \ continue
      then,
    else,
      tok-kind @ tk-punct = tok-num @ [char] } = and if,
        cc-putback-token                           \ leave '}' for the close
        [lit] 0                                    \ stop
      else,
        [lit] 192 cc-die
      then,
    then,
    0=
  until,

  [char] } cc-expect-punct-c
  [char] ; cc-expect-punct-c ;

\ cc-parse-typedef ( -- )  'typedef' has been consumed by the dispatcher.
\ Grammar: typedef BASE '*'* NAME ';'
\ Supported bases: int / char / void / struct TAG / enum TAG / another
\ typedef.
\ Registers NAME as sk-typedef with val = encoded type word.
\
\ Uses cc-td-ty to stage the type so the data stack stays shallow across
\ keyword / pointer / IDENT parsing — easier than r-stack juggling.
variable cc-td-ty
: cc-parse-typedef
  cc-next-token-keep
  \ Parse base type into cc-td-ty.
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-int = if,
      ty-int [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-char = if,
      ty-char [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-void = if,
      ty-void [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-struct = if,
      cc-lookup-struct-tag drop
      ty-struct [lit] 0 ty-make cc-td-ty !
    else, tok-kw-id @ kw-enum = if,
      cc-skip-enum-tag
      ty-int [lit] 0 ty-make cc-td-ty !
    else,
      [lit] 193 cc-die
    then, then, then, then, then,
  else,
    tok-kind @ tk-ident = if,
      tok-str-addr @ tok-str-len @ cc-sym-find
      dup 0< if,
        [lit] 194 cc-die
      then,
      dup cc-sym-kind-of sk-typedef <> if,
        [lit] 195 cc-die
      then,
      cc-sym-val-of cc-td-ty !
    else,
      [lit] 196 cc-die
    then,
  then,

  \ Add pointer stars onto whatever base we got.
  cc-count-stars                                   ( extra-stars )
  cc-td-ty @ +                                     ( final-ty )
  cc-td-ty !

  \ Distinguish:
  \   typedef BASE *... NAME ';'                  (simple alias)
  \   typedef BASE (*NAME) ( params ) ';'         (function-pointer typedef)
  \ M2-Planet's gcc_req.h uses the fn-ptr form for `typedef void (*FUNCTION)(void);`.
  \ The return type and parameter types are parsed-and-discarded; NAME is
  \ registered as a pointer-to-function (ty-func, depth 1), matching how
  \ encodes inline `int (*op)(int)` locals — sufficient for parse-through
  \ without enabling actual indirect call via a typedef'd name yet.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ lparen = and if,
    \ '(' — function-pointer typedef.  Consume one or more '*'s, then IDENT,
    \ then ')'.  Then consume the parameter list parens (balanced).
    cc-count-stars drop                            \ at least one star expected
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 197 cc-die
    then,
    tok-str-addr @ tok-str-len @                   ( a u )
    [char] ) cc-expect-punct-c
    lparen cc-expect-punct-c                       \ '(' of param list
    \ Skip tokens paren-balanced until matching ')'.  Depth starts at 1.
    [lit] 1
    begin,
      dup [lit] 0 >
    while,
      cc-next-token-keep
      tok-kind @ tk-punct = if,
        tok-num @ lparen = if, 1+ else,
        tok-num @ [char] ) = if, 1- else,
        then, then,
      then,
    repeat,
    drop                                           ( a u )
    sk-typedef [lit] 0                             ( a u kind type )
    ty-func [lit] 1 ty-make                        ( a u kind type val )
    cc-sym-add drop
  else,
    \ Plain IDENT (the new typedef name) — putback first since we just peeked.
    tok-kind @ tk-ident <> if,
      [lit] 198 cc-die
    then,
    tok-str-addr @ tok-str-len @                   ( a u )
    sk-typedef [lit] 0 cc-td-ty @                  ( a u kind type val )
    cc-sym-add drop
  then,

  [char] ; cc-expect-punct-c ;

\ ---------------------------------------------------------------------------
\ Top-level forward-decl / file-scope-var elision.
\ ---------------------------------------------------------------------------
\ Our compiler only knows how to emit code for `int NAME(params) { body }`
\ function definitions.  When parsing real-world C headers we encounter a
\ profusion of other top-level forms:
\
\   void f(args);             /* forward fn decl, non-int return type */
\   char* f(args);            /* forward fn decl, pointer return type */
\   struct T* f(args);        /* forward fn decl, struct-ptr return type */
\   int f(args);              /* forward fn decl, int return type (no body) */
\   extern int g;             /* file-scope variable */
\   struct T* g_list;         /* file-scope variable */
\
\ None of these need to GENERATE anything in our target (the body is missing
\ for forward decls; file-scope vars aren't yet supported).  But they DO need
\ to PARSE without exploding so the headers can flow through.
\
\ Strategy: at top level, when we see a type-introducing keyword (int / char /
\ void / struct / typedef-name) that isn't a struct/enum/typedef DEFINITION,
\ cc-top-classify peeks ahead, paren-balanced, to the first ';' or '{' at
\ depth 0 and sorts the declaration into one of three classes:
\   - '{' first               → top-fndef: a function definition.
\   - ';' first, a '(' before → top-proto: a prototype; register the name.
\     (Only a '(' ahead of any '=' or '[' counts.)
\   - ';' first, no '('       → top-var: a file-scope variable.
\ The peek marks the lexer state in cc-peek-mark and resets to it, so the
\ parser that handles the class starts from the declaration's first token.

[lit] 0 constant top-var
[lit] 1 constant top-proto
[lit] 2 constant top-fndef

variable cc-top-depth                             \ paren depth while scanning
variable cc-top-var-seen                          \ an '=' or '[' came first

\ cc-top-classify ( -- class )  Scan forward to the first ';' or '{' at paren
\ depth 0 (or EOF), noting whether a '(' came first — before any '=' or
\ '[' at depth 0, since `int x = (1);` and `int a[(2)];` are variables.
\ Always restores the lexer state; each of the three exits resets it, then
\ returns the class.
: cc-top-classify
  cc-peek-mark cc-lex-mark
  [lit] 0 cc-top-depth !
  [lit] 0 cc-top-var-seen !
  top-var                                         ( class )
  begin,
    cc-next-token-keep
    tok-kind @ tk-eof = if,
      cc-peek-mark cc-lex-reset exit,             \ EOF: no body
    then,
    tok-kind @ tk-punct = if,
      cc-top-depth @ [lit] 0 = if,
        tok-num @ [char] = =  tok-num @ [char] [ = or if,
          true cc-top-var-seen !
        then,
      then,
      tok-num @ lparen = if,
        cc-top-var-seen @ 0= if,
          drop top-proto                          \ a '(' before the end
        then,
        [lit] 1 cc-top-depth +!
      then,
      tok-num @ [char] ) = if, [lit] 1 cc-top-depth -! then,
      cc-top-depth @ [lit] 0 = if,
        tok-num @ [char] ; = if,
          cc-peek-mark cc-lex-reset exit,         \ ';' first: a declaration
        then,
        tok-num @ [char] { = if,
          drop top-fndef
          cc-peek-mark cc-lex-reset exit,         \ '{' first: a definition
        then,
      then,
    then,
  again, ;

\ cc-top-skip-to-semi ( -- )
\ Consume tokens through and including the next top-level ';'.  Paren-balanced
\ so commas / parens inside parameter lists don't fool us.  If we run into
\ EOF first, we exit cleanly so the outer loop also exits.
: cc-top-skip-to-semi
  [lit] 0 cc-top-depth !
  begin,
    cc-next-token-keep
    tok-kind @ tk-eof = if, exit, then,
    tok-kind @ tk-punct = if,
      tok-num @ lparen = if, [lit] 1 cc-top-depth +! then,
      tok-num @ [char] ) = if, [lit] 1 cc-top-depth -! then,
      tok-num @ [char] ; =  cc-top-depth @ [lit] 0 =  and if, exit, then,
    then,
  again, ;

\ cc-register-fn-proto ( -- )  Parse `T '*'* NAME (...);` and register NAME
\ as sk-func with vaddr=0 so call sites resolve.  When the actual definition
\ is later parsed, cc-parse-function adds a newer sk-func entry; cc-sym-find
\ (newest-first) returns the definition for backward calls.  Forward calls
\ (call to fn before its def) are patched through the symbol's fixup list.
\ Caller has put-back the first token of the prototype.  Consumes through ';'.
\
\ Idempotency: real-world headers often re-declare the same prototype across
\ TUs (e.g. M2-Planet has `struct token_list* read_all_tokens(...)` in both
\ cc_macro.c and cc.c, with the definition in cc_reader.c sandwiched in
\ between).  Concatenated into our monolith the post-definition prototype
\ would register a new sk-func with val=0, and because cc-sym-find returns
\ the newest match, every later call site emits a forward-call placeholder
\ against a stale entry whose fixups are never patched.  Skip the re-add if
\ the name is already an sk-func.
: cc-register-fn-proto
  cc-parse-fn-return-type
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 199 cc-die
  then,
  tok-str-addr @ tok-str-len @                    ( a u )
  2dup cc-sym-find                                ( a u id-or-neg1 )
  dup [lit] 0 >= if,
    cc-sym-kind-of sk-func = if,
      \ Already registered as a function — drop the leftover ( a u ).
      2drop
      cc-top-skip-to-semi
    else,
      sk-func ty-int [lit] 0 ty-make [lit] 0      ( a u kind ty val=0 )
      cc-sym-add drop
      cc-top-skip-to-semi
    then,
  else,
    drop                                          ( a u )
    sk-func ty-int [lit] 0 ty-make [lit] 0        ( a u kind ty val=0 )
    cc-sym-add drop
    cc-top-skip-to-semi
  then, ;

\ ===========================================================================
\ File-scope global variable declaration.
\ ===========================================================================
\ Parses ONE top-level declaration: a base type, then one or more
\ declarators separated by ',', then ';'.  A declarator is
\
\    '*'* name                      a scalar
\    '*'* name '=' CONSTANT         a scalar with an initializer
\    '*'* name '[' SIZE ']'         an array
\
\ where the base type is int/char/void/long/short/etc., `struct TAG`,
\ `enum TAG` or a typedef-name, and SIZE and CONSTANT are constant
\ expressions (cc-parse-const).  The base type is consumed by the caller
\ (cc-parse-function-list) — when we get here the lookahead has been put
\ back so cc-next-token-keep yields the type keyword again.
\
\ A scalar takes a data slot (8 bytes — a struct VALUE gets its full
\ descriptor size rounded up to 8), and its initializer is written into
\ the data area so the runtime image already contains the value.  An array
\ takes N*8 bytes of the bss.  A second declaration of a global that
\ already exists — `extern int g;` early on, `int g = 3;` later — names
\ the same slot, so both see one variable and the initializer lands in
\ it.  Function-pointer, aggregate, and struct initializers are not
\ implemented.
\
\ Errors die through cc-die with codes 202..205 (Appendix G).

variable cc-gdecl-base
variable cc-gdecl-name-a
variable cc-gdecl-name-u
variable cc-gdecl-slot
variable cc-gdecl-desc
variable cc-gdecl-ptr-depth

\ cc-gdecl-scalar-bytes ( -- n )  Byte size of one non-array global slot.
\ A struct VALUE (ty-struct base, zero pointer depth, descriptor known)
\ needs its full descriptor size, rounded up to a multiple of 8 — a flat 8
\ would let stores past the first field clobber the next global.  Everything
\ else — ints, chars, pointers, struct pointers, opaque struct refs — is one
\ 8-byte slot.
: cc-gdecl-scalar-bytes                           ( -- n )
  cc-gdecl-base @ ty-struct =
  cc-gdecl-ptr-depth @ [lit] 0 = and
  cc-gdecl-desc @ [lit] 0 <> and if,
    cc-gdecl-desc @ cc-sd-total-size [lit] 7 + [lit] 8 / [lit] 8 *
  else,
    [lit] 8
  then, ;

\ cc-gdecl-add ( -- id )  Register the declarator's name as an sk-global
\ in cc-gdecl-slot.
: cc-gdecl-add
  cc-gdecl-name-a @ cc-gdecl-name-u @               ( a u )
  sk-global                                          ( a u kind )
  cc-gdecl-base @ cc-gdecl-ptr-depth @ ty-make      ( a u kind type )
  cc-gdecl-slot @                                    ( a u kind type val )
  cc-sym-add ;

\ cc-gdecl-declared ( -- id | -1 )  The global this name already is, if
\ it is one.
: cc-gdecl-declared
  cc-gdecl-name-a @ cc-gdecl-name-u @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-global <> if, drop true then,
  then, ;

\ cc-gdecl-declarator ( -- )  One declarator; ends with the token after it
\ read (the caller wants ',' or ';').
: cc-gdecl-declarator
  cc-count-stars cc-gdecl-ptr-depth !
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 203 cc-die
  then,
  tok-str-addr @ cc-gdecl-name-a !
  tok-str-len  @ cc-gdecl-name-u !
  cc-next-token-keep
  [char] [ cc-tok-punct? if,
    \ Array form: 'T name [ N ]', in the bss.  The symbol records the
    \ element count as its array length, so codegen can tell array decay
    \ from scalar deref.
    cc-parse-const                                   ( n )
    [char] ] cc-expect-punct-c
    dup [lit] 8 * cc-bss-alloc cc-gdecl-slot !
    cc-gdecl-add cc-sym-set-array-len
    cc-next-token-keep exit,
  then,
  \ Scalar: a new data slot, or the one an earlier declaration made.
  cc-gdecl-declared dup 0< if,
    drop
    cc-gdecl-scalar-bytes cc-globals-alloc cc-gdecl-slot !
    cc-gdecl-desc @ cc-gdecl-add cc-sym-set-struct-desc
  else,
    cc-sym-val-of cc-gdecl-slot !
  then,
  [char] = cc-tok-punct? if,
    cc-parse-const cc-gdecl-slot @ cc-globals-store-8le
    cc-next-token-keep
  then, ;

\ cc-parse-global-decl ( -- )  Caller has already done cc-skip-storage-quals;
\ the next token is the base-type keyword OR a typedef-name IDENT.  Consumes
\ through ';'.
: cc-parse-global-decl                            ( -- )
  [lit] 0 cc-gdecl-desc !
  ty-int cc-gdecl-base !
  \ Read base type.
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-struct = if,
      \ Support struct TAG as base type.  Soft lookup: descriptor pointer
      \ if the struct is defined, 0 otherwise.  cc_globals.c declares
      \ `struct type* foo;` without a `struct type {...}` in scope — that's
      \ an opaque-pointer pattern we still need to parse.
      ty-struct cc-gdecl-base !
      cc-lookup-struct-tag-soft cc-gdecl-desc !
    else,
      \ Distinguish `char` from other primitives so `char* foo;` records
      \ ty-char in the symbol table.  Without this, `char* hold_string;`
      \ looks identical to `int* foo;` and the array-index path uses qword
      \ stride/load on its bytes — corrupting tokenizer scratch buffers in
      \ M2-Planet's preprocessor.  int/void/long/short/enum TAG all
      \ collapse to ty-int (storage is 8 bytes regardless; only the
      \ byte-stride dispatch cares).
      tok-kw-id @ kw-char = if, ty-char cc-gdecl-base ! then,
      tok-kw-id @ kw-enum = if, cc-skip-enum-tag then,
      cc-tok-is-basic-type-kw? if,
        cc-gdecl-base @ cc-more-type-kws cc-gdecl-base !
      then,
    then,
  else,
    \ Typedef-name IDENT (FILE, uint8_t, ...).  We don't need to verify it
    \ actually resolves to a known typedef — the caller already determined
    \ this is a declaration via cc-top-classify.
    tok-kind @ tk-ident <> if,
      [lit] 202 cc-die
    then,
  then,
  cc-skip-qualifiers
  begin,
    cc-gdecl-declarator
    [char] , cc-tok-punct?
  while,
  repeat,
  [char] ; cc-tok-punct? 0= if,
    [lit] 205 cc-die
  then, ;

\ cc-finalize-globals ( -- )  After the entire program has been parsed and
\ all functions emitted, append cc-globals-buf to cc-out-buf, place the bss
\ after it, and patch every recorded fixup to point at the now-known global
\ vaddrs.
\
\ cc-globals-base-vaddr is set to cc-base-vaddr + (cc-out-pos at the moment
\ globals are appended).  The bss starts at the next 8-aligned vaddr (the
\ file is padded with zeros to reach it), and cc-bss-size tells
\ cc-finalize-elf how much memory it adds.  Then each fixup's imm64
\ placeholder is overwritten with the slot's vaddr: cc-globals-base-vaddr
\ + slot for a data slot, cc-bss-base-vaddr + (slot - cc-bss-flag) for a
\ bss one.
: cc-finalize-globals
  cc-here-vaddr cc-globals-base-vaddr !
  \ Append cc-globals-pos bytes from cc-globals-buf to cc-out-buf.
  [lit] 0
  begin, dup cc-globals-pos @ < while,
    dup cc-globals-buf + c@ cc-emit-byte
    1+
  repeat, drop
  \ Align the bss, if there is one.
  cc-bss-pos @ if,
    begin, cc-out-pos @ [lit] 7 and while, [lit] 0 cc-emit-byte repeat,
  then,
  cc-here-vaddr cc-bss-base-vaddr !
  cc-bss-pos @ cc-bss-size !
  \ Patch each fixup.  i walks 0..cc-gfixup-count-1.
  [lit] 0
  begin, dup cc-gfixup-count @ < while,
    dup cc-gfixup-slot     cell[] @                \ slot
    dup cc-bss-flag < if,
      cc-globals-base-vaddr @ +                     \ vaddr = base + slot
    else,
      cc-bss-flag - cc-bss-base-vaddr @ +           \ vaddr = bss base + offset
    then,
    over cc-gfixup-out-pos cell[] @                \ patch-offset
    cc-out-patch-8le
    1+
  repeat, drop ;

\ cc-struct-def-ahead? ( -- f )  The current token is `struct`.  True iff
\ the next two are TAG '{' — a struct definition, not a declaration that
\ uses the type.  Restores the lexer state.
: cc-struct-def-ahead?
  cc-peek-mark cc-lex-mark
  cc-next-token                                   \ the tag IDENT
  cc-next-token                                   \ what follows it
  tok-kind @ tk-punct = tok-num @ [char] { = and
  cc-peek-mark cc-lex-reset ;

\ cc-enum-def-ahead? ( -- f )  The current token is `enum`.  True iff an
\ enumerator list follows: '{', or TAG '{'.  Otherwise the enum only names
\ a type (`enum BINDING f(...)`).  Restores the lexer state.
: cc-enum-def-ahead?
  cc-peek-mark cc-lex-mark
  cc-next-token
  tok-kind @ tk-ident = if, cc-next-token then,
  tok-kind @ tk-punct = tok-num @ [char] { = and
  cc-peek-mark cc-lex-reset ;

\ cc-parse-top-decl ( -- )  The current token starts a top-level item.
\ Definitions of a struct, enum or typedef have their own parsers; anything
\ else is a function definition, a prototype or a file-scope variable, and
\ cc-top-classify says which.  A `struct TAG` that isn't followed by '{'
\ (`struct TAG* f(...)`, `struct TAG* g;`) is one of those three, and so
\ is an `enum TAG` without an enumerator list.
: cc-parse-top-decl
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-enum    = if,
      cc-enum-def-ahead? if, cc-parse-enum-def exit, then,
    then,
    tok-kw-id @ kw-typedef = if, cc-parse-typedef  exit, then,
    tok-kw-id @ kw-struct  = if,
      cc-struct-def-ahead? if, cc-parse-struct-def exit, then,
    then,
  then,
  \ int/char/void/struct T/typedef-name: put the type back for the parser.
  cc-putback-token
  cc-top-classify
  dup top-fndef = if, drop cc-parse-function     exit, then,
      top-proto = if,      cc-register-fn-proto  exit, then,
  cc-parse-global-decl ;

\ cc-parse-function-list ( -- )  Loop over top-level declarations until EOF.
\ See the long comment above for the elision rules.
: cc-parse-function-list
  begin,
    cc-skip-storage-quals
    cc-next-token-keep
    tok-kind @ tk-eof = 0=
  while,
    cc-parse-top-decl
  repeat, ;

\ ===========================================================================
\ Entry-stub emission and rel32 patching.
\ ===========================================================================

\ cc-emit-entry-stub ( -- )  Emit at vaddr cc-entry-vaddr (0x400078):
\     mov  rdi, [rsp]      48 8B 3C 24      ; argc (kernel puts it at [rsp])
\     lea  rsi, [rsp+8]    48 8D 74 24 08   ; argv = &argv[0]
\     call <main>          E8 <rel32>
\     mov  rdi, rax        48 89 C7         ; main's return -> exit code
\     mov  rax, 60         48 C7 C0 3C 00 00 00
\     syscall              0F 05
\ Records the file-offset of the rel32 in cc-call-main-patch.
\ Stack alignment: kernel hands us rsp 16-aligned and we don't touch it before
\ `call`, so main enters 8-mod-16 as SysV requires.
: cc-emit-entry-stub
  \ mov rdi, [rsp]   — argc
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  60 cc-emit-byte
  [lit]  36 cc-emit-byte

  \ lea rsi, [rsp+8] — argv
  [lit]  72 cc-emit-byte
  [lit] 141 cc-emit-byte
  [lit] 116 cc-emit-byte
  [lit]  36 cc-emit-byte
  [lit]   8 cc-emit-byte

  [lit] 232 cc-emit-byte                          \ E8
  cc-out-pos @ cc-call-main-patch !               \ remember rel32 file-offset
  [lit] 0 cc-emit-4le                             \ rel32 placeholder

  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 199 cc-emit-byte                          \ mov rdi, rax

  [lit]  72 cc-emit-byte
  [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte
  [lit]  60 cc-emit-4le                           \ mov rax, 60

  [lit]  15 cc-emit-byte
  [lit]   5 cc-emit-byte ;                        \ syscall

\ cc-patch-call-main ( -- )  Compute and store the call's rel32.
\ rel32 = main_vaddr - vaddr_of_next_instr
\       = main_vaddr - (cc-base-vaddr + cc-call-main-patch + 4)
: cc-patch-call-main
  cc-main-vaddr @
  cc-base-vaddr cc-call-main-patch @ + [lit] 4 + -
  cc-call-main-patch @
  cc-out-patch-4le ;

\ ===========================================================================
\ Top-level driver
\ ===========================================================================

\ ===========================================================================
\ Built-in libc shim emission + symtab registration.
\ ===========================================================================
\ The shims (putchar, exit, getchar) live at the very start of the code
\ segment, immediately after the 26-byte entry stub.  Registering them in
\ the symbol table BEFORE parsing user functions means cc-parse-call's
\ name-lookup path finds them just like any user-defined function.

\ Pre-baked name strings (raw bytes, no length prefix; the length is supplied
\ explicitly to cc-sym-add).
create cc-name-putchar  s, putchar
create cc-name-exit     s, exit
create cc-name-getchar  s, getchar
create cc-name-fputs    s, fputs
create cc-name-fopen    s, fopen
create cc-name-fclose   s, fclose
create cc-name-fputc    s, fputc
create cc-name-fread    s, fread
create cc-name-fwrite   s, fwrite
create cc-name-calloc   s, calloc
create cc-name-memset   s, memset
create cc-name-free     s, free
create cc-name-open     s, open
create cc-name-read     s, read
create cc-name-write    s, write
create cc-name-close    s, close
create cc-name-malloc   s, malloc
create cc-name-strlen   s, strlen
create cc-name-memcpy   s, memcpy
create cc-name-strrchr  s, strrchr

\ cc-emit-shims ( -- )  Emit each shim's body and register it in the symbol
\ table as sk-func with val = its absolute vaddr.
: cc-emit-shims
  \ putchar
  cc-name-putchar [lit] 7
  sk-func
  ty-int [lit] 0 ty-make
  cc-here-vaddr                                   ( a u kind ty vaddr )
  cc-sym-add drop
  cc-emit-putchar-shim

  \ exit
  cc-name-exit [lit] 4
  sk-func
  ty-void [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-exit-shim

  \ getchar
  cc-name-getchar [lit] 7
  sk-func
  ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-getchar-shim

  \ fputs
  cc-name-fputs [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-fputs-shim

  \ fputc
  cc-name-fputc [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-fputc-shim

  \ fopen
  cc-name-fopen [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-fopen-shim

  \ fclose
  cc-name-fclose [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-fclose-shim

  \ fwrite
  cc-name-fwrite [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-fwrite-shim

  \ fread
  cc-name-fread [lit] 5
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-fread-shim

  \ calloc
  cc-name-calloc [lit] 6
  sk-func ty-int [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-calloc-shim

  \ free (no-op bump allocator)
  cc-name-free [lit] 4
  sk-func ty-void [lit] 0 ty-make
  cc-here-vaddr
  cc-sym-add drop
  cc-emit-free-shim ;

\ ===========================================================================
\ Shims emitted only when used: malloc, open, read, write, close, strlen,
\ memcpy, strrchr.
\ ===========================================================================
\ These are registered like prototypes (sk-func, vaddr 0) before the
\ program is parsed, so a call to one is a forward call whose fixup waits
\ on the symbol (cc-parse-call).  If the program defines the function
\ itself, its definition takes the fixups as for any prototype.  After the
\ program, cc-emit-late-shims emits the body of each one still waiting and
\ patches its callers, so a program that uses none of them is not a byte
\ longer.
\
\ One row per shim: name, name length, emitter xt, and the symbol id
\ (filled in by cc-register-late-shims).  A 0 name ends the table.

: cc-emit-open-shim   [lit] 2 cc-emit-syscall-shim ;
: cc-emit-read-shim   [lit] 0 cc-emit-syscall-shim ;
: cc-emit-write-shim  [lit] 1 cc-emit-syscall-shim ;
: cc-emit-close-shim  [lit] 3 cc-emit-syscall-shim ;
\ malloc jumps into the calloc shim, the first sk-func named calloc.
: cc-emit-malloc-late
  cc-name-calloc [lit] 6 cc-sym-find cc-sym-val-of cc-emit-malloc-shim ;

create cc-late-shims
cc-name-malloc  , [lit] 6 , ' cc-emit-malloc-late  , [lit] 0 ,
cc-name-open    , [lit] 4 , ' cc-emit-open-shim    , [lit] 0 ,
cc-name-read    , [lit] 4 , ' cc-emit-read-shim    , [lit] 0 ,
cc-name-write   , [lit] 5 , ' cc-emit-write-shim   , [lit] 0 ,
cc-name-close   , [lit] 5 , ' cc-emit-close-shim   , [lit] 0 ,
cc-name-strlen  , [lit] 6 , ' cc-emit-strlen-shim  , [lit] 0 ,
cc-name-memcpy  , [lit] 6 , ' cc-emit-memcpy-shim  , [lit] 0 ,
cc-name-strrchr , [lit] 7 , ' cc-emit-strrchr-shim , [lit] 0 ,
[lit] 0 ,

\ cc-register-late-shims ( -- )  Add each as a prototype; keep its id.
: cc-register-late-shims
  cc-late-shims
  begin, dup @ while,
    dup @  over [lit] 8 + @                       ( row a u )
    sk-func ty-int [lit] 0 ty-make [lit] 0 cc-sym-add
    over [lit] 24 + !
    [lit] 32 +
  repeat,
  drop ;

\ cc-emit-late-shims ( -- )  Emit each shim that has callers still waiting,
\ and point them at it.
: cc-emit-late-shims
  cc-late-shims
  begin, dup @ while,
    dup [lit] 24 + @                               ( row id )
    dup cc-sym-call-fixups @  over cc-sym-addr-fixups @  or if,
      cc-here-vaddr over cc-sym-val cell[] !
      dup cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
      dup cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-imm64-to-vaddr
      [lit] 0 over cc-sym-call-fixups !
      [lit] 0 over cc-sym-addr-fixups !
      over [lit] 16 + @ execute
    then,
    drop
    [lit] 32 +
  repeat,
  drop ;

\ ===========================================================================
\ M2 test-suite external prototype.  The M2 monolith itself does not call
\ memset, but the published parity script compares selected upstream tests
\ where memset is declared by an elided system header.
\ ===========================================================================

: cc-emit-external-protos
  cc-name-memset  [lit] 6  sk-func ty-int [lit] 0 ty-make  [lit] 0 cc-sym-add drop ;

\ Built-in typedefs for opaque libc/stdint names.  All map to ty-int so the
\ parser will accept `FILE* p;`, `uint8_t x;`, etc. — codegen still treats
\ them as 8-byte slots regardless of the C-visible width.
create cc-name-FILE      s, FILE
create cc-name-int8_t    s, int8_t
create cc-name-int16_t   s, int16_t
create cc-name-int32_t   s, int32_t
create cc-name-int64_t   s, int64_t
create cc-name-uint8_t   s, uint8_t
create cc-name-uint16_t  s, uint16_t
create cc-name-uint32_t  s, uint32_t
create cc-name-uint64_t  s, uint64_t
create cc-name-size_t    s, size_t
create cc-name-ssize_t   s, ssize_t
create cc-name-intptr_t  s, intptr_t

\ cc-emit-libc-typedefs ( -- )  Register the typedef names above so headers
\ that say `FILE* fp;` or `uint8_t b;` parse as types.  All map to ty-int
\ encoded as the sk-typedef's val field (matching cc-parse-typedef's layout).
: cc-emit-libc-typedefs
  cc-name-FILE     [lit] 4  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int8_t   [lit] 6  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int16_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int32_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-int64_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint8_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint16_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint32_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-uint64_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-size_t   [lit] 6  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-ssize_t  [lit] 7  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop
  cc-name-intptr_t [lit] 8  sk-typedef [lit] 0  ty-int [lit] 0 ty-make  cc-sym-add drop ;

\ cc-check-fns-defined ( -- )  After the whole program: a function that was
\ called or used as a value but never defined still has pending call or
\ address fixups — each would run a rel32 of 0 (falling through to the next
\ instruction) or load address 0.  Die 206 instead.  Then die 207 if there
\ is no main for the entry stub to call.  memset is registered above with
\ no body, so a program that uses it dies here too: this compiler has no
\ memset to link.
: cc-check-fns-defined
  [lit] 0                                         ( id )
  begin, dup cc-sym-count @ < while,
    dup cc-sym-kind-of sk-func = if,
      dup cc-sym-call-fixups @  over cc-sym-addr-fixups @  or if,
        [lit] 206 cc-die
      then,
    then,
    1+
  repeat, drop
  cc-main-vaddr @ 0= if, [lit] 207 cc-die then, ;

\ cc-parse-program ( -- )  Emit entry stub, emit libc shims, register the
\ late shims, the one external prototype and built-in typedefs, parse all
\ functions, emit the late shims that were called, check every used
\ function got a body, patch entry stub.
: cc-parse-program
  cc-emit-entry-stub
  cc-emit-shims
  cc-register-late-shims
  cc-emit-external-protos
  cc-emit-libc-typedefs
  cc-parse-function-list
  cc-emit-late-shims
  cc-check-fns-defined
  cc-patch-call-main ;
