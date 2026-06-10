\ 090-cc-emit.fth — code-emission helpers for the C-subset compiler.
\ Builds tiny instruction-encoders on top of cc-emit-byte / cc-emit-4le from
\ 030-cc-io.fth.  All output goes to cc-out-buf; nothing here touches the seed's
\ HERE pointer.
\
\ Register convention for the compiled code:
\   rdi  — scratch / current expression result
\   rcx  — temp for binary-op right operand
\   rax  — used by idiv (low quotient/remainder); also by SYS-V return
\   rbp  — frame base; locals at [rbp - 8*(slot+1)]
\
\ Depends on 030-cc-io.fth (cc-emit-byte, cc-emit-4le).

\ ===========================================================================
\ Immediate-load instructions (REX.W + C7 /0 + imm32)
\ ===========================================================================

\ cc-emit-mov-rdi-imm32 ( v -- )   48 C7 C7 <imm32>
: cc-emit-mov-rdi-imm32
  [lit]  72 cc-emit-byte
  [lit] 199 cc-emit-byte
  [lit] 199 cc-emit-byte
  cc-emit-4le ;

\ ===========================================================================
\ Stack ops
\ ===========================================================================

\ push rdi: 0x57
: cc-emit-push-rdi  [lit]  87 cc-emit-byte ;

\ pop rdi:  0x5F
: cc-emit-pop-rdi   [lit]  95 cc-emit-byte ;

\ pop rsi:  0x5E
: cc-emit-pop-rsi   [lit]  94 cc-emit-byte ;

\ pop rdx:  0x5A
: cc-emit-pop-rdx   [lit]  90 cc-emit-byte ;

\ pop rcx:  0x59
: cc-emit-pop-rcx   [lit]  89 cc-emit-byte ;

\ pop r8:   0x41 0x58  (REX.B + pop)
: cc-emit-pop-r8    [lit]  65 cc-emit-byte [lit]  88 cc-emit-byte ;

\ pop r9:   0x41 0x59
: cc-emit-pop-r9    [lit]  65 cc-emit-byte [lit]  89 cc-emit-byte ;

\ push rbx (0x53) / pop rbx (0x5B).  Used by switch to preserve the outer
\ value of rbx across the switch (which uses rbx to hold the scrutinee).
: cc-emit-push-rbx  [lit]  83 cc-emit-byte ;
: cc-emit-pop-rbx   [lit]  91 cc-emit-byte ;

\ ===========================================================================
\ Local-variable access
\ ===========================================================================
\ Locals live at [rbp - 8*(slot+1)].  Slots 0..15 have displacements
\ -8..-128, which fit a signed disp8 (ModR/M mod=01); deeper slots need the
\ disp32 form (mod=10).  cc-emit-local-ea picks the right one per slot.
\ Note: the frame itself is fixed at 256 bytes = 32 slots by the prologue
\ call in 110-cc-decl.fth — the encoding handles any slot; the frame does not.
\
\ cc-disp8-from-slot ( slot -- byte )
\   = (256 - 8*(slot+1)) AND 255 = the unsigned-byte representation of the
\   signed displacement -8*(slot+1).  Only valid for slots 0..15.

: cc-disp8-from-slot
  [lit] 1 + [lit] 8 *                            \ 8 * (slot+1)
  [lit] 0 swap -                                  \ negate
  [lit] 255 and ;                                 \ low byte

\ cc-emit-local-ea ( slot modrm8 -- )
\   Emit the ModR/M byte + displacement for [rbp + disp] access to a local
\   slot.  modrm8 is the mod=01 (disp8) form of the ModR/M byte.  Slots
\   0..15 emit it unchanged plus a disp8; deeper slots switch to mod=10
\   (modrm8 + 0x40) plus the 32-bit two's-complement displacement.
: cc-emit-local-ea
  over [lit] 16 < if,
    cc-emit-byte
    cc-disp8-from-slot cc-emit-byte
  else,
    [lit] 64 + cc-emit-byte                       \ mod=01 -> mod=10
    [lit] 1 + [lit] 8 *                           \ 8 * (slot+1)
    [lit] 0 swap - cc-emit-4le                    \ negate; low 4 bytes = disp32
  then, ;

\ mov rdi, [rbp + disp]:  48 8B 7D <disp8>  (or 48 8B BD <disp32>)
: cc-emit-load-local                              ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit] 125 cc-emit-local-ea ;

\ mov [rbp + disp], rdi:  48 89 7D <disp8>  (or 48 89 BD <disp32>)
: cc-emit-store-local                             ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 125 cc-emit-local-ea ;

\ lea rdi, [rbp + disp]:  48 8D 7D <disp8>  (or 48 8D BD <disp32>)
\ ModR/M(mod=01, reg=rdi=7, rm=rbp=5) = 0x7D.  Loads the *address* of the local
\ slot into rdi (used to implement `&local`).
: cc-emit-lea-rdi-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 141 cc-emit-byte
  [lit] 125 cc-emit-local-ea ;

\ mov rdi, [rdi]:  48 8B 3F
\ ModR/M(mod=00, reg=rdi=7, rm=rdi=7) = 0x3F.  Loads the qword at the address
\ currently in rdi into rdi (dereference).
: cc-emit-load-via-rdi
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  63 cc-emit-byte ;

\ movzx rdi, BYTE PTR [rdi]:  48 0F B6 3F
\ Zero-extends a single byte from [rdi] into rdi.  Used by `s[i]` rvalue use
\ where s is `char*` (or any other byte-element access path).
: cc-emit-load-byte-via-rdi
  [lit]  72 cc-emit-byte
  [lit]  15 cc-emit-byte
  [lit] 182 cc-emit-byte
  [lit]  63 cc-emit-byte ;

\ mov [rcx], rdi:  48 89 39
\ ModR/M(mod=00, reg=rdi=7, rm=rcx=1) = 0x39.  Stores rdi to the qword address
\ in rcx (assignment via dereference).
: cc-emit-store-via-rcx
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  57 cc-emit-byte ;

\ mov BYTE PTR [rcx], dil:  40 88 39
\ Stores the low byte of rdi to [rcx].  REX=0x40 is needed to select dil
\ instead of bh.  Used by `s[i] = c;` where s is char*.
: cc-emit-store-byte-via-rcx
  [lit]  64 cc-emit-byte
  [lit] 136 cc-emit-byte
  [lit]  57 cc-emit-byte ;

