\ seed/120-cc-main.fth — main entry for the C-subset compiler.
\
\ Reads C source from stdin; emits ELF executable to /tmp/cc-out.
\
\ Load order (strict — do not rearrange):
\   010-lib.fth        — primitives, syscalls, control-flow, defining words
\   020-cc-arena.fth   — bump allocator (must load before 030-cc-io.fth)
\   030-cc-io.fth      — source buffer, output buffer, file I/O
\   040-cc-prep.fth    — preprocessor (#include, #define)
\   050-cc-lex.fth     — tokenizer (depends on 040-cc-prep.fth for macro lookup)
\   060-cc-types.fth   — type encoding (int, char, pointer, struct)
\   070-cc-sym.fth     — symbol table (parallel arrays, scope stack)
\   080-cc-elf.fth     — ELF header emission
\   090-cc-emit.fth    — x86-64 instruction encoders (codegen backend)
\   100-cc-expr.fth    — expression parser (depends on 090-cc-emit.fth)
\   110-cc-decl.fth    — declaration / statement parser (depends on 100-cc-expr.fth)
\   120-cc-main.fth    — entry point: cc-main

\ Pre-baked output path: "/tmp/cc-out\0"
create cc-out-path
[lit]  47 c, [lit] 116 c, [lit] 109 c, [lit] 112 c,    \ /tmp
[lit]  47 c, [lit]  99 c, [lit]  99 c, [lit]  45 c,    \ /cc-
[lit] 111 c, [lit] 117 c, [lit] 116 c, [lit]   0 c,    \ out\0

: cc-main
  cc-load-stdin
  cc-preprocess
  cc-out-init
  cc-globals-init
  cc-emit-elf-header
  cc-parse-program
  cc-finalize-globals
  cc-finalize-elf
  cc-out-path cc-write-output
  bye ;

cc-main
