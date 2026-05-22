# Appendix E — Further reading

This book stands on a small library of older work.  None of it is
required; all of it makes the territory richer.  Pointers are
grouped by what they help with.

## Forth

- **Leo Brodie, *Starting Forth*** (1981; second edition 1987).
  The standard introduction to the language and the canonical
  source for the conventional Forth style.  Free online at
  forth.com.  Read it if you want the *idiomatic* Forth that
  this book deliberately does not teach.

- **Leo Brodie, *Thinking Forth*** (1984).  How to *design* in
  Forth — factoring, vocabularies, decomposition.  Less about
  syntax than about taste.  Also freely available.

- **Brad Rodriguez, "Moving Forth"** (*The Computer Journal*,
  1992–1995).  An eight-part series on Forth implementation
  techniques — threading models (direct, indirect, subroutine,
  token), inner interpreters, primitives in assembly.  This
  book's seed is closest to a subroutine-threaded Forth; "Moving
  Forth" parts 1 and 4 explain that lineage.  Available at
  bradrodriguez.com/papers.

- **Elizabeth D. Rather, Donald R. Colburn, and Charles H. Moore,
  "The Evolution of Forth"** (HOPL II, 1993).  Forth's designer
  and two of its longtime stewards on the language's history and
  the design forces that shaped it.  Worth reading if you've ever
  wondered *why* the language is the way it is.

- **Richard W. M. Jones, "JONESFORTH"** (a commented x86-32
  Forth, 2007).  A public-domain, heavily annotated assembly
  source for a complete Forth.  If this book's seed feels too
  terse, JONESFORTH is the longer commented version of the same
  ideas on i386.

- **Bill Muench and C. H. Ting, "eForth"** (~1990).  The
  historical reference design for "minimal portable Forth" —
  about thirty primitives, easy to port to a new CPU in a
  weekend.  The cultural reason a number near 32 is the
  conventional choice for a primitive set; this book's seed sits
  in that tradition.

- **Cesar Blum, "sectorforth"** (2020).  A 16-bit x86 Forth that
  fits in a 512-byte boot sector with eight primitives (plus a
  handful of state variables and two I/O words).  The "minimum
  viable Forth" demonstration; useful as a sanity check on how
  much language you can get from how little code.  An order of
  magnitude smaller than this book's seed, at the cost of living
  inside 16-bit BIOS boot constraints.

