# Two small results

A program can calculate a number without showing it. It can show a character
without leaving that character on its stack. And it can finish by handing a
number to the program that started it.

Those are three different destinations for a result. Let's follow two small
programs until the difference is clear. No installation is needed:
these are paper traces of the [pinned implementation](EDITION.md), not newly
observed runs. If you already distinguish a stack value, an output byte and a
process exit status, try [the practice](#try-a-change) first.

## A number becomes a character

A **stack** is a sequence of values with one end used for the next operation.
We draw that end on the right. In `[99, 32]`, the next value available is 32;
99 is below it. A Forth **word** is a named operation on that state.

Here are the three operations we need:

| Word | What it does | Example |
|---|---|---|
| `dup` | Copies the top value | `[99, 32]` becomes `[99, 32, 32]` |
| `+` | Consumes the top two values and puts back their sum | `[99, 32, 32]` becomes `[99, 64]` |
| `[lit] 1` | Puts the literal value one on the stack | `[99, 64]` becomes `[99, 64, 1]` |

A **literal** is a value written directly in the source. This small Forth
requires the explicit `[lit]` word: do not import another Forth's habit of
writing a bare number. The small values here fit comfortably in its cells,
the fixed-size storage units used for stack values.

Predict the state after the final `+`:

```text
start             [99, 32]
after dup         [99, 32, 32]
after +           [99, 64]
after [lit] 1     [99, 64, 1]
after +           ?
```

It is `[99, 65]`. The additions used only the values above 99. Nothing needed
to save 99 elsewhere: it stayed below the part of the stack being changed.

Now name the calculation:

```forth
: twice-plus-one dup + [lit] 1 + ;
```

The colon begins a definition, the next token names it, and the semicolon
ends it. A token is a piece of text separated by whitespace, such as spaces
or line breaks. Keep `:` and `;` separated as shown. Reading this definition
prepares a new word. It does not yet double
a stack value. Later, running `twice-plus-one` performs those four operations.

One more word gives the number a new destination. **`emit` consumes the top
value and requests that its low byte be written to standard output**, the
program's usual output stream. A byte can hold a value from 0 through 255;
all of 65 fits. For a nonnegative value, its low byte is what remains after
removing complete groups of 256. Under ASCII, byte 65 represents `A`. That character code is a
given here, not a fact you need to memorize.

Starting with `[99, 32]`, the sequence `twice-plus-one emit` therefore requests
one `A` byte and, if control returns, leaves `[99]`. It does not leave 65 on the stack, print the
two digits `6` and `5`, or print 99.

We assumed the output destination accepts the request when predicting a
delivered `A` byte. The seed's `emit` does not report a failed write to the Forth
caller. Its stack cleanup therefore cannot tell us whether the byte arrived.
[S7](seed-forth/chapters/07-linux-io-contracts.md) opens that result-handling
problem; [S14](seed-forth/chapters/14-physical-io-and-exit.md#emit-save-one-byte-then-recover-the-older-top)
opens the actual instructions.

The whole small source, starting with an empty logical data stack, is:

```forth
: twice-plus-one dup + [lit] 1 + ;
[lit] 99 [lit] 32 twice-plus-one emit
bye
```

`bye` asks Linux to end the process with status zero. It does not print or
return the remaining 99. The predicted output is one `A` byte, with no
newline requested; the termination status is zero. These are separate
observations a later run would need to retain. For now, you can account for
every value without running anything.

## Seven goes somewhere else

Here is a whole C source program:

```c
int main(void) { return 7; }
```

It looks different from the Forth sequence because C puts a function's name,
inputs and body together:

- A **function** is a named piece of work that can be called and can return a
  result. Here its name is `main`
- `int` says the result has C's integer type. Seven is within its range in
  this edition; we do not need the full type system yet
- `(void)` says this definition has no parameters, the named inputs a
  function can receive
- The braces contain the body. `return 7;` supplies seven as the function's
  result and ends this call. The semicolon terminates that statement

There is no output operation. Predict what should print before opening any
compiler code.

Nothing in this source asks to print seven. Returning a value and displaying
a value are different actions, just as keeping 65 on a Forth stack differed
from passing it to `emit`.

But `main` has no caller in the source. We need to find one.

## The compiler puts a caller in the file

A **program file** contains bytes. A **process** is an instance of a program
running with its own memory and machine state. Our Forth C compiler runs as
one process, the **builder**. The executable it produces can later run as a
different process, the **target**.

In the legacy direct-ELF profile used here, the builder supplies a short
**entry stub**: code that calls `main`, receives its result, and asks Linux
to terminate the target, passing along that result. For our value seven,
the reported **exit status** is also seven. An exit status is a number the
parent process can collect when a program finishes. It is not a character
written to standard output; Linux reports only the low byte of this
exit value, so larger return values need that extra rule.

ELF is the executable-file format here. Its header tells the loader where
execution starts. The start is the entry stub, not the first instruction of
`main`. That extra caller resolves the missing piece in the C source.

For this one input, the source-derived output layout is:

| File region | Bytes in this region | Next unused byte offset |
|---|---:|---:|
| ELF headers | 120 | 120 |
| Entry stub | 26 | 146 |
| Eager runtime bodies and their embedded data | 376 | 522 |
| `main` | 34 | 556 |

An **offset** counts bytes from the beginning of the file, starting at zero.
The next-unused offset is therefore also the length so far. These four
region lengths are supplied facts for this entrance; C19 derives them. In
particular, the compiler emits those runtime bytes even though our input
never calls their functions.

The first `main` instruction will be at offset 522. Yet the builder wrote
the stub before reaching the source definition. How can its call name a
destination that is still unknown?

It reserves four bytes, remembers their position, and fills them after
`main` has a position. That deferred repair is a **patch**. Here the field
begins at offset 130 and ends just before 134. This kind of call records the
distance from the next instruction to its destination. This distance is
called the **call displacement**:

```text
next instruction: 130 + 4 = 134
destination:      522
distance:         522 - 134 = 388 bytes
```

The builder overwrites the reserved field. It does not append another four
bytes, so the total stays 556. This is our first small compiler mechanism:
keep enough information about an unfinished use to complete it once its
destination is known.

Only later, if the file has been successfully written and loaded under the
stated Linux/x86-64 profile, does the target follow the stub to `main` and
back, then request termination with status seven. The calculation does not
create that file or observe its execution. The legacy writer's unchecked
write result makes checking the stored file a separate necessity.

You can now explain the whole path without explaining every compiler word.
[C19's first story](c-compiler/chapters/19-translation-units-and-process-entry.md)
opens the exact bytes, frame and construction steps. Its later reference
sections open the rest of the translation-unit implementation. Continue
there when you want to derive the supplied lengths, not because the seven
is still mysterious.

## Try a change

Use [hints and feedback](practice/first-results-solutions.md) whenever a
starting step is missing. To try independently, leave that file closed.
These entrance tasks supplement the stable chapter exercises; they do not
replace them.

### H1-01 — Keep the older value

Start at `[99, 32]`. Write the states after `dup`, `+`, `[lit] 1`, `+`, and
`emit`. Then explain which statement needs a successful-output assumption:
“99 remains on the stack” or “an A arrived at the output destination.”

### H1-02 — Send the result to memory

Here is the new contract you need. A memory **address** identifies a byte
location. Assume address 1000 is yours to write, with three consecutive bytes
at addresses 999, 1000 and 1001 initially holding 10, 20 and 30.

`c!` consumes a value and an address, with the address on top. It stores only
the value's low byte at that address. Thus its stack inputs have the shape
`[..., value, address]`.

After the same calculation reaches `[99, 65]`, run `[lit] 1000 c!` instead of
`emit`. Give the final stack and all three bytes. Does this sequence request
any output? These are illustrative memory addresses, not addresses to paste
into a running process. [S2](seed-forth/chapters/02-addresses-and-bytes.md)
opens the address/value model in full.

### H2-01 — Find the unfinished use

Using the four supplied region lengths, reconstruct the next-unused offset
after each region. Then fill in the call-distance expression using the start
of its field, its width and `main`'s position. Explain why patching does not
make the image 560 bytes long.

### H2-02 — Move a body, keep the result

For this paper variation, suppose the compiler accepts an unused helper
whose emitted body is 34 bytes. The compiler emits every user function body in source
order. Put that helper before `main`, with everything else unchanged.

Which change: the entry-stub start offset, `main`'s offset, total size, call
displacement, or the specified `main` result? Give each revised number and
explain why it changes or stays the same. What changes if the helper is
instead placed after `main`? You are given the helper's length; this task is
about layout dependence, not compiling an unprovided source.

## Choose the next question

- To follow Forth composition more deeply, continue with
  [S1](seed-forth/chapters/01-values-and-words.md), then its memory bridge
- To open this compiler's supplied pieces, follow
  [C19's first story](c-compiler/chapters/19-translation-units-and-process-entry.md).
  The [C01 profile](c-compiler/chapters/01-compiler-entry-and-profile.md#name-the-compiler-profile)
  explains why later profiles must be named separately
- To see a richer application, return to
  [C01's triangle](c-compiler/chapters/01-compiler-entry-and-profile.md)
- To see why the series moves next toward separately compiled objects, use
  the [five-milestone map](HYBRID-NARRATIVE.md)

Pause at a resolved question. For a useful restart, keep the last state you
could explain and one next prediction. You need not reconstruct an entire
chapter before continuing.

## Source and run status

The Forth contracts come from the pinned seed's
[`emit` and `bye`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L251-L276)
and the S1/S2 source-checked explanations. The C fixture uses the fresh
legacy Linux/x86-64 profile: ordinary default hooks, `cc-target-lp64=0`,
`cc-target-sysv=0`. Its exact construction and valid-input/capacity/loader
assumptions are in C19. The supplied helper-length variation is a layout
model, not a second observed executable.

A runnable entrance still needs a verified starting seed, exact fixture
files, clean reset and output capture, and an actual clean-start check. The
pinned [build entry](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/build.sh)
requires an identified initial hex0 translator; it does not conjure one from
source. Until those entrance checks are performed, this page promises a
paper result, not a tested installation recipe.