\ shl rdi, imm8:  48 C1 E7 <imm8>
\ ModR/M(mod=11, reg=/4 = SHL, rm=rdi=7) = 11_100_111 = 0xE7.  Multiplies rdi
\ by 2^imm8 (used to scale array index by sizeof(T) when T is 8 bytes).
: cc-emit-shl-rdi-imm8                            ( imm8 -- )
  [lit]  72 cc-emit-byte
  [lit] 193 cc-emit-byte
  [lit] 231 cc-emit-byte
  cc-emit-byte ;

\ Convenience: rdi <<= 3 (multiply by 8 = sizeof(int)/sizeof(ptr)).
: cc-emit-shl-rdi-3   [lit] 3 cc-emit-shl-rdi-imm8 ;

\ add rdi, imm32:  48 81 C7 <imm32>
\ ModR/M(mod=11, reg=/0 = ADD, rm=rdi=7) = 11_000_111 = 0xC7.  Used to bias
\ a struct base/pointer in rdi by a field offset.  imm32 is sign-extended.
: cc-emit-add-rdi-imm32                           ( imm32 -- )
  [lit]  72 cc-emit-byte
  [lit] 129 cc-emit-byte
  [lit] 199 cc-emit-byte
  cc-emit-4le ;

\ Param-spill helpers: store the SYS-V argument register holding the i'th
\ argument into local slot i.  Each one is `mov [rbp + disp8], <reg>`.
\ ModR/M byte: mod=01 (disp8), rm=rbp(=5).  reg field varies per source reg.
\ REX byte is 48 (W only) for rsi/rdx/rcx, 4C (W+R) for r8/r9.
\
\   reg=rsi(6): 01_110_101 = 0x75
\   reg=rdx(2): 01_010_101 = 0x55
\   reg=rcx(1): 01_001_101 = 0x4D
\   reg=r8 (0 with R bit): 01_000_101 = 0x45
\   reg=r9 (1 with R bit): 01_001_101 = 0x4D

: cc-emit-store-local-from-rsi                    ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 117 cc-emit-local-ea ;                    \ 0x75

: cc-emit-store-local-from-rdx                    ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  85 cc-emit-local-ea ;                    \ 0x55

: cc-emit-store-local-from-rcx                    ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  77 cc-emit-local-ea ;                    \ 0x4D

: cc-emit-store-local-from-r8                     ( slot -- )
  [lit]  76 cc-emit-byte                          \ REX.W+R = 0x4C
  [lit] 137 cc-emit-byte
  [lit]  69 cc-emit-local-ea ;                    \ 0x45

: cc-emit-store-local-from-r9                     ( slot -- )
  [lit]  76 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  77 cc-emit-local-ea ;                    \ 0x4D

\ mov rax, [rbp + disp]:  48 8B 45 <disp8>  (or 48 8B 85 <disp32>)
\ ModR/M(mod=01, reg=rax=0, rm=rbp=5) = 01_000_101 = 0x45.  Used to load a
\ function-pointer local into rax just before an indirect `call rax` — keeps
\ rdi/rsi/etc. (already loaded with SYS-V args) untouched.
: cc-emit-load-local-into-rax                     ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  69 cc-emit-local-ea ;                    \ 0x45

\ call rax:  FF D0   (no REX needed; rax = reg 0).
\ ModR/M(mod=11, reg=/2 = CALL r/m64, rm=rax=0) = 11_010_000 = 0xD0.
: cc-emit-call-rax
  [lit] 255 cc-emit-byte
  [lit] 208 cc-emit-byte ;

\ ===========================================================================
\ Register-to-register moves
\ ===========================================================================
\ ADD/SUB/IMUL r/m64, r64 has reg-field=src, rm-field=dst.  We use rdi as the
\ destination accumulator and rcx for the right-operand temp.

\ mov rcx, rdi:  48 89 F9     (89 /r, mod=11 reg=rdi=7 rm=rcx=1 -> 11_111_001 = F9)
: cc-emit-mov-rcx-rdi
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 249 cc-emit-byte ;

\ mov rax, rdi:  48 89 F8     (mod=11 reg=rdi=7 rm=rax=0 -> 11_111_000 = F8)
: cc-emit-mov-rax-rdi
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 248 cc-emit-byte ;

\ mov rdi, rax:  48 89 C7     (mod=11 reg=rax=0 rm=rdi=7 -> 11_000_111 = C7)
\ Used after a function call to transfer the SYS-V return value into our
\ scratch rdi so the rest of the expression machinery sees it.
: cc-emit-mov-rdi-rax
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 199 cc-emit-byte ;

\ mov rbx, rdi:  48 89 FB   (89 /r, mod=11 reg=rdi=7 rm=rbx=3 -> 11_111_011 = FB)
\ Used at switch entry to stash the scrutinee in a callee-saved register so
\ it survives across case-body codegen (including any function calls).
: cc-emit-mov-rbx-rdi
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 251 cc-emit-byte ;

\ cmp rbx, imm32:  48 81 FB <imm32>   (81 /7, mod=11 /7=111 rm=rbx=3 -> FB)
\ Used by switch dispatch to compare the saved scrutinee against each case
\ constant.  Sets ZF iff rbx == imm32.  imm32 is sign-extended to 64 bits.
: cc-emit-cmp-rbx-imm32                           ( v -- )
  [lit]  72 cc-emit-byte
  [lit] 129 cc-emit-byte
  [lit] 251 cc-emit-byte
  cc-emit-4le ;

\ xor rax, rax:  48 31 C0     (zero rax in 3 bytes; for implicit return).
: cc-emit-xor-rax-rax
  [lit]  72 cc-emit-byte
  [lit]  49 cc-emit-byte
  [lit] 192 cc-emit-byte ;

