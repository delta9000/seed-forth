"""Keep two explained copy operations out of host-capture fixture payloads.

This is authoring-time bookkeeping, not a bootstrap generator.  An original
archive member can replace a captured duplicate only when its bytes are
unchanged.  Bash's native signal header can replace a fixture only after
the captured mksignames execution that produced the same bytes.
"""


def fixture_copies(package, fixtures, original, final, replay_outputs, events):
    """Return (original-source copies, copies after numbered replay events).

    Paths are source-relative.  Values in original/final are complete file
    bytes; replay_outputs is the set of paths written by replayed programs.
    The event dictionaries deliberately expose only kind/program/arguments.
    The caller retains any fixture for which the evidence is insufficient.
    """
    archive_copies = {}
    # Source-identical aliases include gawk's awklib/{grcat,pwcat}.c.
    # Check final[source] too: configure may have edited an archive member.
    originals_by_bytes = {}
    for source in sorted(original):
        data = original[source]
        if final.get(source) == data:
            originals_by_bytes.setdefault(data, source)
    for target in sorted(fixtures):
        data = final[target]
        if data in originals_by_bytes:
            archive_copies[target] = originals_by_bytes[data]

    generated_copies = {}
    # Bash Makefile.in:739-745 runs ./mksignames lsignames.h, then copies
    # that result to signames.h.  The capture already replays the generator;
    # its host cp was the only reason signames.h became a fixture.
    target, source = "signames.h", "lsignames.h"
    if (package == "bash-5.2.37" and target in fixtures
            and source in replay_outputs
            and final.get(source) == final[target]):
        producers = [i for i, event in enumerate(events)
                     if event.get("kind") == "exec"
                     and event.get("program") == "mksignames"
                     and event.get("arguments", [])[1:] == [source]]
        if len(producers) == 1:
            generated_copies[producers[0]] = [(source, target)]
            archive_copies.pop(target, None)
    return archive_copies, generated_copies
