# Chapter 12 — `allot`, `create`, `variable`, `bytes-eq`

```text
Missing capability: the library lacks variable storage, forward references and byte-comparison helpers.
New pattern: create + allot for data areas; defer/is for a word whose meaning comes later; a search loop that returns the moment it knows (exit,).
Artifact after this chapter: allot, create, variable, defer, is, s,, bytes-eq — 010-lib.fth is now complete.
Proof link: macro (Ch 22) and symbol (Ch 24) lookup compare names via bytes-eq; every fixed compiler table is a create/allot buffer; the parsers' mutual recursion (Chs 22, 27, 30) goes through defer.
```

Where does a compiler written in this library keep its line number?
`constant` names a value that never changes, and the data stack
forgets everything the moment a word returns.  The compiler needs
named *storage*: counters, buffers, tables.  And when it meets the
identifier `main`, it needs to ask whether those four bytes match a
name it has seen before, with no string type.

The last 96 lines of `010-lib.fth` (374–469) supply both.  `allot`
bumps HERE by a byte count.  `create` reuses Ch 10's 19-byte runtime
body but makes it push the address of a data area that follows the
body.  `variable` is `create` with one zero cell already in place.
Together they cover every static-memory pattern the C compiler
needs.  `defer` and `is` let a word call another word that is not
written yet, which two parsers that call each other need.  `s,` fills a data area with the bytes of a name, such as
`main`, and `bytes-eq` compares two byte ranges, returning with
Ch 11's `exit,` at the first mismatch.  Its callers are the macro
and symbol lookups of Chs 22 and 24.  The seed's `,` primitive,
which `variable` uses to lay down its zero cell, is Ch 17.

## 1. `allot` in one line

```forth
: allot  here-addr @ + here-addr ! ;
```

`allot ( n -- )` advances HERE by `n` bytes without writing
anything.  The body is the same read-modify-write idiom we met in
`c,` (Ch 2), but parameterised: fetch the HERE cell, add `n`, store
it back.

Trace it:

| token         | stack                       |
|---------------|-----------------------------|
| (in)          | `n`                         |
| `here-addr`   | `n addr-of-HERE`            |
| `@`           | `n current-HERE`            |
| `+`           | `current-HERE+n`            |
| `here-addr`   | `current-HERE+n addr-of-HERE` |
| `!`           | empty (HERE := current+n)   |

`allot` writes nothing, so the new region holds whatever was
already in memory.  After `create FOO`, `[lit] 16 allot` reserves a
16-byte data area you are expected to fill before reading.  In
practice the region is fresh memory the kernel zeroed, so the seed
never needs an explicit clear.

One more HERE move lives next to `allot`.  `skip-vm-pages` jumps
HERE forward past the seed's fixed pages (the data stack, the I/O
scratch byte, the token buffer and the sysvar page), so that the C
compiler's megabyte buffers (Ch 21) cannot overlap them:

```forth
: skip-vm-pages  state [lit] 4096 + here-addr ! ;
```

The sysvar page starts at STATE's cell, `0x413000`, so the page
above it starts 4096 bytes later, at `0x414000`.  Like `here-addr`
(Ch 2), it derives the address from what the seed exports instead
of typing it in.

## 2. `create`'s runtime body

`create` defines a word that, when later invoked, pushes the
address of the bytes immediately following its body.  Mechanically
it builds the same 19-byte template `constant` did (Ch 10), but the
`imm64` is a *computed* address: the address of the data area
itself.

```forth
: create  : here [lit] 19 + push-body, [lit] 0 state ! ;
```

The interesting part is **`here [lit] 19 +`**.  At the moment it
runs, `:` has just built the header, so HERE sits at the first byte
of the body that `push-body,` (Ch 10) is about to write.  That body
is 19 bytes, so the byte just past its `ret`, where the data area
begins, is `HERE + 19`.  `push-body,` takes that future address as
its value and writes it into the imm64 slot.  When the resulting
word runs, it pushes its own data-area address.

After `create FOO`, FOO's dictionary entry looks like:

```
[link][flags=0][name-len][name]
[19-byte runtime body, imm64 = data-area-addr]
[data area: empty, sized by subsequent allot/c,/,/,8 calls]
```

The data area sits in the dictionary, contiguous with the body, so
there is no separate allocator, no fixup, and no pointer
indirection.  You name a thing, then you fill in its bytes.