\ ===========================================================================
\ ALU on rdi using rcx as the right operand
\ ===========================================================================
\ The binary-op pattern emitted by the parser is:
\     <eval left>          ; rdi = left
\     push rdi
\     <eval right>         ; rdi = right
\     mov rcx, rdi         ; rcx = right
\     pop rdi              ; rdi = left
\     <op> rdi, rcx        ; rdi = left <op> right
\
\ ADD r/m64, r64 (0x01 /r): rm=dst, reg=src.
\   add rdi, rcx -> mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111 = 0xCF
: cc-emit-add-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]   1 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ SUB r/m64, r64 (0x29 /r): same encoding shape.
\   sub rdi, rcx -> 0xCF
: cc-emit-sub-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  41 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ IMUL r64, r/m64 (0x0F AF /r): reg=dst, rm=src (NOTE the operand order is
\ flipped from add/sub).
\   imul rdi, rcx -> mod=11 reg=rdi=7 rm=rcx=1 -> 11_111_001 = 0xF9
: cc-emit-imul-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte
  [lit] 249 cc-emit-byte ;

\ Signed division: idiv divides rdx:rax by r/m64, leaving quotient in rax,
\ remainder in rdx.  We want rdi := rdi / rcx (or rdi % rcx).  Sequence:
\     mov rax, rdi      ; 48 89 F8
\     cqo               ; 48 99            (sign-extend rax into rdx)
\     idiv rcx          ; 48 F7 F9         (F7 /7, mod=11 rm=rcx=1 -> 11_111_001=0xF9)
\     mov rdi, rax|rdx  ; 48 89 C7 (rax) or 48 89 D7 (rdx)
: cc-emit-idiv-quotient
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 153 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 247 cc-emit-byte [lit] 249 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 199 cc-emit-byte ;

: cc-emit-idiv-remainder
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 153 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 247 cc-emit-byte [lit] 249 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 215 cc-emit-byte ;

\ ===========================================================================
\ Function prologue / epilogue
\ ===========================================================================
\ Prologue:  push rbp ; mov rbp, rsp ; sub rsp, imm32
\ Epilogue:  mov rsp, rbp ; pop rbp ; ret

: cc-emit-prologue                                ( frame-bytes -- )
  [lit]  85 cc-emit-byte                          \ push rbp
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 229 cc-emit-byte                          \ mov rbp, rsp
  [lit]  72 cc-emit-byte
  [lit] 129 cc-emit-byte
  [lit] 236 cc-emit-byte                          \ sub rsp, imm32 prefix
  cc-emit-4le ;

: cc-emit-epilogue
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 236 cc-emit-byte                          \ mov rsp, rbp
  [lit]  93 cc-emit-byte                          \ pop rbp
  [lit] 195 cc-emit-byte ;                        \ ret

