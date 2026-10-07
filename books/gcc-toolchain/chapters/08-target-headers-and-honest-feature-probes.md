# Target headers and honest feature probes

A header can select a prototype branch because a macro is defined. Does that
definition establish that the compiler implements every feature usually
associated with the macro?

Follow the target’s actual predefines into one header choice, then follow a
configure test into a retained answer. The two kinds of choice have different
producers.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G03 supplies declaration checking.
[C03](../../c-compiler/chapters/03-preprocessing-regions-and-includes.md),
[C04](../../c-compiler/chapters/04-macro-expansion-and-rescanning.md) and
[C05](../../c-compiler/chapters/05-conditionals-and-profile-extensions.md) open
includes, macros and conditional/location state. Locally, a **probe** is a small
attempted compilation, link or execution whose result a configuration script
consumes.

## Advertise the selected target

System V mode defines __STDC__=1, __STDC_HOSTED__=0 and __SEED_FORTH__=1, plus
__linux__, __x86_64__ and __LP64__. It installs dynamic file/line entries too.
It does not invent __GNUC__ or a C99/C11 version macro. Loading the file merely
installs a target hook; the hook adds these names only when System V is active.

The hook runs after macro-table reset and before the user source. This gives
each translation unit the chosen target policy instead of retaining an earlier
source’s definitions. Command-line defines and undefines are applied in their
supplied order afterward. User options do not become arbitrary runtime-build
options.

A historical header can use __STDC__ to select prototypes and qualifiers. That
is a supported branch policy for this bounded C90-oriented compiler. The macro
is neither a complete conformance certificate nor an implementation of missing
builtins. __STDC_HOSTED__=0 also does not imply there are no runtime C
functions; it describes the advertised environment contract.