- **Koichi Nakamura, "planckforth"** (2020).  Bootstraps a Forth
  from a hand-written 1 KB i386 ELF binary (stored as xxd hex)
  plus a `bootstrap.fs` library that builds the higher-level
  language on top.  The closest spiritual cousin in this list,
  with three differences worth knowing: planckforth is
  indirect-threaded i386 where seed-forth is subroutine-threaded
  x86-64; planckforth's primitives are single-character codes
  (`k`, `h`, `t`, `j`, …), so the opening of `bootstrap.fs` is
  dense ASCII like `h@l@h@!h@C+h!k1k0-h@$...` until the library
  has defined `\` for comments and conventional word names — the
  bootstrap earns its own readability inside itself; and the
  terminal artifact is a self-hosted Forth, not a bootstrap-chain-
  compatible C compiler, so there is no analog to seed-forth's
  Stage-A parity claim.

- **gforth** — the GNU Forth, the playground this book uses for
  Part I.  Documentation at gnu.org/software/gforth.

- **ANS Forth (ANSI X3.215-1994)** — the standard.  Most of the
  vocabulary in this book is borrowed from it (`dup`, `drop`,
  `swap`, `: ;`, etc.).  The seed *does not* implement ANS Forth
  — it implements just enough Forth to host its own compiler.

## Compilers and parsers

- **Niklaus Wirth, *Compiler Construction*** (1996).  The
  shortest book that takes you from grammars to a working
  one-pass compiler.  Wirth's PL/0 example mirrors what this
  book's Chs 22–32 do, minus the C-isms.

- **Andrew Appel, *Modern Compiler Implementation in C*** (1998).
  The standard university text.  Read the chapters on parsing
  and codegen if Chs 27–31 leave you wanting depth.

- **Jack Crenshaw, "Let's Build a Compiler"** (Pascal,
  1988–1995).  A series that walks through writing a compiler
  from scratch in one sitting, the same target audience as this
  book.  Available online (search the title).

- **Theodore Norvell, "Parsing Expressions by Recursive
  Descent"** (1999, Memorial University of Newfoundland).  The
  write-up that coined the name "precedence climbing" for the
  algorithm Ch 27 uses.  The original description is in **Keith
  Clarke, "The top-down parsing of expressions"** (1986
  technical note, Queen Mary College).

- **Pratt parsing** is the obvious alternative — Vaughan Pratt,
  "Top down operator precedence" (1973).  Pratt and precedence
  climbing produce the same parse tree; Pratt dispatches on
  *token*, precedence climbing dispatches on *precedence level*.
  Ch 27 picks the latter because it's smaller to write in Forth.

## Bootstrapping and reproducible builds

- **Ken Thompson, "Reflections on Trusting Trust"** (Turing
  Award lecture, 1984).  Three pages.  The reason the bootstrap
  chain exists.

- **bootstrappable.org** — the umbrella project tracking work to
  reduce binary-blob dependence in the Linux software stack.
  Lists the current state of the full-source-bootstrap chain.

- **Jeremiah Orians et al., stage0 / stage0-posix / M2-Planet /
  mescc-tools** (github.com/oriansj).  The links in the chain
  immediately below and above this book's segment.  Ch 32 and
  Appendix C describe how this book's compiler plugs into them.

- **Janneke Nieuwenhuizen, GNU Mes** (gnu.org/software/mes).
  The Scheme/C interpreter that connects M2-Planet's output to
  TinyCC and onward to GCC in the Guix Full Source Bootstrap.

- **Live-bootstrap** (github.com/fosslinux/live-bootstrap).
  Runs the entire chain hex0 → GCC + GNU/Linux as a single
  reproducible script.  The integration testbed for everyone
  upstream of this book.

## x86-64 and ELF

- **Intel® 64 and IA-32 Architectures Software Developer's
  Manual** (Intel SDM).  Volume 2 (instructions) is the authority
  for every encoder in Ch 25.  Free PDF from intel.com.

- **System V Application Binary Interface, AMD64 Architecture
  Processor Supplement** ("psABI").  The calling convention this
  book's compiler outputs to (Ch 25, Ch 26, Ch 31).  Maintained
  at gitlab.com/x86-psABIs/x86-64-ABI.

- **TIS, *Executable and Linkable Format (ELF) Specification***
  (1995, the Tool Interface Standards version).  The 18-page
  document Ch 13 and Ch 25 work from.  Still distributed as
  `gabi.xinuos.com` or in countless mirrors.

- **Linux man-pages, sections 2 (syscalls) and 5 (file formats:
  `elf`, `core`)**.  The current behaviour of every syscall Ch 5
  wraps, and the kernel's view of the ELF loader.

## Closely related literate / from-scratch projects

- **Daniel J. Bernstein, "qhasm"** and **CompCert** show two
  ends of the spectrum: how far a careful assembler/codegen
  language can go (qhasm) and how rigorous a verified C compiler
  can be (CompCert).  Neither is in this book's lineage but both
  inform the surrounding question of "what is a trustworthy
  compiler?"

- **Andrew Tridgell, "How Samba was Written"** (2003) — not
  about compilers, but the same flavour of "the source is the
  spec, read it" pedagogy this book aims for.

---

If you read only three things from this list: Brodie's
*Starting Forth* for the language, Wirth's *Compiler
Construction* for the compiler, and Thompson's "Reflections
on Trusting Trust" for the *why*.  The rest is depth on demand.