\ ===========================================================================
\ Comparisons: set rdi to 0 or 1 based on signed comparison of left/right.
\ ===========================================================================
\ The binary-op pattern (same as ALU) leaves rdi=left, rcx=right.  Each helper
\ emits 12 bytes:
\     xor rax, rax     48 31 C0
\     cmp rdi, rcx     48 39 CF      (sets flags from rdi - rcx = left - right)
\     setX al          0F 9X C0      (X = 4=E, 5=NE, C=L, D=GE, E=LE, F=G)
\     mov rdi, rax     48 89 C7
\
\ cc-emit-cmp-set ( setX-opcode -- )  Common tail; caller passes the second
\ byte of the setcc opcode (0x94, 0x95, 0x9C, 0x9D, 0x9E, 0x9F).
: cc-emit-cmp-set
  [lit]  72 cc-emit-byte [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor rax,rax
  [lit]  72 cc-emit-byte [lit]  57 cc-emit-byte [lit] 207 cc-emit-byte   \ cmp rdi,rcx
  [lit]  15 cc-emit-byte                                                  \ 0F prefix
  cc-emit-byte                                                            \ setX opcode
  [lit] 192 cc-emit-byte                                                  \ ModR/M for AL
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 199 cc-emit-byte ; \ mov rdi,rax

: cc-emit-cmp-eq  [lit] 148 cc-emit-cmp-set ;     \ 0x94 setE
: cc-emit-cmp-ne  [lit] 149 cc-emit-cmp-set ;     \ 0x95 setNE
: cc-emit-cmp-lt  [lit] 156 cc-emit-cmp-set ;     \ 0x9C setL
: cc-emit-cmp-ge  [lit] 157 cc-emit-cmp-set ;     \ 0x9D setGE
: cc-emit-cmp-le  [lit] 158 cc-emit-cmp-set ;     \ 0x9E setLE
: cc-emit-cmp-gt  [lit] 159 cc-emit-cmp-set ;     \ 0x9F setG

\ ===========================================================================
\ Conditional / unconditional branches with rel32 fixups.
\ ===========================================================================

\ test rdi, rdi  -> 48 85 FF  (sets ZF=1 iff rdi == 0).
: cc-emit-test-rdi
  [lit]  72 cc-emit-byte
  [lit] 133 cc-emit-byte
  [lit] 255 cc-emit-byte ;

\ cc-emit-jz-rel32-placeholder ( -- patch-offset )
\ Emits `0F 84 00 00 00 00`; returns the file-offset of the rel32 cell
\ so the caller can later patch it with cc-patch-rel32-to-here.
: cc-emit-jz-rel32-placeholder
  [lit]  15 cc-emit-byte
  [lit] 132 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-emit-jmp-rel32-placeholder ( -- patch-offset )
\ Emits `E9 00 00 00 00`; returns the rel32 file-offset.
: cc-emit-jmp-rel32-placeholder
  [lit] 233 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-emit-call-rel32-placeholder ( -- patch-offset )
\ Emits `E8 00 00 00 00`; returns the rel32 file-offset.  Used for forward
\ function calls whose target vaddr is not yet known.  The caller threads the
\ patch offset onto a fixup list attached to the callee's prototype symbol;
\ the list is walked and patched when the function is later defined.
: cc-emit-call-rel32-placeholder
  [lit] 232 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-emit-jnz-rel32-placeholder ( -- patch-offset )
\ Emits `0F 85 00 00 00 00`; returns the rel32 file-offset.  Used by `||`'s
\ short-circuit fast-path: if LHS is non-zero, skip RHS and produce 1.
: cc-emit-jnz-rel32-placeholder
  [lit]  15 cc-emit-byte
  [lit] 133 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-patch-rel32-to-here ( patch-offset -- )
\ rel32 = current cc-out-pos - (patch-offset + 4).
: cc-patch-rel32-to-here
  cc-out-pos @                                    ( patch-off target-off )
  over [lit] 4 + -                                ( patch-off rel32 )
  swap cc-out-patch-4le ;

\ NOTE: cc-emit-jmp-vaddr (which emits a backward unconditional jump to an
\ absolute vaddr — needed for `while`/`for` loops) lives in 110-cc-decl.fth
\ because it references cc-base-vaddr from 080-cc-elf.fth, which is loaded AFTER
\ 090-cc-emit.fth.

\ ===========================================================================
\ movabs rdi, imm64 — used for loading string-literal addresses.
\ ===========================================================================
\ Encoding: 48 BF <imm64-LE>  (10 bytes total).

: cc-emit-movabs-rdi-imm64                        ( v -- )
  [lit]  72 cc-emit-byte                          \ REX.W
  [lit] 191 cc-emit-byte                          \ B7 + rdi (7) = BF
  cc-emit-8le ;

\ cc-emit-mov-rdi-int ( v -- )  Load an integer literal into rdi using the
\ shortest correct encoding.  `mov rdi, imm32` (5 bytes) sign-extends its
\ 32-bit field, so it only represents values in signed-32 range; a wider
\ constant (e.g. 0x80000000 or 2^32) would be sign-extended or truncated.
\ For those, fall back to the 10-byte `movabs rdi, imm64`.  C literals are
\ always non-negative here (a leading `-` is unary minus, applied later), so
\ only the upper bound needs checking — which keeps every in-range constant
\ on the exact imm32 bytes it emitted before.
: cc-emit-mov-rdi-int                             ( v -- )
  dup [lit] 2147483647 > if,
    cc-emit-movabs-rdi-imm64
  else,
    cc-emit-mov-rdi-imm32
  then, ;

\ cc-emit-movabs-rdi-imm64-placeholder ( -- patch-offset )
\ Emits `48 BF 00 00 00 00 00 00 00 00`; returns the imm64 file-offset.
\ Used when a forward-declared function's name is taken as an rvalue
\ (function-pointer load) before its definition is reached.  Caller threads
\ patch-offset onto cc-sym-extra2 of the function's prototype symbol; the
\ list is walked and each 8-byte imm64 is patched to the function's real
\ vaddr when cc-parse-function processes its definition.
: cc-emit-movabs-rdi-imm64-placeholder
  [lit]  72 cc-emit-byte
  [lit] 191 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-8le ;

\ cc-add-fixup-to-list ( fixup-offset list-var -- )  Allocate a 16-byte node
\ and prepend it to the linked list rooted at list-var.  Defined here so
\ 100-cc-expr.fth (loaded before 110-cc-decl.fth) can reference it from the
\ forward-function-rvalue path in cc-parse-primary.
: cc-add-fixup-to-list                            ( off var -- )
  [lit] 16 cc-alloc                               ( off var node )
  >r                                              ( off var ; R: node )
  swap r@ !                                       ( var ; R: node )
  dup @ r@ [lit] 8 + !                            ( var ; R: node )
  r> swap ! ;                                     ( -- )

\ ===========================================================================
\ String-literal byte emission with C-escape decoding.
\ ===========================================================================
\ Walks ( src-addr src-len ) and copies bytes into cc-out-buf, decoding
\ \n, \t, \r, \\, \', \", and \0.  Other escape characters pass through
\ literally (matches cc-lex-char behaviour).  Appends a trailing NUL byte.
\
\ Stack convention inside the loop: ( src len ).

: cc-emit-string-bytes                            ( src-addr src-len -- )
  begin,
    dup [lit] 0 >
  while,
    over c@ [lit] 92 = if,                        \ '\\' (backslash)
      dup [lit] 2 >= if,
        \ Have at least one more byte for the escape.
        over [lit] 1 + c@                         ( src len escaped )
        dup [lit] 110 = if, drop [lit] 10 else,   \ \n
        dup [lit] 116 = if, drop [lit]  9 else,   \ \t
        dup [lit] 114 = if, drop [lit] 13 else,   \ \r
        dup [lit]  92 = if, drop [lit] 92 else,   \ \\
        dup [lit]  39 = if, drop [lit] 39 else,   \ \'
        dup [lit]  34 = if, drop [lit] 34 else,   \ \"
        dup [lit]  48 = if, drop [lit]  0 else,   \ \0
          \ Default: pass the escaped char through unchanged.
        then, then, then, then, then, then, then,
        cc-emit-byte
        \ Advance src by 2, decrement len by 2.
        swap [lit] 2 + swap [lit] 2 -
      else,
        \ Trailing backslash with no follow-up char: emit literally.
        over c@ cc-emit-byte
        swap [lit] 1 + swap [lit] 1 -
      then,
    else,
      over c@ cc-emit-byte
      swap [lit] 1 + swap [lit] 1 -
    then,
  repeat,
  drop drop
  [lit] 0 cc-emit-byte ;                          \ trailing NUL terminator

\ ===========================================================================
\ Built-in libc shims (putchar, exit, getchar) emitted at the start of
\ the code segment so user code can call them via the standard call path.
\ ===========================================================================
\
\ All three shims follow SYS-V x86-64 calling convention: the first arg is in
\ rdi, the return value comes back in rax, and the call site converts rax to
\ rdi via cc-emit-mov-rdi-rax (already done by cc-parse-call).
\
\ NOTE on stack: each shim is entered with rsp ≡ 8 mod 16 (caller pushed the
\ return address from a 16-aligned base).  putchar and getchar each do one
\ `push` before the syscall, restoring rsp ≡ 0 mod 16.  Linux syscalls don't
\ care about ABI alignment, so this keeps the shim prologues uniform.

\ -- putchar(int c): write the low byte of rdi to fd 1.  29 bytes.
\
\   push rdi             57
\   mov rax, 1           48 C7 C0 01 00 00 00     (write syscall #)
\   mov rdi, 1           48 C7 C7 01 00 00 00     (fd = stdout)
\   mov rsi, rsp         48 89 E6                 (buffer = pushed qword's first byte)
\   mov rdx, 1           48 C7 C2 01 00 00 00     (count = 1)
\   syscall              0F 05
\   pop rdi              5F                       (restore rsp)
\   ret                  C3
: cc-emit-putchar-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rax, 1
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 199 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rdi, 1
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 230 cc-emit-byte
                                                  \ mov rsi, rsp
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 194 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rdx, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- exit(int n): syscall 60 with rdi = n.  10 bytes.
\
\   mov rax, 60          48 C7 C0 3C 00 00 00
\   syscall              0F 05
\   ret                  C3                        (unreachable but tidy)
: cc-emit-exit-shim
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit]  60 cc-emit-4le                           \ mov rax, 60
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- getchar(void): read 1 byte from fd 0; return -1 on EOF.  48 bytes.
\
\   push rdi             57                          (reserve 8B scratch on stack)
\   mov rax, 0           48 C7 C0 00 00 00 00        (read syscall #)
\   mov rdi, 0           48 C7 C7 00 00 00 00        (fd = stdin)
\   mov rsi, rsp         48 89 E6
\   mov rdx, 1           48 C7 C2 01 00 00 00
\   syscall              0F 05
\   test rax, rax        48 85 C0
\   jnz .have            75 09                       (skip 9 bytes -> movzx)
\   mov rax, -1          48 C7 C0 FF FF FF FF
\   jmp .done            EB 05                       (skip 5 bytes -> pop rdi)
\ .have:
\   movzx rax, byte [rsp] 48 0F B6 04 24
\ .done:
\   pop rdi              5F
\   ret                  C3
: cc-emit-getchar-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit]   0 cc-emit-4le                           \ mov rax, 0
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 199 cc-emit-byte
  [lit]   0 cc-emit-4le                           \ mov rdi, 0
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 230 cc-emit-byte
                                                  \ mov rsi, rsp
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 194 cc-emit-byte
  [lit]   1 cc-emit-4le                           \ mov rdx, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte [lit] 192 cc-emit-byte
                                                  \ test rax, rax
  [lit] 117 cc-emit-byte [lit]   9 cc-emit-byte   \ jnz +9 (skip mov+jmp)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte [lit] 192 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte   \ mov rax, -1 (sign-extended imm32 = FFFFFFFF)
  [lit] 235 cc-emit-byte [lit]   5 cc-emit-byte   \ jmp +5 (skip movzx)
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 182 cc-emit-byte [lit]   4 cc-emit-byte
  [lit]  36 cc-emit-byte                          \ movzx rax, byte [rsp]
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit] 195 cc-emit-byte ;                        \ ret

\ ===========================================================================
\ Libc shims: fputs, fputc, fopen, fclose, fwrite, fread, calloc,
\ free.  All follow SYS-V x86-64 ABI.  Symbol registration and
\ vaddr assignment happen in cc-emit-shims (110-cc-decl.fth).
\ ===========================================================================

\ -- fputs(char *s, FILE *fp) -> non-negative on success.  33 bytes.
\
\   push rdi           57                    (save str)
\   push rsi           56                    (save fd)
\   xor rdx, rdx       48 31 D2              (length counter)
\ .loop:
\   movzx ecx, [rdi+rdx]  0F B6 0C 17       SIB: idx=rdx(2) base=rdi(7)
\   test cl, cl            84 C9
\   jz +5  (.done)         74 05
\   inc rdx                48 FF C2
\   jmp .loop              EB F3             (disp = -13)
\ .done:
\   mov rax, 1         48 C7 C0 01 00 00 00  (write)
\   mov rsi, rdi       48 89 FE              (buf = str)
\   pop rdi            5F                    (fd = saved rsi slot)
\   pop rcx            59                    (discard saved str)
\   syscall            0F 05
\   ret                C3
: cc-emit-fputs-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  86 cc-emit-byte                          \ push rsi
  [lit]  72 cc-emit-byte [lit]  49 cc-emit-byte
  [lit] 210 cc-emit-byte                          \ xor rdx, rdx
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]  12 cc-emit-byte [lit]  23 cc-emit-byte   \ movzx ecx, [rdi+rdx]
  [lit] 132 cc-emit-byte [lit] 201 cc-emit-byte   \ test cl, cl
  [lit] 116 cc-emit-byte [lit]   5 cc-emit-byte   \ jz +5
  [lit]  72 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 194 cc-emit-byte                          \ inc rdx
  [lit] 235 cc-emit-byte [lit] 243 cc-emit-byte   \ jmp .loop  (disp = -13)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rax, 1
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 254 cc-emit-byte                          \ mov rsi, rdi  (buf)
  [lit]  95 cc-emit-byte                          \ pop rdi  (fd)
  [lit]  89 cc-emit-byte                          \ pop rcx  (discard str)
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fputc(int c, FILE *fp) -> c on success.  30 bytes.
\
\   push rdi           57                    (char onto stack = write buffer)
\   mov rax, 1         48 C7 C0 01 00 00 00
\   mov rdi, rsi       48 89 F7              (fd = arg2)
\   mov rsi, rsp       48 89 E6              (buf = stack)
\   mov rdx, 1         48 C7 C2 01 00 00 00
\   syscall            0F 05
\   movzx eax, [rsp]   0F B6 04 24           (return char)
\   pop rcx            59
\   ret                C3
: cc-emit-fputc-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rax, 1
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 247 cc-emit-byte                          \ mov rdi, rsi  (fd)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 230 cc-emit-byte                          \ mov rsi, rsp  (buf)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 194 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rdx, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]   4 cc-emit-byte [lit]  36 cc-emit-byte   \ movzx eax, [rsp]
  [lit]  89 cc-emit-byte                          \ pop rcx
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fopen(char *path, char *mode) -> fd on success, 0 on error.  51 bytes.
\
\   push rdi           57
\   movzx eax, [rsi]   0F B6 06              (first char of mode)
\   xor esi, esi       31 F6                 (flags = O_RDONLY = 0)
\   cmp eax, 119       83 F8 77              ('w')
\   jne +7  (.try_a)   75 07
\   mov esi, 0x241     BE 41 02 00 00        (O_WRONLY|O_CREAT|O_TRUNC)
\   jmp +10  (.open)   EB 0A
\ .try_a:
\   cmp eax, 97        83 F8 61              ('a')
\   jne +5  (.open)    75 05
\   mov esi, 0x441     BE 41 04 00 00        (O_WRONLY|O_CREAT|O_APPEND)
\ .open:
\   pop rdi            5F
\   mov rax, 2         48 C7 C0 02 00 00 00  (open syscall)
\   mov edx, 420       BA A4 01 00 00        (mode 0644)
\   syscall            0F 05
\   test rax, rax      48 85 C0
\   jns +2  (.ok)      79 02
\   xor eax, eax       31 C0                 (return NULL on error)
\ .ok:
\   ret                C3
: cc-emit-fopen-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  15 cc-emit-byte [lit] 182 cc-emit-byte
  [lit]   6 cc-emit-byte                          \ movzx eax, [rsi]
  [lit]  49 cc-emit-byte [lit] 246 cc-emit-byte   \ xor esi, esi
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte
  [lit] 119 cc-emit-byte                          \ cmp eax, 'w'
  [lit] 117 cc-emit-byte [lit]   7 cc-emit-byte   \ jne +7
  [lit] 190 cc-emit-byte [lit] 577 cc-emit-4le    \ mov esi, 0x241
  [lit] 235 cc-emit-byte [lit]  10 cc-emit-byte   \ jmp +10
  [lit] 131 cc-emit-byte [lit] 248 cc-emit-byte
  [lit]  97 cc-emit-byte                          \ cmp eax, 'a'
  [lit] 117 cc-emit-byte [lit]   5 cc-emit-byte   \ jne +5
  [lit] 190 cc-emit-byte [lit] 1089 cc-emit-4le   \ mov esi, 0x441
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   2 cc-emit-4le    \ mov rax, 2
  [lit] 186 cc-emit-byte [lit] 420 cc-emit-4le    \ mov edx, 0644
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 121 cc-emit-byte [lit]   2 cc-emit-byte   \ jns +2
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fclose(FILE *fp) -> 0.  12 bytes.
\
\   mov rax, 3    48 C7 C0 03 00 00 00  (close syscall)
\   syscall       0F 05
\   xor eax, eax  31 C0
\   ret           C3
: cc-emit-fclose-shim
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   3 cc-emit-4le    \ mov rax, 3
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fwrite(void *ptr, size_t sz, size_t n, FILE *fp) -> bytes written.  20 bytes.
\
\   imul rdx, rsi  48 0F AF D6   (total = n * sz;  rdx=n, rsi=sz)
\   mov rsi, rdi   48 89 FE      (buf = ptr)
\   mov rdi, rcx   48 89 CF      (fd = arg4)
\   mov rax, 1     48 C7 C0 01 00 00 00
\   syscall        0F 05
\   ret            C3
: cc-emit-fwrite-shim
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte [lit] 214 cc-emit-byte   \ imul rdx, rsi
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 254 cc-emit-byte                          \ mov rsi, rdi  (buf)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 207 cc-emit-byte                          \ mov rdi, rcx  (fd)
  [lit]  72 cc-emit-byte [lit] 199 cc-emit-byte
  [lit] 192 cc-emit-byte [lit]   1 cc-emit-4le    \ mov rax, 1
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- fread(void *ptr, size_t sz, size_t n, FILE *fp) -> elements read.  30 bytes.
\
\   push rsi         56               (save sz)
\   imul rsi, rdx    48 0F AF F2      (total = sz * n)
\   mov rdx, rsi     48 89 F2         (count)
\   mov rsi, rdi     48 89 FE         (buf = ptr)
\   mov rdi, rcx     48 89 CF         (fd = arg4)
\   xor eax, eax     31 C0            (read = 0)
\   syscall          0F 05
\   pop rcx          59               (restore sz)
\   test rax, rax    48 85 C0
\   jle +5  (.done)  7E 05
\   xor edx, edx     31 D2            (clear for div)
\   div rcx          48 F7 F1         (rax = bytes_read / sz)
\ .done:
\   ret              C3
: cc-emit-fread-shim
  [lit]  86 cc-emit-byte                          \ push rsi
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte [lit] 242 cc-emit-byte   \ imul rsi, rdx
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 242 cc-emit-byte                          \ mov rdx, rsi  (count)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 254 cc-emit-byte                          \ mov rsi, rdi  (buf)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 207 cc-emit-byte                          \ mov rdi, rcx  (fd)
  [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor eax, eax
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  89 cc-emit-byte                          \ pop rcx  (sz)
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 126 cc-emit-byte [lit]   5 cc-emit-byte   \ jle +5
  [lit]  49 cc-emit-byte [lit] 210 cc-emit-byte   \ xor edx, edx
  [lit]  72 cc-emit-byte [lit] 247 cc-emit-byte
  [lit] 241 cc-emit-byte                          \ div rcx
  [lit] 195 cc-emit-byte ;                        \ ret

\ -- calloc(size_t n, size_t sz) -> zeroed memory or NULL.  113 bytes.
\
\ Bump allocator backed by a single 256 MB mmap.  heap_base and heap_pos
\ are stored as inline 8-byte data slots immediately after the ret.
\ All RIP-relative displacements are fixed because the shim is a closed
\ region; the offsets below are exact (verified by hand):
\
\   heap_base @ shim_offset 97  (rip+0x58 from @2, rip+0x2A from @48)
\   heap_pos  @ shim_offset 105 (rip+0x2B from @55, rip+0x16 from @76,
\                                 rip+0x09 from @89)
\
\   push rdi                    57
\   push rsi                    56
\   mov rax, [rip+0x58]         48 8B 05 58 00 00 00  (heap_base)
\   test rax, rax               48 85 C0
\   jnz +48  (.have_heap)       75 30
\   xor edi, edi                31 FF
\   mov esi, 0x10000000         BE 00 00 00 10
\   mov edx, 3                  BA 03 00 00 00   (PROT_READ|PROT_WRITE)
\   mov r10d, 0x22              41 BA 22 00 00 00  (MAP_PRIVATE|MAP_ANONYMOUS)
\   mov r8d, -1                 41 B8 FF FF FF FF  (no fd)
\   xor r9d, r9d                45 31 C9           (offset=0)
\   mov eax, 9                  B8 09 00 00 00     (mmap)
\   syscall                     0F 05
\   mov [rip+0x2A], rax         48 89 05 2A 00 00 00  (heap_base)
\   mov [rip+0x2B], rax         48 89 05 2B 00 00 00  (heap_pos)
\ .have_heap:
\   pop rsi                     5E
\   pop rdi                     5F
\   imul rdi, rsi               48 0F AF FE   (total = n*sz)
\   add rdi, 7                  48 83 C7 07   (align8)
\   and rdi, -8                 48 83 E7 F8
\   mov rax, [rip+0x16]         48 8B 05 16 00 00 00  (heap_pos = cur)
\   mov rcx, rax                48 89 C1
\   add rcx, rdi                48 01 F9      (new_pos = cur + size)
\   mov [rip+0x09], rcx         48 89 0D 09 00 00 00  (heap_pos = new_pos)
\   ret                         C3
\   heap_base: 8 zero bytes     (mmap is zero-filled by Linux)
\   heap_pos:  8 zero bytes
: cc-emit-calloc-shim
  [lit]  87 cc-emit-byte                          \ push rdi
  [lit]  86 cc-emit-byte                          \ push rsi
  [lit]  72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  88 cc-emit-4le    \ mov rax, [rip+0x58]
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte
  [lit] 192 cc-emit-byte                          \ test rax, rax
  [lit] 117 cc-emit-byte [lit]  48 cc-emit-byte   \ jnz +48 (.have_heap)
  [lit]  49 cc-emit-byte [lit] 255 cc-emit-byte   \ xor edi, edi
  [lit] 190 cc-emit-byte [lit] 268435456 cc-emit-4le  \ mov esi, 0x10000000 (256 MB heap)
  [lit] 186 cc-emit-byte [lit]   3 cc-emit-4le    \ mov edx, 3
  [lit]  65 cc-emit-byte [lit] 186 cc-emit-byte
  [lit]  34 cc-emit-4le                           \ mov r10d, 0x22
  [lit]  65 cc-emit-byte [lit] 184 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte
  [lit] 255 cc-emit-byte [lit] 255 cc-emit-byte   \ mov r8d, -1  (4 explicit bytes)
  [lit]  69 cc-emit-byte [lit]  49 cc-emit-byte
  [lit] 201 cc-emit-byte                          \ xor r9d, r9d
  [lit] 184 cc-emit-byte [lit]   9 cc-emit-4le    \ mov eax, 9
  [lit]  15 cc-emit-byte [lit]   5 cc-emit-byte   \ syscall
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  42 cc-emit-4le    \ mov [rip+0x2A], rax (heap_base)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  43 cc-emit-4le    \ mov [rip+0x2B], rax (heap_pos)
  [lit]  94 cc-emit-byte                          \ pop rsi
  [lit]  95 cc-emit-byte                          \ pop rdi
  [lit]  72 cc-emit-byte [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte [lit] 254 cc-emit-byte   \ imul rdi, rsi
  [lit]  72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 199 cc-emit-byte [lit]   7 cc-emit-byte   \ add rdi, 7
  [lit]  72 cc-emit-byte [lit] 131 cc-emit-byte
  [lit] 231 cc-emit-byte [lit] 248 cc-emit-byte   \ and rdi, -8
  [lit]  72 cc-emit-byte [lit] 139 cc-emit-byte
  [lit]   5 cc-emit-byte [lit]  22 cc-emit-4le    \ mov rax, [rip+0x16] (heap_pos)
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit] 193 cc-emit-byte                          \ mov rcx, rax
  [lit]  72 cc-emit-byte [lit]   1 cc-emit-byte
  [lit] 249 cc-emit-byte                          \ add rcx, rdi
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte
  [lit]  13 cc-emit-byte [lit]   9 cc-emit-4le    \ mov [rip+0x09], rcx (heap_pos)
  [lit] 195 cc-emit-byte                          \ ret
  [lit]   0 cc-emit-8le                           \ heap_base = 0
  [lit]   0 cc-emit-8le ;                         \ heap_pos  = 0

\ -- free(void *p) -> void.  1 byte.  No-op: bump allocator never frees.
: cc-emit-free-shim
  [lit] 195 cc-emit-byte ;                        \ ret

\ ===========================================================================
\ Shifts, bitwise ops, inc/dec/neg/not on rdi
\ ===========================================================================
\ Variable-count shifts use rcx (specifically CL).  The binary-op pattern
\ leaves rdi=left and rcx=right (already in rcx because of mov rcx,rdi+pop).
\
\ shl rdi, cl: 48 D3 E7   (D3 /4, mod=11 rm=rdi=7 -> 11_100_111=0xE7)
: cc-emit-shl-rdi-cl
  [lit]  72 cc-emit-byte
  [lit] 211 cc-emit-byte
  [lit] 231 cc-emit-byte ;

\ sar rdi, cl (arithmetic right shift, signed): 48 D3 FF  (D3 /7 -> 11_111_111=0xFF)
: cc-emit-sar-rdi-cl
  [lit]  72 cc-emit-byte
  [lit] 211 cc-emit-byte
  [lit] 255 cc-emit-byte ;

\ and rdi, rcx: 48 21 CF  (21 /r, mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111=0xCF)
: cc-emit-and-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  33 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ or rdi, rcx: 48 09 CF
: cc-emit-or-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]   9 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ xor rdi, rcx: 48 31 CF
: cc-emit-xor-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  49 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ not rdi: 48 F7 D7  (F7 /2 = NOT, mod=11 rm=rdi=7 -> 11_010_111=0xD7)
: cc-emit-not-rdi
  [lit]  72 cc-emit-byte
  [lit] 247 cc-emit-byte
  [lit] 215 cc-emit-byte ;

