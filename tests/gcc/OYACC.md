# Original oyacc source-only check

Pass the preserved, verified oyacc-6.6 source directory to oyacc-check.py.
The pinned archive and all twenty original file hashes are in oyacc-source.json.
The checker copies the original inputs with their license notices, extracts
upstream configure's C probes, and runs those compile/link checks with the
Forth driver. Only the trivial cccheck probe is executed. No host configure
answer or shipped generated parser is a production input.

All thirteen unchanged original translation units are compiled and linked.
The resulting oyacc generates parser C, token header and an automaton report
from the project arithmetic grammar. If host GCC exists, an independent build
of the same original sources uses separately measured host configuration;
all three generated outputs must match byte-for-byte. Real program checks
verify cleanup of three temporary files after SIGINT and preservation of an
inherited ignored SIGINT disposition.

The default additionally Forth-compiles and executes the untouched generated
parser on ten arithmetic/error/stack-growth cases, with a separate host parser
oracle. --generate-only deliberately stops before this consumer stage and
records consumer_execution as not_run. It does not bypass #line processing.

The unchanged upstream portable.c asprintf fallback has a 32-byte allocation
limit. The recipe uses short relative output names such as parser.c within
that boundary. No arbitrary-length output-name, complete Flex/Bison ancestry,
or completed GCC bootstrap claim follows from this bounded check.
