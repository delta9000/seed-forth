# Return check after I/O, dictionary, and compiler internals

These paper tasks mix [physical I/O](../chapters/14-physical-io-and-exit.md),
[dictionary and token input](../chapters/15-dictionary-and-token-input.md),
and [the native colon compiler](../chapters/16-native-colon-compiler.md).
Keep the actual contracts available. A source-matched byte sequence is not
permission to assume a missing input or error-handling guarantee.

## R5-01 An old output byte becomes apparent input

The shared scratch byte contains 65 after an earlier output operation. The
logical data stack is `[99]`. A call to `key` issues its one-byte read, which
returns a raw negative error, and no new byte was written into the scratch
location. Following the inspected instructions, what does `key` leave on
the logical stack? Does its returned value establish that the input supplied
an `A`? Explain the first incorrect assumption a higher-level reader could
make if it treated every nonzero result as fresh input.

## R5-02 A new name binding and an old call coexist

An ordinary word `seven` pushes 7. A word `use-seven` is compiled with a
direct call to that definition. Later, another ordinary definition named
`seven` is created and pushes 8. The old code remains intact. What does a new
dictionary lookup of `seven` select, and what does the already compiled
`use-seven` call? Which mechanism from Chapter 10 would be needed if the
intent were to change an existing caller's selected operation through a cell?

## R5-03 A pending branch fixup survives a compiled literal

Inside a definition, `[lit] 3` has read and parsed its numeric token, discarded
the success flag, and is about to emit the compile-mode literal. Let C be the
compile-time data stack. Before emission, `C=[F,3]`, where F is an older
unfinished branch fixup. HERE contains P. Trace the temporary push of the
`lit` execution token, `compile_call`, and the comma tail-call. What is C
afterward, how far has HERE advanced, and which bytes carry the number 3?
Do not confuse F with the runtime data stack of the finished word.

## R5-04 The accepted bound and the fatal path are different

An ordinary non-comment token contains 256 non-whitespace, non-NUL bytes.
Follow `read_word` at the boundary after 255 have been stored. Is the next
byte rejected before or after storage? What length does the fatal path use
for its report, and what exit status does it request? Does this path create
a dictionary entry with a wrapped zero name length or silently return a
255-byte token? State separately what the write request asks for and what
successful delivery would require.

## Hints

- R5-01: The branch after the syscall tests equality with zero, not whether
  the returned count is positive
- R5-02: Follow the lookup link chain at compile time, then the encoded
  relative call at runtime
- R5-03: `compile_call` consumes its xt; comma consumes the value below it;
  older C items remain underneath both
- R5-04: Locate the store, increment, test of `bh`, and jump to `fatal_token`
  in that order

## Answers and changed checks

### R5-01 answer

The negative result is nonzero, so the zero-result EOF branch is not taken.
The code reads the unchanged scratch byte and returns 65. The final logical
stack is `[99,65]`: `key` preserved its older data prefix, but it did not
preserve a trustworthy input-status distinction. No new `A` was established.
The higher-level reader would be mistaking a stale byte for a successful
read.

For a changed check, let the scratch byte contain zero. The same negative
error can then appear as the zero sentinel. Changing the old byte changes
the apparent input; neither result is a valid error-reporting contract.

### R5-02 answer

A fresh lookup starts at the newest header and selects the new `seven`,
whose body pushes 8. The old encoded call in `use-seven` still targets the
earlier body and pushes 7. It does not rerun a name lookup each time.
Deferred dispatch supplies the additional indirection: a caller targets a
stable deferred-word body, which reads the current execution token from a
mutable dispatch cell. Updating that cell can change behavior without
rewriting the caller.

For a changed check, compile a second caller after the redefinition. Its
ordinary call selects the new 8-producing body. The two callers may therefore
coexist with different targets despite using the same source spelling.

### R5-03 answer

The helper temporarily preserves n and makes the xt the cached top:
`[F,3] -> [F,3,lit-xt]`. `compile_call` emits a five-byte call and consumes
that token, leaving `[F,3]`. Comma stores the eight-byte value 3 after the
call, advances HERE by eight, and consumes 3, leaving `[F]`.
The net cursor increase is thirteen bytes. The inline cell contains
`03 00 00 00 00 00 00 00` in hexadecimal; the call's four-byte displacement
reaches the `lit` primitive and is not the encoding of the number 3.

For a changed check, compile zero. The inline cell becomes eight zero bytes,
but the call still occupies five bytes, F still survives, and the total size
remains thirteen. A literal's numeric magnitude does not shorten this format.

### R5-04 answer

The 256th byte is stored at TIB+255, then the length is incremented to 256.
Testing `bh` detects that bound and branches to the fatal path. The report
appends question mark and newline after the 256 stored bytes and requests
a stdout write of 258 bytes. `fatal_token` then requests exit status 2.
It neither returns a truncated token nor creates a wrapped-length header.

The report is a single raw write whose result is ignored. The request for
258 bytes is not proof that all 258 reached the destination; errors and
partial progress retain their earlier I/O meanings.

For a changed check, use 255 bytes followed by whitespace. That length fits
the accepted token contract and the one-byte dictionary name-length field.
The reader returns a pointer and count, not a promised terminating NUL.

## Choose the relevant distinction

The four errors to watch are stale byte versus fresh input, name lookup
versus encoded identity, compiler work stack versus future runtime data,
and requested report versus delivered report. Trace the first differing
transition, use its hint, then try the changed case. These remain checks of
specified reasoning, not observed executions or guarantees about every input.
