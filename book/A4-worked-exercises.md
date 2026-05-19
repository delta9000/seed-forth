# Appendix D — Worked exercises

Each main chapter ends with 3–5 exercises.  This appendix walks
three of them — one per Part — end to end.  The picks are
deliberately a mix of hands-on, analytical, and tracing.

| From | Exercise |
|------|---|
| Ch 11 (Part I)   | "Add the `again,` combinator" |
| Ch 18 (Part II)  | "Why is `ret` enough to end a colon definition?" |
| Ch 27 (Part III) | "Trace `cc-parse-add` parsing `a - b - c`" |

---

## D.1.  Ch 11 — Add the `again,` combinator

> **Exercise (Ch 11 #3).**  Write `again, ( back-target -- )` which
> emits an unconditional backward jump.  It is the simplest member
> of this family — three lines.

### What's being asked

`begin,` already exists in `010-lib.fth` and leaves the
*current* HERE on the stack — the address loops will eventually
branch back *to*.  `while,` and `repeat,` close a counted loop;
they pop `begin,`'s address and emit a `0branch` back to it.

`again,` is the *unconditional* counterpart: pop a back-target and
emit a `branch` (not `0branch`) to it.  Useful for infinite loops
(`begin, ... again,`), or for tail calls written manually.

### The shape of the answer

The existing `repeat,` (in `010-lib.fth`) does exactly this for
the conditional case.  Read it for the template:

```forth
: repeat,                  ( back-target while-fixup -- )
  swap                     ( while-fixup back-target )
  branch-xt comma-call     ( while-fixup )      \ emit JMP back-target
  here ,8                  ( )                  \ but wait — we need a slot
  …
```

Actually the simpler model is `begin, ... 0branch ... ;` — read
`while,` directly: it compiles a 0branch and leaves a *forward*
fixup on the stack.  For `again,` we don't need a fixup; we have
the back-target right there.

### The solution

```forth
\ again, ( back-target -- ) emit an unconditional backward branch.
: again,
  branch-xt comma-call   \ CALL branch_code  (5 bytes)
  ,8 ;                   \ inline 8-byte target = back-target
```

Three lines, as promised.  Walk the bytes for `: forever begin,
again, ;`:

| HERE offset | Byte(s) | Source |
|---|---|---|
| 0 | `E8 ?? ?? ?? ??` | `comma-call branch_code` → `CALL branch_code` |
| 5 | `00 00 00 00 00 00 00 00` | `,8` of the back-target (= HERE at `begin,` time, which was 0 in this body) |

When `branch_code` runs, it reads the inline cell as its new
return address.  Reading 0 here means jumping back to the first
byte of the body — exactly the infinite loop you'd expect.

### Try it

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo ": again,  branch-xt comma-call ,8 ;"
  echo ": tick  begin, [lit] 46 emit again, ;"
  # Hit Ctrl-C after a few dots — there's no way out of this loop.
  echo "tick"
} | grep -v '^[[:space:]]*$' | timeout 1 ./seed-forth || true
```

Expected: stdout fills with `.` until the `timeout 1` kills it.

### Why three lines

The seed pays for `again,` exactly twice: once for the 5-byte
`CALL branch_code`, once for the 8-byte inline target.  No
runtime decision, no fixup stack, no condition.  This is the
floor of the combinator family — everything else in Ch 11 is more
machinery on top of these two emits.

---

## D.2.  Ch 18 — Why is `ret` enough to end a colon definition?

> **Exercise (Ch 18 #2).**  `;`'s appended `ret` (`C3`) is the only
> thing that ends a colon definition.  Why is `ret` enough?  (Hint:
> how was the colon definition *entered* — via `CALL` or via
> `JMP`?)

### What's being asked

A colon definition's body is just a sequence of `CALL xt`
instructions, terminated by a single `C3` byte (`ret`).  Why
doesn't the body need a frame setup, a save/restore, an unwind?

### The trace

When the REPL — or another colon definition — invokes our word
`foo`, the dispatch is `CALL foo_body`.  That single x86
instruction does two things:

1. pushes `rip` (the address of the instruction after the
   `CALL`) onto the x86 *call stack* (which is `rsp`-based);
2. sets `rip` to `foo_body`'s first byte.

Now we're executing inside `foo`.  Each line of the body is a
further `CALL` — to `dup`, or `+`, or `emit`, or another colon
word.  Each of those `CALL`s pushes another return address onto
`rsp` and then `ret`s back — leaving `rsp` exactly where it was
before each call.

When the REPL's compile-mode handler (`;`) appended `C3` at the
*end* of the body, it appended a single instruction that *pops
the top of `rsp` and jumps there*.  At the moment `ret` executes
inside `foo`, the top of `rsp` is the return address that the
*original* `CALL foo_body` pushed.

So `ret` returns control to *whoever called `foo`* — the REPL,
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
   why they always come in matched pairs — leave them
   unbalanced, and `ret` jumps to your stashed integer.
2. The seed's `execute` (Ch 17) is literally `pop xt ; jmp xt`.
   It doesn't `call` because then the *xt-as-function* would
   `ret` to *execute itself*, which it doesn't want.  Tail-call
   semantics are the default in this Forth, free.

### What you would change to break this

If you replaced the `:` entry-point dispatch with `JMP foo_body`
(instead of `CALL foo_body`), nothing would push a return address
when `foo` started.  When `foo`'s terminating `ret` ran, it would
pop whatever happened to be on `rsp` — the previous *unrelated*
return address — and crash.

The book's `colon_code` is 130 bytes (Ch 18) but only ~12 of
those build the *callable* part of the new word.  The `ret`
appended by `;` is the punch line that the entire system is built
to honour.

---

## D.3.  Ch 27 — Trace `cc-parse-add` parsing `a - b - c`

> **Exercise (Ch 27 #1).**  Trace `cc-parse-add` parsing `a - b - c`.
> Where does left-associativity come from?

### What's being asked

`a - b - c` in C is `(a - b) - c`, not `a - (b - c)`.  The
expression parser is precedence-climbing recursion (Ch 27).
Where in the recursion does left-associativity fall out?

### The structure of `cc-parse-add`

From `100-cc-expr.fth` (read it in Ch 27 §3):

```forth
: cc-parse-add                            ( -- )
  cc-parse-mul                            \ parse leftmost mul-expression
  begin,
    cc-peek-add-or-sub                    \ is the next token + or - ?
  while,
    cc-consume-token                      \ eat it
    >r                                    \ stash the op byte on R
    cc-emit-push-rax                      \ save left result
    cc-parse-mul                          \ parse the right operand
    cc-emit-pop-rcx                       \ left was on stack; pop into rcx
    r>                                    \ retrieve op
    cc-emit-arith-op                      \ emit "sub rcx, rax" or "add rcx, rax"
    cc-emit-mov-rax-rcx                   \ result back to rax for the next round
  repeat, ;