## 3. `variable` = `create` + a cell

```forth
: variable  create [lit] 0 , ;
```

`variable` runs `create`, whose `:` reads the name that follows
`variable` in the input, then `,` lays down one 8-byte zero cell as
the data area.  After `variable COUNTER`, COUNTER is a word that
pushes the address of a zero-initialised 8-byte cell.  Calling
`create` from inside another defining word works because `create`
takes its name from the input stream, not from the stack: whoever
calls it, the next token becomes the name.

Read side by side, Ch 10's `constant` and this chapter's `create`
and `variable` are variations on one 19-byte template, differing
only in (a) which 64-bit value goes into the `movabs` slot, and (b)
what (if anything) follows the `ret`.

| Word       | imm64                | post-body data         |
|------------|----------------------|------------------------|
| `constant` | the user's value     | nothing                |
| `create`   | the data-area addr   | nothing (user fills via `allot`/`c,`/`,`) |
| `variable` | the data-area addr   | one 8-byte zero cell   |

## 4. `defer` and `is`: a name now, a meaning later

`:` compiles a call to a word it can find, so a word can only call
words defined before it.  That is a problem for words that call each
other.  The C compiler's statement parser calls the `if` parser, and
the `if` parser calls the statement parser for its body; whichever is
written first cannot name the other.

A *deferred* word solves it.  `defer NAME` defines `NAME` now, with a
body that runs whatever execution token (xt) sits in a cell after its
code.  Callers compile ordinary calls to `NAME`.  Later, once the
real word exists, `' REAL is NAME` stores its xt in that cell, and
from then on every call to `NAME` runs `REAL`:

```forth
' @       constant fetch-xt
' execute constant execute-xt
[lit] 29 constant defer-code-size

: defer
  : here defer-code-size + push-imm64,           \ rdi = address of the cell
  fetch-xt call,  execute-xt call,  ret,
  [lit] 0 ,  [lit] 0 state ! ;

: is  ' defer-code-size + ! ;
```

`defer` is `create`'s recipe with two calls added.  `:` builds the
header, and the body starts at HERE with Ch 10's 18-byte
`push-imm64,`, whose value is the address of the cell.  Then come
two 5-byte calls: `@` fetches the xt out of the cell, and the seed's
`execute` runs it.  A `ret` ends the code, and the cell itself
follows, 18 + 5 + 5 + 1 = 29 bytes after the start of the body.

`is` finds that cell again.  `'` reads `NAME` and returns its xt,
which is the first byte of its body, so the cell is at xt + 29.  The
xts of `@` and `execute` are captured with `'` at load time, as
Ch 11 did for `branch` and `0branch`, so nothing depends on where the
seed put them.

A deferred word that is called before any `is` jumps to address 0
and crashes, so every `defer` in the compiler is followed, later in
the same file, by the `is` that fills it.  Chs 22, 27 and 30 use it
wherever a parser needs a word that the file defines further down.

## 5. `s,`: names as data

The C compiler needs a few fixed names as bytes: `main` to find the
entry point, `putchar` for its libc shim.  `s,` lays down the next
token's bytes at HERE:

```forth
create cc-main-name-bytes  s, main
```