\ neg rdi: 48 F7 DF  (F7 /3 = NEG, mod=11 rm=rdi=7 -> 11_011_111=0xDF)
: cc-emit-neg-rdi
  [lit]  72 cc-emit-byte
  [lit] 247 cc-emit-byte
  [lit] 223 cc-emit-byte ;

\ inc qword [rbp + disp]: 48 FF 45 <disp8>  (or 48 FF 85 <disp32>)
\ ModR/M(mod=01, reg=/0=INC, rm=rbp=5) = 01_000_101 = 0x45.  Increments the
\ local slot in place without disturbing rdi/rcx (used by post-increment).
: cc-emit-inc-mem-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 255 cc-emit-byte
  [lit]  69 cc-emit-local-ea ;

\ dec qword [rbp + disp]: 48 FF 4D <disp8>  (or 48 FF 8D <disp32>)
\ ModR/M(mod=01, reg=/1=DEC, rm=rbp=5) = 01_001_101 = 0x4D.
: cc-emit-dec-mem-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 255 cc-emit-byte
  [lit]  77 cc-emit-local-ea ;

\ cc-emit-not-zero-flag.  Canonicalize rdi to 0/1 = (rdi == 0).
\ Pattern: xor rax,rax; test rdi,rdi; sete al; mov rdi,rax.  Used by unary '!'.
: cc-emit-not-zero-flag
  [lit]  72 cc-emit-byte [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte
                                                  \ xor rax,rax
  [lit]  72 cc-emit-byte [lit] 133 cc-emit-byte [lit] 255 cc-emit-byte
                                                  \ test rdi,rdi
  [lit]  15 cc-emit-byte [lit] 148 cc-emit-byte [lit] 192 cc-emit-byte
                                                  \ sete al
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 199 cc-emit-byte ;
                                                  \ mov rdi,rax

\ ===========================================================================
\ File-scope global variables.
\ ===========================================================================
\ Globals are accumulated in a parallel buffer (cc-globals-buf) during
\ parsing.  Each global gets a SLOT offset into that buffer (0 for the first
\ one, +8 for each subsequent qword, +N*8 for arrays).  Initializer bytes
\ are written directly into cc-globals-buf at the slot offset; uninitialized
\ globals stay zero (Forth `allot` zeroes the memory).
\
\ At codegen time, an IDENT referring to a sk-global emits
\     movabs rdi, <imm64 placeholder = 0>          ; 10 bytes
\ and records (patch-offset-in-cc-out-buf, slot) into the cc-gfixup arrays.
\
\ At cc-finalize-globals (called after parsing, before cc-finalize-elf):
\   1. cc-globals-base-vaddr := cc-base-vaddr + cc-out-pos@.
\   2. Append cc-globals-buf bytes to cc-out-buf.
\   3. For each fixup, compute vaddr = cc-globals-base-vaddr + slot, then
\      patch the placeholder imm64 in cc-out-buf at the recorded patch-offset.
\
\ This places the globals immediately after the code in the same PT_LOAD
\ segment — no holes, no extra phdr.

[lit] 4096 constant cc-globals-cap
create cc-globals-buf  cc-globals-cap allot
variable cc-globals-pos

\ Capacity for deferred global-vaddr fixups.  M2-Planet's cc_core.c emits
\ ~891 global references — 256 is far too low; 4096 gives healthy headroom.
[lit] 4096 constant cc-gfixup-cap
create cc-gfixup-out-pos  cc-gfixup-cap [lit] 8 * allot
create cc-gfixup-slot     cc-gfixup-cap [lit] 8 * allot
variable cc-gfixup-count

variable cc-globals-base-vaddr                   \ set by cc-finalize-globals

\ cc-globals-init ( -- )  Reset globals + fixup state at the start of compile.
: cc-globals-init
  [lit] 0 cc-globals-pos !
  [lit] 0 cc-gfixup-count !
  [lit] 0 cc-globals-base-vaddr !
  \ Zero the globals buffer so uninitialized globals are guaranteed zero
  \ even if a previous run left bytes in there.  Loop walks i = 0..cap-1.
  [lit] 0
  begin, dup cc-globals-cap < while,
    [lit] 0 over cc-globals-buf + c!
    [lit] 1 +
  repeat, drop ;

\ cc-globals-alloc ( bytes -- slot )  Reserve `bytes` bytes; return the offset
\ of the first reserved byte.  Aborts if cc-globals-buf would overflow.
: cc-globals-alloc                                 ( bytes -- slot )
  cc-globals-pos @                                 ( bytes slot )
  swap                                              ( slot bytes )
  cc-globals-pos +!
  cc-globals-pos @ cc-globals-cap > if,
    [lit] 70 die
  then, ;

\ cc-globals-store-8le ( v slot -- )  Write `v` as 8-byte LE into globals-buf
\ at the given slot offset.
: cc-globals-store-8le                             ( v slot -- )
  cc-globals-buf +                                 ( v addr )
  >r                                                ( v ; R: addr )
  dup r@                       c!
  [lit] 256 / dup r@ [lit] 1 + c!
  [lit] 256 / dup r@ [lit] 2 + c!
  [lit] 256 / dup r@ [lit] 3 + c!
  [lit] 256 / dup r@ [lit] 4 + c!
  [lit] 256 / dup r@ [lit] 5 + c!
  [lit] 256 / dup r@ [lit] 6 + c!
  [lit] 256 /     r> [lit] 7 + c! ;

\ cc-gfixup-add ( patch-offset slot -- )  Record a deferred global-vaddr fixup.
\ Uses sym-slot (from 070-cc-sym.fth, signature `( id arr -- addr )`) since it's a
\ generic helper that just computes arr + 8*id.
: cc-gfixup-add                                    ( patch-off slot -- )
  cc-gfixup-count @ dup cc-gfixup-cap >= if,
    [lit] 71 die
  then,
  ( patch-off slot i )
  >r                                                \ park i on rstack
  r@ cc-gfixup-slot     sym-slot !                 \ store slot
  r@ cc-gfixup-out-pos  sym-slot !                 \ store patch-off
  r> drop
  [lit] 1 cc-gfixup-count +! ;

\ cc-emit-global-ref ( slot -- )  Emit `movabs rdi, <vaddr placeholder>` and
\ record a deferred fixup so the imm64 will be patched to cc-globals-base-
\ vaddr + slot once globals are placed.  Used by the sk-global IDENT path in
\ cc-parse-primary.
: cc-emit-global-ref                                ( slot -- )
  [lit]  72 cc-emit-byte                            \ REX.W (0x48)
  [lit] 191 cc-emit-byte                            \ B7 + 7 = BF (movabs rdi)
  cc-out-pos @                                      ( slot patch-off )
  [lit] 0 cc-emit-8le                               \ imm64 placeholder
  swap cc-gfixup-add ;
