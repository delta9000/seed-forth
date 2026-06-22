# tools/tangle.awk — extract literate code blocks from book/*.md.
#
# Driven by tools/tangle.sh.  Expects OUTDIR set on the command line.
#
# Recognized fence headers (the language token is ignored; only the
# attribute matters):
#
#     ```forth file=<path>          root block for <path>
#     ```hex0  file=<path>          root block for <path> (hex0 file)
#     ```hex0  chunk=<name>         named chunk, referenced by <<name>>
#     ```                           (anything else, ignored)
#
# Root blocks may contain lines of the form `<<name>>` (optionally
# indented).  Those are recursively expanded with the chunk body, with
# the leading indent of the reference prepended to every line of the
# expansion (so chunk bodies stay readable in the book).
#
# All other code blocks (no file= or chunk= attribute) are illustrative
# and ignored.

BEGIN {
    if (OUTDIR == "") {
        print "tangle.awk: OUTDIR not set" > "/dev/stderr"
        exit 2
    }
    in_block = 0
    block_target = ""    # "file:/path" or "chunk:name" while inside a block
}

# Match start of a tagged code block.
/^```[A-Za-z0-9_-]*[[:space:]]+(file|chunk)=[^[:space:]]+/ {
    in_block = 1
    block_target = ""
    if (match($0, /file=[^[:space:]]+/)) {
        name = substr($0, RSTART+5, RLENGTH-5)
        block_target = "file:" name
        if (!(name in seen_file)) {
            seen_file[name] = 1
            file_path[name] = OUTDIR "/" name
            # Truncate.
            printf "" > file_path[name]
        }
    } else if (match($0, /chunk=[^[:space:]]+/)) {
        name = substr($0, RSTART+6, RLENGTH-6)
        block_target = "chunk:" name
        # A chunk may legitimately be (re)defined; concatenate.
    }
    next
}

# Any fenced block opener without our attributes — skip its body.
/^```/ {
    if (in_block) {
        in_block = 0
        block_target = ""
    } else {
        in_block = 1
        block_target = ""    # "skip" mode
    }
    next
}

in_block && block_target != "" {
    if (substr(block_target, 1, 5) == "file:") {
        # Stash root-block lines for later expansion.
        name = substr(block_target, 6)
        root_lines[name, ++root_n[name]] = $0
    } else {
        name = substr(block_target, 7)
        chunk_lines[name, ++chunk_n[name]] = $0
    }
    next
}

END {
    for (name in seen_file) {
        out = file_path[name]
        n = root_n[name]
        for (i = 1; i <= n; i++) {
            emit_line(out, root_lines[name, i], "")
        }
    }
}

# Emit a line to `out`, expanding <<chunk-ref>> references recursively.
# `indent` is the accumulated leading whitespace from outer references.
function emit_line(out, line, indent,    pre, name, j, cn) {
    # Detect <<name>> reference, possibly indented.
    if (match(line, /^[[:space:]]*<<[A-Za-z0-9_.-]+>>[[:space:]]*$/)) {
        pre = line
        sub(/<<.*/, "", pre)            # leading whitespace before <<
        if (match(line, /<<[A-Za-z0-9_.-]+>>/)) {
            name = substr(line, RSTART+2, RLENGTH-4)
        }
        cn = chunk_n[name]
        if (cn == 0) {
            print "tangle.awk: undefined chunk <<" name ">>" > "/dev/stderr"
            exit 1
        }
        for (j = 1; j <= cn; j++) {
            emit_line(out, chunk_lines[name, j], indent pre)
        }
        return
    }
    print indent line >> out
}