It is `token bytes,`.  `bytes, ( a u -- )` is a counted `c,` loop.
`token ( "tok" -- a u )` reads the next token and returns where it
is and how long it is.  The seed's reader leaves each token in the
TIB (Ch 10's `tib`) but keeps its length in a register Forth never
sees, so `token` first fills the TIB with 256 blanks, reads the
token with `' drop` as `char` does, and then counts bytes up to the
first blank.  A token never contains a blank, so the count is its
length.

## 6. `bytes-eq`: stop at the first mismatch

The last word in `010-lib.fth` is a byte-by-byte memory comparator.

```forth
: bytes-eq
  begin,
    dup [lit] 0 >
  while,
    >r                                           ( a1 a2  R: u )
    over c@ over c@ <> if,                       ( a1 a2 )
      r> drop 2drop [lit] 0 exit,                \ mismatch: answer 0
    then,
    1+ swap 1+ swap                              ( a1+1 a2+1 )
    r> 1-                                        ( a1+1 a2+1 u-1 )
  repeat,
  drop 2drop true ;                              \ all u bytes matched
```

`bytes-eq ( a1 a2 u -- f )` returns `-1` if the first `u` bytes at
`a1` equal those at `a2`, else `0`.  Each pass parks the count `u`
on the return stack, compares one byte from each side, advances both
pointers, and takes `u` back decremented:

| token                     | stack          | what happens                                |
|---------------------------|----------------|---------------------------------------------|
| `>r`                      | `a1 a2`        | park `u` on the return stack                |
| `over c@`                 | `a1 a2 *a1`    | fetch byte at `a1`                          |
| `over c@`                 | `a1 a2 *a1 *a2` | fetch byte at `a2`                         |
| `<> if,`                  | `a1 a2`        | bytes differ?  then return 0 at once        |
| `1+ swap 1+ swap`         | `a1+1 a2+1`    | advance both pointers                       |
| `r>`                      | `a1+1 a2+1 u`  | recover `u` from the return stack           |
| `1-`                      | `a1+1 a2+1 u-1` | decrement                                  |

If the loop runs out (`u` reaches zero), every byte matched: `drop
2drop` clears the residue and `true` (Ch 7) is the answer.

The mismatch branch is where Ch 11's rule about `exit,` bites.  At
that point `u` is parked on the return stack, and `exit,`'s `ret`
would pop it as the return address and jump into nowhere.  So the
branch first runs `r> drop` to take `u` back off, then clears `a1
a2` from the data stack, pushes `0`, and returns.  The C compiler
calls `bytes-eq` thousands of times while it builds itself, mostly
on two names that differ, and none of those calls reads past the
first differing byte.

## Canonical source

```forth file=010-lib.fth
\ ===== Defining-words: allot / create / variable =====
\ These let Forth code build variables and arbitrary data structures
\ without escaping back into 000-seed.hex0.  Like constant, create calls
\ the seed's `:` primitive to tokenize the next input word and build a
\ dictionary header (link, flags=0, name-len, name bytes), lays down the
\ 19-byte push body, and resets STATE=0 (since `:` left it at 1).

\ allot ( n -- )  Bump HERE by n bytes (no initialization).
\ Used after `create` to grow an array, or stand-alone for scratch buffers.
: allot  here-addr @ + here-addr ! ;

\ skip-vm-pages ( -- )  Jump HERE to the first page above the seed's fixed VM
\ pages: data stack (below 0x411000), I/O scratch byte (0x412000), token
\ buffer (0x412800) and the sysvar page, which starts at STATE's cell.  So
\ HERE becomes STATE + 4096 = 0x414000.  030-cc-io.fth and 130-asm.fth call
\ it before creating their megabyte buffers, which then cannot overlap VM
\ state.  HERE must still be below the data stack (0x410000) when it runs.
: skip-vm-pages  state [lit] 4096 + here-addr ! ;

\ create ( "name" -- )  Define name as a word that pushes the address of
\ the data area immediately following its body.  Caller fills the data
\ area via `,` / `c,` / `allot`.  HERE is at the start of the body when
\ push-body, runs, and the body is 19 bytes, so the data area starts at
\ HERE + 19.
: create  : here [lit] 19 + push-body, [lit] 0 state ! ;

\ variable ( "name" -- )  Define name as a word that pushes the address of
\ an 8-byte cell, initialized to 0: a create whose data area is one cell.
: variable  create [lit] 0 , ;

\ ===== Deferred words: defer / is =====
\ A word can only call words that already exist, but two words that call
\ each other (a statement parser and the if-statement parser inside it)
\ cannot both come first.  defer names a word now and says what it does
\ later: its body calls whatever xt sits in a cell after its code, and is
\ fills that cell once the real word exists.
\
\ A deferred word's body is 29 bytes of code, then the cell:
\   <18 bytes>   push-imm64, of the cell's address   ; rdi = &cell
\   E8 <rel32>   call @                              ; rdi = the xt
\   E8 <rel32>   call execute                        ; run it
\   C3           ret
\   <8 bytes>    the cell (0 until is fills it)
' @       constant fetch-xt
' execute constant execute-xt
[lit] 29 constant defer-code-size

\ defer ( "name" -- )  Define name as a word that runs the xt in its cell.
: defer
  : here defer-code-size + push-imm64,           \ rdi = address of the cell
  fetch-xt call,  execute-xt call,  ret,
  [lit] 0 ,  [lit] 0 state ! ;

\ is ( xt "name" -- )  Make the deferred word name run xt from now on.
\ ' finds name's code; its cell sits defer-code-size bytes further on.
: is  ' defer-code-size + ! ;

\ token ( "tok" -- a u )  read the next token; leave its address in the TIB
\ and its length.  The seed keeps the length in a register Forth cannot
\ see, so we blank the TIB's 256 bytes first and then count the token's
\ bytes up to the first blank (a token is at most 255 bytes).
: token
  tib [lit] 256 + tib                            ( end p )
  begin, 2dup > while, bl over c! 1+ repeat,     \ fill the TIB with blanks
  2drop  ' drop                                  \ read the token into it
  tib [lit] 0                                    ( a 0 )
  begin, 2dup + c@ bl <> while, 1+ repeat, ;     ( a u )

\ bytes, ( a u -- )  copy u bytes from a to HERE, advancing HERE.
: bytes,
  begin, dup while,
    over c@ c,  1- swap 1+ swap
  repeat,
  2drop ;

\ s, ( "tok" -- )  copy the next token's bytes to HERE: `create name s, text`
\ lays down the string "text" without a terminator or a length.
: s,  token bytes, ;

\ ===== bytes-eq =====
\ bytes-eq ( a1 a2 u -- f )  -1 if first u bytes at a1 match those at a2; 0 else.
\ Used by symbol-table name comparison and keyword recognition in the C
\ compiler.  Stops at the first mismatch: exit, returns 0 from inside the
\ loop, after r> drop has taken the parked count off the return stack.
: bytes-eq
  begin,
    dup [lit] 0 >
  while,
    >r                                           ( a1 a2  R: u )
    over c@ over c@ <> if,                       ( a1 a2 )
      r> drop 2drop [lit] 0 exit,                \ mismatch: answer 0
    then,
    1+ swap 1+ swap                              ( a1+1 a2+1 )
    r> 1-                                        ( a1+1 a2+1 u-1 )
  repeat,
  drop 2drop true ;                              \ all u bytes matched
```

## Try it

### `create`/`allot`: gforth works

`create` and `allot` are standard.  In gforth:

```forth
create buf  16 allot
65 buf c!   66 buf 1 + c!   67 buf 2 + c!
buf 3 type     \ prints "ABC"
```

`type ( c-addr u -- )` is gforth's built-in "print `u` bytes from
`c-addr`."  The seed has no `type`; it has `emit` for one byte at a
time.  See the seed test below for the equivalent.

### `create`/`allot` and `bytes-eq` in the seed

```sh
./build.sh
{ cat 010-lib.fth
  echo 'create buf  [lit] 65 c, [lit] 66 c, [lit] 67 c,'
  echo 'buf c@ emit  buf [lit] 1 + c@ emit  buf [lit] 2 + c@ emit'
} | ./seed-forth
```

Expected: `ABC`.  `create buf` defines a word; the three `c,` calls
write `A`, `B`, `C` into its data area.  Then we read each byte
back and emit.

For `bytes-eq`:

```sh
{ cat 010-lib.fth
  echo 'create a  [lit] 72 c, [lit] 73 c, [lit] 0 c,'
  echo 'create b  [lit] 72 c, [lit] 73 c, [lit] 0 c,'
  echo 'create c  [lit] 72 c, [lit] 88 c, [lit] 0 c,'
  echo 'a b [lit] 3 bytes-eq  0= [lit] 49 + emit'    # a vs b: equal  -> "1"
  echo 'a c [lit] 3 bytes-eq  0= [lit] 49 + emit'    # a vs c: differ -> "0"
} | ./seed-forth
```

Expected output: `10`.  `a` and `b` are identical 3-byte buffers
(`HI\0`); `a` and `c` differ at byte 2 (`HI\0` vs `HX\0`).

### `defer` and `is` in the seed

```sh
{ cat 010-lib.fth
  echo 'defer greet'
  echo ': twice  greet greet ;'
  echo ": say-a  [lit] 65 emit ;  ' say-a is greet  twice"
  echo ": say-b  [lit] 66 emit ;  ' say-b is greet  twice"
} | ./seed-forth
```

Expected: `AABB`.  `twice` is compiled while `greet` still has no
meaning.  Each `is` changes what `greet` does, and `twice` follows
without being recompiled.

### The finale: every Part I word at once

One last run, using nothing but words Part I built.  `src` holds the
nine bytes of the C fragment `int x=42;`.  `kind` classifies one byte
with nested `if,`s over Ch 6's predicates, and `scan` walks the
buffer with a `begin,` loop:

```sh
{ cat 010-lib.fth
  echo 'create src  [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit] 32 c, [lit] 120 c,'
  echo '            [lit] 61 c, [lit] 52 c, [lit] 50 c, [lit] 59 c,'
  echo ': kind  dup alpha? if, drop [lit] 97 else,'
  echo '        dup digit? if, drop [lit] 100 else,'
  echo '        dup space? if, drop [lit] 95 then, then, then, emit ;'
  echo ': scan  begin, dup [lit] 0 > while,'
  echo '        over c@ kind  [lit] 1 - swap [lit] 1 + swap  repeat, 2drop ;'
  echo 'src [lit] 9 scan'
} | ./seed-forth
```

Expected output: `aaa_a=dd;`.  Letters became `a`, digits `d`, the
space `_`, and punctuation passed through.  That is the first step
of a C lexer, and most of its words (`create`, `if,`, `else,`,
`begin,`, `>`, `-`, `alpha?`, `2drop`) get a `?` from the bare
seed.

## Exercises

1. **★★ Trace.** Delete `r> drop` from `bytes-eq`'s mismatch branch.  Trace
   `a c [lit] 3 bytes-eq` from the Try-it: where does `exit,`'s `ret`
   jump, and why does the word still work when the mismatch never
   happens?

2. **★★ Extend.** Define `2variable ( -- )` that defines a word pushing the address
   of a *two*-cell store.  Compare its emitted bytes to `variable`.

3. **★★ Extend.** Define `counted, ( "tok" -- )` that lays down a
   length byte followed by the next token's bytes (a *counted
   string*), using `token` and `bytes,`.  Then write `ctype ( a -- )`
   that emits a counted string.

