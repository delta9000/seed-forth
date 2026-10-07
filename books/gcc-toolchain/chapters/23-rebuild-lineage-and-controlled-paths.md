# Rebuild lineage and controlled paths

Three directories labeled stage2, stage3 and stage4 do not explain which
compiler built which bytes. What must remain constant for a difference between
them to say something useful?

Follow one GCC generation through Stage D’s actual producer sequence. Then
change the installation path in a paper counterexample. The recorded recipe
names its equality requirement; we do not execute it anew.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

G22 supplies the installed Stage C GCC and musl sysroot. A **generation** is a
compiler product built by a named predecessor. DESTDIR changes where
installation is staged while the configured prefix remains the logical installed
path. Paths can become bytes inside executables, making them comparison inputs.

## Name each arrow before comparing the boxes

Stage C’s installed GCC, whose compiler proper and driver were built by Forth,
builds stage 2. Stage 2 builds stage 3. Stage 3 builds stage 4. Each later
generation uses the same identified Stage C binutils/sysroot and Forth-built
oyacc/flex producers.

This is a C-only GCC 4.0.4 native Linux AMD64 lineage. It is not the historical
TinyCC→gcc64→newer-GCC ladder, and those executable ancestors must not be
inserted simply because some source adaptations are shared with gcc64.

The Stage D recipe compares stages 2 and 3 as well as stages 3 and 4. It does
not settle for eventual agreement between the last pair. Nor does it require the
original Forth-built Stage C compiler executable itself to equal stage 2: the
compared set is the later GCC-produced installed generations.

Sources: [generation identities and
criterion](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L8-L25),
[actual build and comparison
sequence](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L170-L191).

## Reuse coordinates, stage installation separately

Every build extracts into the same source path, creates the same build path and
configures the same prefix. Stage 2 installs directly at WORK/prefix. Stages 3
and 4 install under their DESTDIR trees, whose full installed path concatenates
staging root and prefix.

The predecessor compiler path changes, as it must, but the product’s
source/build/prefix coordinates remain controlled. Debug text, search defaults
or generated path strings can otherwise differ merely because the stage label
changed. Comparing products configured with prefix /stage2 and /stage3 would ask
another question.

A shared path alone is not a shared live source tree. The recipe freshly
extracts the same selected C-only source and reapplies its identified
adaptations for each build, removing stale generated/compiled state. Retained
per-stage logs name compiler and installed tree.

Sources: [fresh source and common path
construction](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L135).

## Retain the source adaptation that a real GCC needs

GCC system.h exempts FLEX_SCANNER and YYBISON from malloc/realloc poisoning,
while other logic recognizes YYBYACC parser output. The Forth-built oyacc
defines YYBYACC. Stage D makes that exemption consistent, requiring the original
line to occur exactly once before replacing it.

The collect2 patch is applied as in the repository’s gcc64 recipe, with exact
patch commands and no fuzz. Parser/scanner generation still names the
Forth-built tools. This is a separately documented Stage D source adaptation,
not Stage C’s no-C-source-patch policy carried forward unchanged.

Only named C language subtrees are selected; omitted Java, C++, Ada and other
trees do not become unsupported evidence hidden behind “GCC 4.0.4.” The selected
configuration and source set define the artifact comparison’s domain.

Sources: [poison exemption and source
selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L35-L62),
[checked adaptation
application](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L97).

## Keep target tools and build overrides in the lineage

Stage D configures libiberty, libcpp and gcc with explicit native tuple, static
flags, target sysroot and the same as/ld. AR/RANLIB and parser-generator
variables name source-built tools. The Make overrides include supported
optimization/static linkage and target header paths, plus the recorded
fixincludes/installation adjustments.

The first Stage C cc1 can require a deep stack because Forth-generated frames
are larger. Stage D raises its stack limit to 64 MiB before starting the builds.
That is an execution-environment input, not a source feature or an output
normalization rule.

Host environment, Python, shell, make, archive extraction, patch and platform
services remain. “No host compiler produces these objects” is the bounded
producer claim; it does not assert a source-only machine with no operational
dependencies.

Sources: [configure environment and make/install
inputs](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L99-L135),
[stack
setting](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L169-L174).

## Explain a mismatch before treating it as a defect

Supply two otherwise identical installed gcc files whose only differing bytes
encode /tmp/run2 and /tmp/run3. That mismatch establishes unequal files, but not
a miscompiled arithmetic operation. First control the path inputs or explicitly
choose a path-normalization predicate; the actual recipe controls them rather
than masking arbitrary executable bytes.

A runtime algorithm can also change legal code-generation choices without
changing source semantics. G24 will open the recorded equal-key sort difference.
That cause remains part of the compiler’s execution environment, even when the
sort function’s public contract is valid.

