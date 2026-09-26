# Appendix D — Three worked exercises, one per Part

The 32 main chapters end with 3–5 exercises each, roughly a
hundred in total, with no solutions printed inline (the point of
an exercise is the time you spend stuck).  This appendix is a
*sampler*: one exercise from each Part, walked end to end.  The
picks are one Extend and two Traces, chosen to show three
distinct working modes fully: a hands-on derivation, an
analytical "why is this enough?", and a step-by-step trace.

| From | Tag | Exercise |
|------|-----|---|
| Ch 11 (Part I)   | ★★ Extend | "Add the `?exit,` combinator" |
| Ch 18 (Part II)  | ★ Trace   | "Why is `ret` enough to end a colon definition?" |
| Ch 27 (Part III) | ★★ Trace  | "Trace `cc-parse-add` parsing `a - b - c`" |

---

## D.1.  Ch 11 — Add the `?exit,` combinator

> **Exercise (Ch 11 #3, ★★ Extend).**  Write `?exit, ( flag -- )`, an
> immediate word that compiles "return now if the flag is non-zero".
> Build it from the emitters `if,`, `exit,` and `then,` are made of,
> not from those words themselves: three lines.

### What's being asked

Inside a definition, `if, exit, then,` already means "return if the
flag is non-zero".  `?exit,` should compile exactly that in one
word.  The catch is in the last sentence of the exercise: `if,`,
`exit,` and `then,` are immediate, so writing them inside `?exit,`'s
own body would run them while `?exit,` is being compiled, not when
`?exit,` later runs inside some other definition.  `?exit,` has to
emit their bytes itself.

### The shape of the answer

Read the three words it replaces (Ch 11, Ch 10):

```forth
: if,    0branch-xt call,  here  [lit] 0 , ;   immediate
: exit,  ret, ;                                immediate
: then,  here swap ! ;                         immediate
```

`if,` emits `CALL 0branch` and an 8-byte slot and leaves the slot's
address; `exit,` emits `C3`; `then,` stores HERE into the slot.
Run the three bodies back to back and the fixup never needs to leave
the data stack of `?exit,` itself.

### The solution

```forth
\ ?exit, ( flag -- )  compile: return now if flag is non-zero.
: ?exit,
  0branch-xt call,  here [lit] 0 ,     \ CALL 0branch + slot (fixup)
  ret,  here swap ! ;                  \ C3, then patch slot to just past it
immediate
```

Three lines, as promised, plus the `immediate` every combinator
needs.  Leave it off and `?exit,` runs when its caller *runs*
instead of when it compiles: the caller's body gets a `CALL ?exit,`,
and each call appends 14 stray bytes at whatever HERE is at run
time.

Walk the bytes `?exit,` lays down at offset 0 of some body:

| HERE offset | Byte(s) | Source |
|---|---|---|
| 0  | `E8 ?? ?? ?? ??` | `0branch-xt call,` → `CALL 0branch_code` |
| 5  | 8-byte slot = address of offset 14 | `here [lit] 0 ,`, patched by `here swap !` |
| 13 | `C3` | `ret,` |
| 14 | (the caller's next instruction) | |

At run time `0branch_code` pops the flag.  If it is zero, it reads
the slot and continues at offset 14, past the `ret`.  If it is
non-zero, it skips the slot and falls into the `C3`, which returns
from the word.

### Try it

```sh
./build.sh
{ cat 010-lib.fth
  echo ": ?exit,  0branch-xt call, here [lit] 0 , ret, here swap ! ; immediate"
  echo ": dot-unless  ?exit, [lit] 46 emit ;"
  echo "[lit] 0 dot-unless  [lit] 1 dot-unless  [lit] 0 dot-unless"
} | ./seed-forth
```

Expected output: `..`.  The two zero flags fall through to `emit`;
the `1` returns before it.

### Why three lines

`?exit,` is `if,`, `exit,` and `then,` with the fixup kept private:
14 bytes, one forward branch over one `ret`.  It is also Ch 11's
rule about `exit,` in its smallest form: the `C3` it compiles pops
the caller's return address, so it is only safe where nothing else
has been pushed on the return stack.

---

## D.2.  Ch 18 — Why is `ret` enough to end a colon definition?

> **Exercise (Ch 18 #2, ★ Trace).**  `;`'s appended `ret` (`C3`) is the only
> thing that ends a colon definition.  Why is `ret` enough?  (Hint:
> how was the colon definition *entered* — via `CALL` or via
> `JMP`?)

### What's being asked

A colon definition's body is just a sequence of `CALL xt`
instructions, terminated by a single `C3` byte (`ret`).  Why
doesn't the body need a frame setup, a save/restore, an unwind?

### The trace

When the REPL (or another colon definition) invokes our word
`foo`, the dispatch is `CALL foo_body`.  That single x86
instruction does two things:

1. pushes `rip` (the address of the instruction after the
   `CALL`) onto the x86 *call stack* (which is `rsp`-based);
2. sets `rip` to `foo_body`'s first byte.

Now we're executing inside `foo`.  Each line of the body is a
further `CALL`: to `dup`, or `+`, or `emit`, or another colon
word.  Each of those `CALL`s pushes another return address onto
`rsp` and then `ret`s back, leaving `rsp` exactly where it was
before the call.

When the REPL's compile-mode handler (`;`) appended `C3` at the
*end* of the body, it appended a single instruction that *pops
the top of `rsp` and jumps there*.  At the moment `ret` executes
inside `foo`, the top of `rsp` is the return address that the
*original* `CALL foo_body` pushed.

So `ret` returns control to *whoever called `foo`*: the REPL,
or another colon body that contained `CALL foo`.

### Why this works (the deeper answer)

The seed never builds a separate call frame.  Its data stack
lives in `rbp` (not `rsp`); its return stack lives in `rsp` (the
hardware one).  Every colon definition's "frame" is just the one
return address on `rsp` that the entry `CALL` pushed.  No locals,
no saved registers, no prologue, no epilogue.

The cost is that Forth-level words can't have local variables in
the C sense — they share the data stack and the return stack
with their callers.  The benefit is that a 1-byte `ret` is the
entire teardown.

Two consequences fall out:

1. `>r` and `r>` (Ch 4) work by stashing values onto the *same*
   `rsp` that the caller is using as its return stack.  This is
   why they always come in matched pairs.  Leave them
   unbalanced, and `ret` jumps to your stashed integer.
2. The seed's `execute` (Ch 17) is literally `pop xt ; jmp xt`.
   It doesn't `call` because then the *xt-as-function* would
   `ret` to *execute itself*, which it doesn't want.  Tail-call
   semantics are the default in this Forth, free.

### What you would change to break this

If you replaced the `:` entry-point dispatch with `JMP foo_body`
(instead of `CALL foo_body`), nothing would push a return address
when `foo` started.  When `foo`'s terminating `ret` ran, it would
pop whatever happened to be on `rsp` (the previous, *unrelated*
return address) and crash.

The book's `colon_code` is 82 bytes (Ch 18) but only ~12 of
those build the *callable* part of the new word.  The one-byte
`ret` appended by `;` is all it takes to end one.

---

## D.3.  Ch 27 — Trace `cc-parse-add` parsing `a - b - c`

> **Exercise (Ch 27 #1, ★★ Trace).**  Trace `cc-parse-add` parsing `a - b - c`.
> Where does left-associativity come from?

### What's being asked

`a - b - c` in C is `(a - b) - c`, not `a - (b - c)`.  The
expression parser is a precedence cascade: recursive descent
with one function per precedence level (Ch 27).
Where in the recursion does left-associativity fall out?

### The structure of `cc-parse-add`

From `100-cc-expr.fth` (Chs 27 §6–7 walk this in detail):

```forth
: cc-parse-add
  cc-parse-mul
  begin,
    level-add cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-emit-push-rdi                              \ save left
    cc-parse-mul                                  \ rdi = right
    r> cc-binop-apply                             \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many
```

The accumulator is `rdi`, the seed VM's TOS register cache (Ch
13 §4), which the compiler reuses as the expression-evaluation
register.  The loop body is a `begin, … while, … repeat,`:
pure iteration, not recursion-on-tail.  Each pass of the loop:

1. reads the next token and asks the operator table "is it an
   add-level operator (`+` or `-`)?" (`level-add cc-binop?`);
2. if yes, stashes the operator's table row on R, materializes the
   left so it's a value (not an lvalue), and pushes the running
   left;
3. parses *one* mul-expression as the next right (which lands in
   `rdi`); `cc-binop-apply` materializes it, moves it to `rcx`,
   pops the saved left back into `rdi`,
4. and runs the row's emitter: `add rdi, rcx` or `sub rdi, rcx`;
5. loops.

### The trace for `a - b - c`

Start: `rdi` is the eval register; the input is `a - b - c`.

**Pass 0** (the call into `cc-parse-add` itself):
1. `cc-parse-mul` consumes `a` and emits a load.  rdi = `a`.

**Loop iteration 1**: the next token is `-` (token byte 45).
1. Push `-`'s row onto R.  Materialize left.
2. Emit `push rdi` (save `a`).
3. `cc-parse-mul` consumes `b`.  rdi = `b`.  Materialize.
4. Emit `mov rcx, rdi`.  rcx = `b`.
5. Emit `pop rdi`.  rdi = `a`, rcx = `b`.
6. Pop the row from R; its emitter emits `sub rdi, rcx`.
   rdi = `a - b`.

**Loop iteration 2**: the next token is `-` again.
1. Push its row.  Materialize left.
2. Emit `push rdi` (save `(a - b)`).
3. `cc-parse-mul` consumes `c`.  rdi = `c`.  Materialize.
4. Emit `mov rcx, rdi`.  rcx = `c`.
5. Emit `pop rdi`.  rdi = `a - b`, rcx = `c`.
6. Pop the row; emit `sub rdi, rcx`.  rdi = `(a - b) - c`.

**Loop iteration 3**: the next token isn't `+` or `-`, so
`cc-binop?` answers 0 and the loop exits.  `cc-putback-token` returns the peeked token.
Final rdi = `(a - b) - c`.

### Where left-associativity comes from

Two design choices, both in the loop body:

1. **The current left value is `push`ed before the next right is
   parsed.**  That means the next mul-expression sees a free
   `rdi` to write into, and the running left result is preserved
   in stack order.

2. **The op is applied with `rdi` as the destination** (left
   operand) and `rcx` as the source (right operand): `sub rdi,
   rcx` computes `left - right` and puts it in `rdi`, ready for
   the next iteration.  This means *each iteration sees the
   cumulative left-so-far as its left operand*.

If you wanted right-associativity instead, you'd recurse: instead
of looping, you'd call `cc-parse-add` on the right operand,
producing `a - (b - c)`.  The cascade makes the choice
*per-level* by selecting iteration vs recursion at this exact
point.  Compare `cc-parse-assign` (Ch 28), which *is* right-
associative and *does* recurse.

### Sanity check

Compile and run:

```c
int main(void) { return 10 - 3 - 2; }
```

`(10 - 3) - 2 = 5`.  Right-associative would be `10 - (3 - 2) =
9`.

```sh
./build.sh
./tests/cc/build-m2planet-monolith.sh   # has the C compiler
echo 'int main(void) { return 10 - 3 - 2; }' > /tmp/t.c
# Run /tmp/cc-out on /tmp/t.c by your usual mechanism (the
# monolith pipeline pipes stdin to seed-forth; substitute your
# own input scheme).  Run the result; exit code should be 5.
```

If you see 5, left-associative.  If you see 9, you have a bug.