4. **★★★ Trace.** A `bytes-eq` without `exit,` has to keep going after a
   mismatch, AND-ing each byte's result into a running flag.  How
   much work does the early exit save the C compiler?  (Hint: count
   `bytes-eq` calls per build and how many stop at byte 0; the
   symbol table compares lengths before it calls `bytes-eq`.)

## Takeaways

- `create`, `variable`, and `constant` share one 19-byte runtime
  body and differ only in the `imm64` value and what follows the
  `ret`.
- `allot` bumps HERE by `n` bytes, and with `create` it reserves a
  named data area of any size.
- `defer` defines a word whose body runs the xt in a cell, and `is`
  fills the cell, so a word can call one that is written later.
- `bytes-eq` returns at the first mismatch with `exit,`, after
  `r> drop` restores the return stack it borrowed; `s,` supplies the
  fixed names it is compared against.

**Part I tally, complete.**  Byte emission, Boolean logic,
subtraction, file I/O, character tests, comparisons, shuffles,
multi-byte writes, `constant`, branches and loops, **variables,
buffers, forward references, and strings**.  `010-lib.fth` is complete.

## Bridge to Part II: what Part I bought us

In Ch 1 the bare seed answered `?` to `over - and < if, variable`.
You have now built all six, and every other line of `010-lib.fth`,
and run a byte classifier built from them.  Everything in Part I
was ordinary Forth.

And every line of it stands on 32 primitives you have taken on
faith.  `nand`, which gave you all of Boolean logic, is 12 bytes of
machine code at offset `0x1CE`.  `dup` is 9.  `/`, which gave you
`<` and every byte split, is 18.  What are those bytes?  How does 1,772 bytes of hex persuade a Linux kernel to run
a REPL at all?  Those bytes are the one layer of the chain a skeptic
cannot read as Forth, and Part I has not shown you one of them.

Part II opens that box.  Eight chapters read `000-seed.hex0` and
show the exact bytes behind every primitive you have called.
Ch 13 starts where the kernel does, at byte 0: the ELF header and
the entry point.  Chs 14–16 read the stack, arithmetic and I/O
primitives (`dup`, `nand`, `emit`, `syscall6`).  Chs 17–20 read the
machinery that runs everything else: the dictionary and `find`, the
colon compiler (`:`, `;`), `branch` and `0branch`, and the REPL.

Next: Chapter 13 — The ELF and the Entry Point, where the first 120
bytes of the file have one job: persuading the kernel to run the
rest.
