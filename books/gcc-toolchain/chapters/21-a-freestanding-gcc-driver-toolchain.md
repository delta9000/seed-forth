# A freestanding GCC driver toolchain

A -B directory can find cc1 without changing the assembler path baked into gcc.
How can a program silently use the wrong downstream producer even when its
driver came from this build?

Join G19’s compiler with G20’s output tools and follow the pinned freestanding
check. The result is a complete no-header executable chain, with hosted target
headers and libc still belonging to G22.

This is a paper lesson at the [pinned edition](../../EDITION.md). Its worked
states use inspected repository contracts and explicitly supplied inputs.
Existing results are attributed to their recorded source accounts; no new
compiler, generator, runtime, toolchain or produced program was executed for
this manuscript.

## Bring the needed contract

Retrieve both G19 and G20. A **driver** starts other tools and chooses their
arguments; collect2 participates in GCC’s linking path. A **freestanding**
fixture here provides its own Linux entry/syscalls and requests no default
libc/startup. This is narrower than arbitrary freestanding-language conformance.

## Install verified bytes under usable names

driver.py checks stage-B outputs against that run’s report before copying them
into WORK/toolchain under as, ld, ar, nm, objdump and readelf. ranlib uses the
identified ar-index operation. Copies retain their producing build identity; new
filenames do not create new compilers.

It configures libiberty with the frame adapter/archive support, libcpp with
archive support, and gcc with archive support and --with-binutils pointing at
that tool directory. The census links cc1 and Makefile rules build xgcc, cpp and
collect2. Those join the downstream tools, with xgcc installed under the name
gcc.

A successful copy and a later execution are separate steps. Reported installed
hashes let a reviewer compare the selected inputs, not just trust directory
names that could later be replaced.

Sources: [stage-B hash verification and
installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L76-L94),
[configure, census and GCC tool
installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L104-L180).

## Distinguish search prefixes from compiled defaults

GCC 4.0.4 searches -B prefixes for cc1 and collect2, first in target/version
subdirectories and then directly. The flat WORK/toolchain layout uses that
fallback. Without -B, the configured install prefix would guide those searches.

as and ld are different: DEFAULT_ASSEMBLER and DEFAULT_LINKER record absolute
configure paths and are preferred when executable. A driver configured against
guards will invoke those guards even if PATH or -B contains real tools.
--with-binutils changes the actual recorded defaults before the driver is built.

The toolchain is consequently tied to its WORK path. Moving the flat directory
alone does not rewrite embedded defaults. Reconfiguration/rebuilding and a new
record would be required for a relocated production path claim.

Sources: [baked defaults and -B
search](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L197-L246).

## Follow one command to a process result

The recorded fixture command uses gcc with its -B prefix, -O2, -nostdlib and
-static on tests/gcc/e2e-freestanding-hello.c. GCC compiles through cc1, invokes
the installed as and links through its selected collect2/ld path. The fixture
supplies Linux operations itself rather than depending on G06’s default
Forth-runtime startup archive.

The documented acceptance requires two printed lines and exit status 42. Those
are different observations: a captured status is not a printed number, and two
lines alone do not identify which tools produced the executable. The check
retains both behavior and invocation evidence.

This chapter does not execute that command. Its facts come from the pinned
recipe/check. A future reader run needs matching verified tools, recorded paths,
source and Linux execution support; a command copied into another work directory
is not automatically the same fixture.