The source documentation reports the later Stage D closure under its specified
recipe. We have no new build logs or installed artifacts from this manuscript
work. The lesson prepares the exact comparison in G25 rather than declaring a
fresh fixed point from source inspection.

Sources: [recorded fixed-point
lineage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L512-L541).

## Name generations by the compiler that made them

Stage C is the available Forth-built first GCC with its hosted runtime closure.
It builds stage 2. Stage 2 builds stage 3. Stage 3 builds stage 4. Write the
executable producer above each arrow, and write the source/generated inputs
below it. A stage number alone is insufficient if an unexpected host compiler
supplied one of those products.

The executing compiler's runtime belongs to that arrow too. When Stage C cc1
runs, it uses its source-built seed runtime. Later GCC generations run with
musl. G24 will show why that difference can change bytes even when all compiler
source files are retained. Runtime identity is therefore part of the producer's
behavior, not merely a target program dependency.

The configured language scope is C. A completed C-only rebuild is the stated
achievement; it does not silently establish additional GCC frontends. The script
also supplies an enlarged stack limit. That operating environment can be
necessary for build work without being source code compiled into GCC. Preserve
it with the recipe rather than calling it part of a new target ABI.

Sources: [generation identities and
criterion](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L8-L25),
[actual build and comparison
sequence](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L170-L191).

## Hold path inputs constant without overwriting generations

Build and installation paths can become strings embedded in compiler products.
Supply two otherwise matching builds configured with different prefixes. They
can differ as installed files even if they compile the same simple source. Such
a difference would be evidence of changed input, not necessarily a
compiler-generation defect.

The Stage D recipe retains a common configured prefix while using separate
installation destinations. DESTDIR stages an installation into different trees
without requiring each generation to advertise a different compiled-in prefix.
The trees can then be compared as independent artifacts. Distinct storage
locations and common semantic path inputs solve different needs.

Use the same discipline for build-path identity. It is tempting to make
stage-numbered source/build directories for convenience and then normalize the
resulting binaries afterward. The inspected recipe instead controls the
producing inputs at the intended boundary. Its comparison does not broadly erase
embedded path bytes after production.

Sources: [fresh source and common path
construction](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L135).

## Retain the parser intervention as an intervention

The generated parser's YYBYACC preparation and the collect2 adjustment are
checked recipe inputs. The poison/preparation logic expects a specific
occurrence rather than applying an unbounded text replacement. This helps
preserve the claim about which input was changed. It does not establish that
arbitrary regenerated parser source would have the same shape.

Keep the transformation, its selected input and the resulting prepared bytes
alongside compiler identities. A rebuild graph with only upstream archive names
would omit an actual source difference consumed at production. Conversely,
calling every Make setting a compiler-source patch would obscure where the
change lives.

The final comparisons require stage 2 against 3 and stage 3 against 4. They do
not require the earlier Forth-built Stage C installation to have identical
bytes. A transition from a different producing compiler and runtime can be
relevant to the diagnosis while remaining outside the stated later fixed-point
predicate.

No new generations were built for this chapter. The lineage and controls are
inspected recipe facts; the reported agreement belongs to the repository's
retained account. G24 opens the documented mismatch that made the runtime arrow
visible, and G25 reads exactly what the successful comparison accepts.

Sources: [poison exemption and source
selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L35-L62),
[checked adaptation
application](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L97),
[configure environment and make/install
inputs](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L99-L135),
[stack
setting](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L169-L174).

## Distinguish an input control from a comparison exception

A common configured prefix prevents generation-specific installation strings
from becoming different compiler inputs. Reusing source and build coordinates
addresses another embedded-path source. DESTDIR separates installation trees for
storage and comparison. These are controls before production, not exceptions
that forgive arbitrary differences afterward.

The archive-member predicate in G25 is different: it compares a defined content
view after complete-container hashes differ. Do not conflate this with broad
path normalization. The ordinary executable comparison still expects matching
file-content digests. If a path string differs, it remains a difference until
the producing inputs are controlled and the products rebuilt.

| Recorded control | Layer it affects | Why it belongs in lineage |
|---|---|---|
| Same source/build coordinates | Build inputs | Embedded source/build names can change bytes |
| Same configured prefix | Configuration | Tool search strings can change bytes |
| Separate DESTDIR | Artifact storage | Generations remain independently retained |
| YYBYACC exemption | Prepared parser context | Actual GCC input differs from pristine text |
| C-only configuration | Product scope | Only selected frontends enter comparison |
| Enlarged stack limit | Running build environment | Producer has admitted execution resources |

The checked parser change expects exactly one poison-exemption line before
transformation. That occurrence guard prevents silently adapting an unexpected
source shape. It establishes where the recipe intends to intervene, not that
every future GCC release can use the same patch. The selected collect2 patch is
another retained source preparation in this bounded route.