Sources: [target
predefines](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/124-cc-target.fth#L1-L21),
[include and macro
ordering](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L28-L43).

## Use the headers belonging to this runtime

stddef.h declares size_t as unsigned long, ptrdiff_t as long and the target’s
offsetof spelling. stdarg.h declares the real array-of-one record consumed by
G12’s intrinsic provider. stdio.h declares an opaque FILE and says its streams
are unbuffered with no host-FILE compatibility.

Those declarations do not create implementations. A caller must compile with the
appropriate header and link the selected source-built runtime members.
Conversely, supplying an implementation without its correct declaration can make
a C90 caller assume int when the real return is a pointer. The linker cannot
detect all such losses.

Include lookup follows explicit configured paths, with quoted-source-relative
search before include directories. The default bounded runtime directory is
last; -nostdinc removes it. No host header directory is silently supplied by the
direct Forth compiler driver. G21’s first GCC driver has a different include
situation, and G22 supplies its actual target sysroot.

Sources: [LP64 header
types](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stddef.h#L1-L9),
[variadic header
ABI](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdarg.h#L1-L18),
[stream surface and
limits](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdio.h#L1-L66).

## Let an unsupported option fail honestly

The direct driver accepts flags describing its real output, including -static,
-O0 and -g0. It rejects -g, -O2 and unknown options instead of pretending to
optimize or emit debug data. GCC configure’s debug probe should therefore fail
and can select a non-GNU fallback with empty CFLAGS.

The original Makefile template can still hardcode -g after configure accepted
empty flags. The recipe passes CFLAGS= and LDFLAGS= to make explicitly. That is
an identified build override; it is not a forged successful -g probe. A
generated feature answer and a later Makefile’s behavior must both be inspected.

Binutils’ warning logic historically inferred GNU versions too broadly and
selected an unsupported warning flag. G20 retains the explicit warning overrides
and the reason. Setting __GNUC__ just to get through a header or probe would
send consumers down branches whose promised semantics may be absent.

Sources: [accepted and rejected
flags](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L66-L74),
[Makefile flag
override](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L164-L168),
[warning selection
boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/binutils.py#L12-L24).

## Retain the question that produced an answer

A configure success is a script result, not proof of every positive feature
macro. The recipe starts with empty flags, no site configuration and no
prefilled cache, and guards host target tools. Each probe trace keeps arguments,
working directory, C/object inputs, headers, diagnostics and successful outputs.
The invocation/environment and probe inventory remain inspectable.

If a feature test links without running, it cannot establish the function’s
executed behavior. If it compiles a declaration only, it cannot establish a
definition. If the host linker is guarded and a probe fails, that failure must
stay visible instead of being recoded as a success for convenience.

The lesson’s small evidence table is therefore qualitative: a header-only test
supplies parsing evidence; a link test supplies selected symbol closure; an
executed test supplies its named behavior. We have not run new probes or copied
their expected answers into configuration.

Sources: [verified configure source and trace
contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L102-L148).

## Keep logical location separate from the opened path

Generated parser C often carries #line directives so diagnostics and
__FILE__/__LINE__ describe the originating grammar. The selected preprocessor
accepts its bounded C form: a macro-expanded decimal line number and optional
ordinary filename string. The physical opened path still determines relative
include search.

A macro invoked in a C file uses the invocation location, with saved argument
locations and the documented alias-tail rules. The flattened preprocessed line
used by current diagnostics is another coordinate. A reader should not claim
that every numeric diagnostic already identifies the original header or grammar
line.

Malformed or unsupported line-control forms fail under the direct gate. G18 will
retain original generated line directives rather than stripping them to hide a
missing contract. Source acceptance must be earned by the provider implementing
that form, not by silently changing all inputs.

Sources: [generated-parser production
context](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L471-L510),
[location policy and bounded line
control](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/40-direct-gcc-target.md#L22-L69).

## A feature probe is a question with a consumer

Supply a configure test that includes stddef and asks for the size of a pointer.
The selected target's LP64 metadata and target header determine what the
compiler sees. A successful compile can support this target-layout fact. It
cannot establish that every GNU extension is accepted or that an arbitrary
hosted library is present.

Now supply a different test guarded by a GNU-identity macro. Defining that macro
would select the guarded branch even if the compiler did not implement the
branch's required syntax or attributes. The predefine would therefore change the
question being asked. Honest feature selection keeps identity and admitted
behavior in agreement instead of obtaining a superficially successful
configuration by advertising an unrelated compiler.

The target-predefine hook is selected before preprocessing user input. It
supplies the compiler-facing token environment. The runtime header supplies
declarations and macros as source. A target runtime object supplies callable
implementation bytes. These three inputs cooperate, but one cannot replace
another. A stdio prototype does not implement fwrite; an errno object does not
declare every error constant; an LP64 macro does not generate startup.

Retain all three beside a later probe result: selected provider, exact header
inputs and linked runtime inputs. “The test compiled” omits whether it was
merely syntax-checked, emitted as an object, linked or executed. Configure can
ask several kinds of questions, each with its own acceptance event.

Sources: [target
predefines](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/124-cc-target.fth#L1-L21),
[include and macro
ordering](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L28-L43),
[LP64 header
types](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stddef.h#L1-L9),
[variadic header
ABI](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdarg.h#L1-L18),
[stream surface and
limits](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdio.h#L1-L66).

## Follow a diagnostic back to the prepared source

A compiler reads a physical input buffer, but a line directive can give later
tokens a logical filename and line. The source-location mechanism preserves that
distinction. Generated or preprocessed input can therefore produce diagnostics
naming the original source while the bytes came from a prepared file.

Suppose the physical buffer's fiftieth line carries a directive naming another
file and a new line number. The next diagnosed token must be interpreted through
the logical-location state, not merely a count of newline bytes from buffer
start. This does not change where the bytes were loaded or their ownership.
Logical identity serves reporting; physical identity serves input provenance.

A future retained probe should save its complete input, selected defines,
diagnostic output and exit status. If a source preparation step inserted a line
directive, keep that preparation too. A report containing only the logical
filename could otherwise hide which generated view was actually compiled.

Sources: [verified configure source and trace
contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L102-L148).

## Keep command admission alongside language admission

The direct driver's accepted arguments are also part of its interface. The build
recipe arranges compiler flags around that interface. Its use of empty Make
CFLAGS is meaningful when ordinary debug or optimization switches are not
admitted by this driver. Silently passing familiar host-compiler flags would not
make them supported.

This is a different failure from an unsupported C construct in an admitted input
file. Before diagnosing parser behavior, establish that the invocation itself
reached compilation. Before diagnosing runtime behavior, establish that it
linked against the intended target implementation. These short entrance checks
prevent a later toolchain chapter from treating every failed probe as evidence
about C semantics.

G17 will capture and replay configure observations in a named environment. This
chapter supplies the contracts for reading those observations: exact target
identity, honest branch selection, declared headers, real runtime providers and
phase-specific success. Its probes are paper questions; no new configure outcome
was measured here.

Sources: [accepted and rejected
flags](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L66-L74),
[Makefile flag
override](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L164-L168),
[warning selection
boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/binutils.py#L12-L24),
[generated-parser production
context](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L471-L510),
[location policy and bounded line
control](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/40-direct-gcc-target.md#L22-L69).

## Make a probe report answer the question actually asked

Supply three prospective probes using the same declaration: one parses it, one
takes its address and links, and one calls it in a target program. Parsing can
establish that the header's spelling is admitted. Linking can establish that the
selected providers close that use. Execution can establish a particular result
under the target state. They are related questions with different answers and
required inputs.

Now let an explicit include directory provide a header with the same basename as
the runtime header. The driver's search order can select that explicit input. A
report attributing the result to the runtime header without retaining search
order would be wrong even if the probe succeeded. Include search is part of the
source identity.

The logical filename supplied by #line does not move the physical file. Quoted
include lookup begins from the physical including directory under the documented
rule. Diagnostics can name the logical source while preparation and include
ownership remain tied to actual opened paths. Retain both identities if a
generated probe uses directives.

| Probe evidence | What it can support | Remaining obligation |
|---|---|---|
| Header parsed | Admitted declarations/macros | Function body and link |
| Object emitted | Selected translation behavior | Provider resolution |
| Executable linked | Named symbol closure | Loaded behavior |
| Named target run | That program's observed result | Broader inputs and features |
| Configure final status | Recipe's final decision | Individual probe outcomes and lineage |

A failed debug-flag probe belongs in the report even when the real build clears
its hardcoded flags and succeeds. It helps explain how the selected invocation
stays within the driver's interface. Omitting it would make the later
empty-flags choice look arbitrary and falsely broaden the compiler's advertised
capability.

The source-built FILE type is opaque for a reason. A header admits pointers to
its runtime's objects; a host FILE pointer belongs to a different
implementation. Name agreement and pointer-width agreement do not establish
layout or ownership agreement. A later test must create and consume streams
through the selected runtime itself.

This chapter's predefines select honest branches for the admitted compiler. They
do not supply a certificate for all C or GNU behavior. A new feature result
needs its own retained input, invocation and phase outcome. No new probe report
or configuration was produced for the book.

Sources: [LP64 header
types](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stddef.h#L1-L9),
[variadic header
ABI](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdarg.h#L1-L18),
[stream surface and
limits](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdio.h#L1-L66),
[accepted and rejected
flags](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L66-L74),
[Makefile flag
override](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L164-L168),
[warning selection
boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/binutils.py#L12-L24),
[verified configure source and trace
contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L102-L148),
[generated-parser production
context](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L471-L510),
[location policy and bounded line
control](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/book/40-direct-gcc-target.md#L22-L69).

## Read an include as a producer decision

A C source says which header spelling it wants, while the compiler invocation
supplies where to search. The runtime includes a target header directory, but an
explicit -I directory can take precedence. Quoted includes first consider the
including file's physical directory under the selected contract. A header's
familiar basename is therefore insufficient to identify the bytes that reached
preprocessing.

Supply two directories containing different stddef.h files. One is explicit and
one is the runtime directory. The first selected file can define a different
size_t or ptrdiff_t. A probe that compiles successfully has answered a question
about those actual selected declarations. It has not automatically verified the
runtime header the author intended.

A later record should retain the include options, actual opened paths and file
identities. Preprocessing output can help reveal which declarations reached the
parser, but preparation lineage still identifies where they came from. This is a
concrete way to separate producer intent from consumer evidence.

The selected runtime headers expose bounded APIs, including the real va_list
shape and opaque FILE declaration. An admitted header branch can make a
declaration visible without making the implementation available in every link.
Source generators that take a function address or execute a probe require
subsequent symbol and runtime closure. Keep those phases in the same include
record.

Target predefines also enter before header branching. Their honest identity
keeps the generated view within the admitted compiler. An unsupported option
failure is retained rather than hidden by impersonating another compiler. The
later build can deliberately use empty supported flags while the failed
debug-feature question remains negative evidence.

The chapter does not ask the reader to memorize every header. It asks for a
traceable choice: which bytes were selected, which macro branch they took, what
phase the probe reached and which runtime would complete the declared use. Its
examples are supplied alternatives and source inspection, with a fresh
include/probe transcript still pending.

Sources: [target predefines](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/124-cc-target.fth#L1-L21), [include and macro ordering](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L28-L43), [LP64 header types](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stddef.h#L1-L9), [variadic header ABI](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdarg.h#L1-L18), [stream surface and limits](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/runtime/gcc-seed/include/stdio.h#L1-L66), [accepted and rejected flags](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L66-L74), [Makefile flag override](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L164-L168), [warning selection boundary](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/binutils.py#L12-L24), [verified configure source and trace contract](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L102-L148).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](07-source-built-allocation-and-byte-operations.md) remains
available for a specific missing contract; its entire implementation is not an
entrance examination. The first four problems below revisit concrete state
transitions. The later problems change a representation, ownership or evidence
boundary. They can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/08-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G8-01 — Classify a macro

What do LP64, __STDC__ and __SEED_FORTH__ each identify? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G8-02 — Follow include order

Where does the driver’s runtime directory sit relative to explicit -I
directories? Explain which supplied rule determines your answer. Keep any
prediction separate from a claim that the corresponding program or build was
run.

### G8-03 — Separate declaration and body

A header-only probe accepts a function declaration. Has that function been
linked? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

### G8-04 — Read the rejected flag

Why may configure’s -g failure coexist with a successful build using empty
CFLAGS? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

### G8-05 — Keep location coordinates

A #line filename changes. Does relative include lookup follow that displayed
name? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

### G8-06 — Retain negative evidence

Configure exits zero but some guarded tool attempts failed. May the failures be
omitted? Explain which supplied rule determines your answer. Keep any prediction
separate from a claim that the corresponding program or build was run.

### G8-07 — Name the runtime

Why can the host’s FILE object not be passed to this runtime’s stdio? Explain
which supplied rule determines your answer. Keep any prediction separate from a
claim that the corresponding program or build was run.

## What this mechanism makes available

You can now use a real header/probe choice to connect target predefines with
c03-c05. Use the state transitions above to justify that explanation, rather
than treating a source filename or a successful later milestone as a substitute
for the mechanism.

Continue to [G09: Typed constants and symbolic
addresses](09-typed-constants-and-symbolic-addresses.md). The [series
map](../README.md) also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