Sources: [freestanding behavior and
evidence](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259),
[fixture entry and syscall
source](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-hello.c#L1-L21).

## Audit the tools that actually ran

The check uses a minimal PATH, parses verbose tool commands and, when tracing is
available, inspects successful execve paths. Every successful tool exec must
belong to WORK/toolchain. GCC’s guard log must not grow, and installed files
must contain no guard path.

A blocked host attempt is different from a successful host producer. The report
retains guard counts and capability limitations rather than assuming tracing
always works. Verbose commands are useful evidence but should not be called a
syscall trace when no trace was obtained.

A report-only oracle assembles the same -S output with project as and host as,
comparing .text bytes. The host result does not feed production. Matching .text
is a scoped comparison, not equality of every ELF header, debug record or
runtime behavior.

Sources: [end-to-end check
setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-check.py#L1-L80),
[execution paths, guards and
oracle](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259).

## Leave the header obligation open

The first driver still lists host /usr/local/include and /usr/include as system
include directories. The no-header fixture avoids them; it does not show a
source-built target-header universe. Its -nostdlib also bypasses default
runtime/startup closure.

G22 adds a verified musl sysroot before configuration, builds GCC runtime
libraries and startup objects, and exercises a hosted static program. The joined
chain is a meaningful milestone precisely because its boundary is stated:
compiler and output tools cooperate without host production assembly/linkage for
this fixture.

Do not infer that every compiler dependency disappeared. Host orchestration, OS
and hardware remain, and the source-built gcc executable itself runs on its
identified runtime. Direct production ancestry is narrower than “no trusted
platform.”

Sources: [include limit and next-stage
sysroot](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L255-L285).

## Resolve programs before resolving target symbols

Invoke the GCC driver on the planned freestanding fixture. Before any target
relocation can be resolved, the driver has to find the programs that perform
compilation, assembly and linking. cc1 and collect2 are driver-side executables;
as and ld are output tools. Their paths identify running producers, not target
symbols inside the final executable.

The selected installation uses a flat tool arrangement and explicit path
behavior. The driver probe retains hashes of the installed tools and the
commands it invokes. Read the compiler-search prefix and the configured
assembler/linker paths separately. Supplying a search prefix for cc1 is not
proof that an unrelated as found elsewhere was excluded.

Once the actual tools are identified, follow their outputs: C to assembly,
assembly to relocatable object, objects to executable. Preserve each file as the
input of the next identified executable. This turns a final exit status into a
traceable producer chain rather than an opaque assertion that “gcc worked.”

Sources: [stage-B hash verification and
installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L76-L94),
[configure, census and GCC tool
installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L104-L180),
[baked defaults and -B
search](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L197-L246).

## Keep the no-libc contract small enough to inspect

The fixture supplies its own low-level exit behavior and avoids a hosted C
runtime. Its observed output and exit status test the joined driver/toolchain at
a deliberately small boundary. The test does not ask GCC to provide musl
headers, startup files, ordinary stdio or libgcc closure for every source
construct.

This is useful because a failure can be localized. Did cc1 emit assembly? Did
the source-built assembler accept it? Did the source-built linker publish the
image? Did the executable reach its supplied entry and request the expected
exit? A later hosted failure should not retroactively erase evidence that this
smaller boundary was completed.

The assembly oracle compares the relevant text output using a host assembler in
the report-only branch. Name that producer when interpreting equality. A
comparison object made by host as is not the production object merely because
the two text sections match. The final target must consume the object made by
the source-built assembler for the production ancestry claim.

Sources: [freestanding behavior and
evidence](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259),
[fixture entry and syscall
source](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-hello.c#L1-L21),
[end-to-end check
setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-check.py#L1-L80),
[execution paths, guards and
oracle](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259).

## Leave hosted inputs for their own producer handoff

A working freestanding GCC driver still has configured include-search behavior.
Avoid assuming that every installed path already points at a populated
source-built sysroot. The next chapter will provide headers, startup objects and
runtime libraries under an explicit Stage C sequence.

That sequence also changes who compiles some products. Forth builds the first
GCC, then the resulting GCC builds selected runtime components. A libc function
used by a later hosted program can therefore exceed the seed runtime's
formatting subset without proving that the Forth compiler or seed runtime
implemented the same behavior.

For a future joined-toolchain record, retain invocation commands, all producer
hashes, output bytes and target status. The chapter attributes the existing
freestanding result to its pinned report. It has not rerun the driver probe,
observed new process execution or supplied a new host-assembler comparison.

Sources: [include limit and next-stage
sysroot](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L255-L285).

## A path is an input to executable selection

Supply a compiler-search prefix pointing at the installed cc1 and collect2. Also
retain the driver's configured absolute assembler and linker defaults. Moving
the directory containing cc1 does not necessarily update those defaults. Program
selection is a concrete algorithm over paths, not a promise that all tools next
to gcc will be preferred.

This matters when copying the freestanding toolchain to another location. A
copied gcc binary can retain a default naming its original WORK directory. Its
version message and path spelling may still look correct. The actual invoked
as/ld identities must be checked before attributing the resulting object to the
copied source-built tools.

| Selection evidence | What it establishes | What it leaves open |
|---|---|---|
| Installed file digest | Identity of that artifact | Whether the driver invokes it |
| Verbose command text | Driver's reported command | Successful execution syscall |
| Retained execution trace | Actual executable invocation | Correctness for all inputs |
| Produced object identity | This assembly result | Final executable behavior |
| Target output/status | This fixture's behavior | Hosted runtime closure |

Verbose commands are valuable for explaining the route, but a claim about
successful execve needs actual tracing evidence. Similarly, tool hashes are
valuable for ancestry but do not imply that a command ran. These distinctions
let a future fixture record precisely what it observed.

The no-header, no-default-library fixture retains its own entry and raw
output/exit behavior. Two printed lines and exit status forty-two belong to the
documented named run. They demonstrate a small joined chain when backed by its
retained record. They do not establish that the first driver already selects
only source-built hosted include paths.

The host-assembler oracle consumes the same generated assembly independently and
compares a bounded output view. Its result can help diagnose an encoding
difference. Its object must not replace the production object for the
source-built ancestry claim. Follow the object that the final link actually
consumes.

The source-built freestanding driver is the entrance to Stage C, where headers,
libgcc, startup and libc obtain explicit target producers. This chapter has not
moved a toolchain, traced a new execve, rerun the oracle or produced a new
target executable. It attributes the recorded fixture and explains the path
controls required to reproduce it.

Sources: [stage-B hash verification and
installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L76-L94),
[configure, census and GCC tool
installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L104-L180),
[baked defaults and -B
search](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L197-L246),
[end-to-end check
setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-check.py#L1-L80),
[execution paths, guards and
oracle](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259),
[include limit and next-stage
sysroot](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L255-L285).

## Ask what the driver invocation actually joins

The driver is the user's entrance, but its executable alone does not translate
every source into target instructions. It arranges preprocessing/compilation
through cc1, assembly through as and linking through the selected linker path
and collect2 behavior. The source-built toolchain result joins these identified
products in one invocation.

Supply a C input for the recorded no-libc fixture. cc1 supplies assembly; the
source-built assembler supplies an object; the source-built linker supplies the
executable; the loader and kernel supply the running process environment. The
fixture's own entry/output/exit code then supplies its observable behavior. Each
arrow has a different artifact and completion event.

The installation step hash-checks the stage-B products before copying them into
the tool directory. This supports actual executable ancestry rather than relying
on conventional names. The driver probe also retains installed compiler/support
tools. An artifact's digest identifies the bytes; the invocation record
identifies which bytes actually ran.

Compiler-prefix search and configured absolute defaults remain distinct. The
selected driver uses the compiler search prefix for cc1/collect2, while
assembler selection can prefer its configured absolute default. Passing -B is
not a general instruction to replace every embedded tool path. Copying the tree
elsewhere cannot automatically rewrite those defaults.

A future process trace can check actual program execution. Verbose driver text
supplies a reported command but does not by itself establish successful execve.
Preserve which evidence was collected before calling it a trace. If the driver
prints the intended assembler path but cannot execute it, command selection and
execution have different outcomes.

The report-only host assembler comparison makes a bounded output view available
from another implementation. It supports diagnosis without becoming a production
object supplier. The final link must consume the object made by the source-built
assembler for the direct-toolchain claim. Exact hashes and retained paths make
that choice reviewable.

The no-header fixture deliberately leaves hosted include/library/startup work
outside its scope. The first compiler installation can retain host
include-search defaults even while its no-libc output chain works. Stage C
supplies the intended musl sysroot and hosted closure under another recipe. This
is a concrete capability progression rather than a claim that one successful
program certifies every toolchain service.

The chapter attributes the recorded two-line output and status forty-two, plus
tool identities and oracle boundaries, to its pinned account. It has not
launched the driver or created a fresh output object. A new reader can explain
the complete small chain on paper before undertaking a separately retained
operational run.

Sources: [stage-B hash verification and installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L76-L94), [configure, census and GCC tool installation](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/driver.py#L104-L180), [baked defaults and -B search](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L197-L246), [freestanding behavior and evidence](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259), [fixture entry and syscall source](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-hello.c#L1-L21), [end-to-end check setup](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/tests/gcc/e2e-freestanding-check.py#L1-L80), [execution paths, guards and oracle](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L248-L259), [include limit and next-stage sysroot](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/gcc-direct/README.md#L255-L285).

## Stop, then change the boundary

Save the worked state you can now explain, including its owner and the phase at
which it changes. Reconstruct that state before moving to a changed case. If a
result differs, locate the first changed premise rather than replacing the final
number until it agrees.

The continuous story and reference mechanisms use the same selected profile. The
[previous chapter](20-building-the-downstream-binutils.md) remains available for
a specific missing contract; its entire implementation is not an entrance
examination. The first four problems below revisit concrete state transitions.
The later problems change a representation, ownership or evidence boundary. They
can be attempted in another session.

## Try the mechanism

Use paper states and the supplied contracts. The [hints, worked solutions and
separate changed checks](../practice/21-solutions.md) let you choose support
without exposing every answer. Write both a prediction and the reason; a correct
value with the wrong producer, coordinate or lifetime still needs repair.

### G21-01 — Separate search policies

Does -B automatically replace executable DEFAULT_ASSEMBLER? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G21-02 — Retain copied ancestry

Why hash-check stage-B outputs before installing as/ld? Explain which supplied
rule determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G21-03 — Interpret the fixture

What do two printed lines and status 42 establish? Explain which supplied rule
determines your answer. Keep any prediction separate from a claim that the
corresponding program or build was run.

### G21-04 — Trace production

Where does host as in the report-only oracle enter the chain? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G21-05 — Move a tool directory

Can copying WORK/toolchain elsewhere guarantee the same assembler selection?
Explain which supplied rule determines your answer. Keep any prediction separate
from a claim that the corresponding program or build was run.

### G21-06 — Bound hosted claims

Why does the no-header fixture not establish a musl sysroot? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

### G21-07 — Name execution evidence

May verbose tool names be called successful execve traces? Explain which
supplied rule determines your answer. Keep any prediction separate from a claim
that the corresponding program or build was run.

## What this mechanism makes available

You can now join g19 gcc and g20 output tools in a freestanding no-header
program. Use the state transitions above to justify that explanation, rather
than treating a source filename or a successful later milestone as a substitute
for the mechanism.

Continue to [G22: Hosted closure with libgcc and
musl](22-hosted-closure-with-libgcc-and-musl.md). The [series map](../README.md)
also provides the complete route and practice companions.

The evidence remains exact-pin source inspection, stated derivations and
separately attributed repository records. Actual new fixture bytes, cold/cache
transcripts, failure observations, clean-start setup, rendered layout and
independent reader learning have not been established here. Source coverage,
document checks, execution and learning are different states.