```

The loop body is a `begin, … while, … repeat,` — pure iteration,
not recursion-on-tail.  Each pass of the loop:

1. asks "is there another `+` or `-`?";
2. if yes, eats it, pushes the current left, parses *one*
   mul-expression as the next right;
3. emits the op on `(left, right)`, leaving the result in `rax`;
4. loops.

### The trace for `a - b - c`

Start: `rax` is empty; the input is `a - b - c`.

**Pass 0** (the call into `cc-parse-add` itself):
1. `cc-parse-mul` consumes `a` and emits "load a into rax".  rax = `a`.

**Loop iteration 1**: next token is `-`.
1. Consume `-`.  Push op byte onto R.
2. Emit `push rax` (save `a` on the eval stack).
3. `cc-parse-mul` consumes `b`.  rax = `b`.
4. Emit `pop rcx`.  rcx = `a`, rax = `b`.
5. Pop op from R; emit `sub rcx, rax`.  rcx = `a - b`.
6. Emit `mov rax, rcx`.  rax = `a - b`.

**Loop iteration 2**: next token is `-`.
1. Consume `-`.  Push op byte.
2. Emit `push rax` (save `(a - b)`).
3. `cc-parse-mul` consumes `c`.  rax = `c`.
4. Emit `pop rcx`.  rcx = `a - b`, rax = `c`.
5. Pop op; emit `sub rcx, rax`.  rcx = `(a - b) - c`.
6. Emit `mov rax, rcx`.  rax = `(a - b) - c`.

**Loop iteration 3**: next token is not `+` or `-` — exit the
loop.  Final rax = `(a - b) - c`.

### Where left-associativity comes from

Two design choices, both in the loop body:

1. **The current left value is `push`ed before the next right is
   parsed.**  That means the next mul-expression sees a clean
   `rax` to write into, and the running left result is preserved
   in stack order.

2. **The op is applied with `rcx` as the destination** (left
   operand) and `rax` as the source (right operand): `sub rcx,
   rax` computes `left - right` and puts it in `rcx`, which is
   then `mov`'d back to `rax`.  This means *each iteration sees
   the cumulative left-so-far as its left operand*.

If you wanted right-associativity instead, you'd recurse: instead
of looping, you'd call `cc-parse-add` on the right operand,
producing `a - (b - c)`.  Precedence climbing makes the choice
*per-operator* by selecting iteration vs recursion at this exact
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