Stage C builds stage 2 using its own runtime, then stage 2 builds stage 3 on
musl, and stage 3 builds stage 4. The source-built downstream tools and sysroot
remain named inputs. If bytes differ, compare the whole producer edge, including
runtime and environment, before attributing cause solely to compiler source.

Reading build() can establish this intended sequence. Only retained completed
steps and artifacts can establish a new run of it. The successful result in the
series belongs to the pinned record, with both required adjacent comparisons.
The manuscript has not created three generations or calculated fresh
installed-tool hashes.

Sources: [fresh source and common path
construction](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L135),
[poison exemption and source
selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L35-L62),
[checked adaptation
application](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L97),
[configure environment and make/install
inputs](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L99-L135),
[stack
setting](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L169-L174),
[recorded fixed-point
lineage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L512-L541).

## A build label cannot identify its executable producer

Imagine three directories named stage2, stage3 and stage4. Without the actual
compiler invocations, those names do not establish lineage. Any one could
contain files copied from elsewhere or built by a host compiler. The Stage D
recipe specifies the producer of each generation and retains commands/results so
the labels have concrete meaning.

Stage C's installed GCC builds stage 2. The stage-2 compiler builds stage 3. The
stage-3 compiler builds stage 4. Each uses the selected downstream tools and
musl sysroot. Add generated parser/scanner inputs, source preparations and
configuration arguments to those arrows before interpreting equal output.

Identical source archives are only one part of the input. The recipe uses fresh
C-only source preparation with the checked YYBYACC poison exemption and selected
collect2 patch. It configures components one by one and explicitly disables the
fixincludes stamp work. These are actual recipe choices, not facts implied by
the source version number.

Path control is another actual choice. The same source/build coordinates and
configured prefix prevent incidental generation labels from becoming embedded
byte differences. Separate DESTDIR trees retain distinct installed artifacts
without changing the common advertised prefix. This addresses a cause before
producing output rather than erasing mismatches afterward.

The stack limit belongs to the running build environment. It does not change the
target C data model, but can affect whether a producer completes its work. Keep
operating assumptions beside the command record. The C-only language selection
similarly limits the product domain; other frontend files are not covered by
these comparisons.

The earlier compiler's runtime and later musl runtimes also belong to the
producer edges. Their differing qsort behavior was the recorded cause opened in
G24. A source-only comparison would miss that input. Holding source paths
constant does not hold every runtime algorithm constant.

Both adjacent comparisons are required: stage 2 versus 3 and stage 3 versus 4. A
last-pair match alone leaves the recipe's earlier-pair condition unresolved. The
Forth-built Stage C installation is not required to be byte-identical to stage 2
under this predicate. Its role is the identified starting producer, with
different compilation ancestry and runtime behavior.

The chapter's graph is a source-derived account of the recipe and attributed
records. It does not turn reading build() into a completed three-generation run.
A future reproduction should preserve every generation's installed inventory,
hashes, commands, prepared source and reports so both lineage and comparison can
be challenged independently.

Sources: [generation identities and criterion](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L8-L25), [actual build and comparison sequence](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L170-L191), [fresh source and common path construction](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L135), [poison exemption and source selection](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L35-L62), [checked adaptation application](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L78-L97), [configure environment and make/install inputs](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L99-L135), [stack setting](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/stage-d.py#L169-L174), [recorded fixed-point lineage](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L512-L541).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](22-hosted-closure-with-libgcc-and-musl.md) remains available
for a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/23-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G23-01 — Draw the lineage

Name producers for stages 2,3,4. Explain which supplied rule determines your
answer. Keep any prediction separate from a claim that the corresponding program
or build was run.

### G23-02 — Read the criterion

Is equality of stages 3/4 alone enough for this recipe? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G23-03 — Control paths

Why not configure each generation under a different prefix? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G23-04 — Keep patches visible

Why add YYBYACC to the poison exemption? Explain which supplied rule determines
your answer. Keep any prediction separate from a claim that the corresponding
program or build was run.

### G23-05 — Bound language scope

Does C-only GCC equality compare all GCC languages? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G23-06 — Diagnose unequal paths

Two files differ only in embedded run-directory strings. Does that prove a
semantic compiler error? Explain which supplied rule determines your answer.
Keep any prediction separate from a claim that the corresponding program or
build was run.

### G23-07 — Report evidence

May source inspection of build() be called a newly completed Stage D run?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

## What this mechanism makes available

You can now name the compiler building each later gcc generation. Use the state
transitions above to justify that explanation, rather than treating a source
filename or a successful later milestone as a substitute for the mechanism.

Continue to [G24: Equal sort keys and unequal
bytes](24-equal-sort-keys-and-unequal-bytes.md). The [series map](../README.md)
also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
