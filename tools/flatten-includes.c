/* Pinned pnut-kit include flattener, built with stage-1 sf-pnut64.
 * Usage: flatten-includes INPUT > OUTPUT
 *
 * Reproduce process-includes.sh's exact, column-zero include syntax, global
 * system-header suppression (BRE substring matching, '.' is a wildcard),
 * recursive quoted includes, and omission of a final unterminated line.
 * This recipe subset accepts system names [A-Za-z0-9_][A-Za-z0-9_./-]* and
 * quoted basenames only. Other recognized include names fail closed.
 * Not a C preprocessor: conditionals are copied and not evaluated.
 * Input errors emit no stdout; the caller must discard output on write error.
 */
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

#define MAX_FILE 1048576
#define MAX_TOTAL 16777216
#define MAX_OUTPUT 4194304
#define MAX_PATH 4096
#define MAX_LINE 65536
#define MAX_HEADERS 65536
#define MAX_DEPTH 32

char *output;
int output_size;
char *headers;
int headers_size;
char *active[MAX_DEPTH];
int total_size;

int length(char *text) {
    int size = 0;
    while (text[size] != 0) size = size + 1;
    return size;
}

void die(char *message) {
    write(2, "flatten-includes: ", 18);
    write(2, message, length(message));
    write(2, "\n", 1);
    exit(1);
}

int equal(char *a, char *b) {
    int pos = 0;
    while (a[pos] != 0 && a[pos] == b[pos]) pos = pos + 1;
    return a[pos] == b[pos];
}

int prefix(char *text, int size, char *start) {
    int pos = 0;
    while (start[pos] != 0) {
        if (pos >= size || text[pos] != start[pos]) return 0;
        pos = pos + 1;
    }
    return 1;
}

void append(char *bytes, int size) {
    int pos;
    if (size > MAX_OUTPUT - output_size) die("output limit exceeded");
    for (pos = 0; pos < size; pos = pos + 1) output[output_size + pos] = bytes[pos];
    output_size = output_size + size;
}

int ordinary(int ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
           (ch >= '0' && ch <= '9') || ch == '_';
}

void check_name(char *name, int size, int system) {
    int pos;
    int ch;
    if (size == 0 || size >= MAX_PATH || !ordinary(name[0])) die("unsupported include name");
    for (pos = 0; pos < size; pos = pos + 1) {
        ch = name[pos];
        if (!ordinary(ch) && ch != '.' && ch != '-' && !(system && ch == '/'))
            die("unsupported include name");
    }
}

int seen_header(char *name, int size) {
    int start;
    int pos;
    /* The shell uses grep, not fixed-string or whole-header comparison. */
    for (start = 0; start <= headers_size - size; start = start + 1) {
        pos = 0;
        while (pos < size && (name[pos] == '.' || name[pos] == headers[start + pos]))
            pos = pos + 1;
        if (pos == size) return 1;
    }
    if (size + 1 > MAX_HEADERS - headers_size) die("system-header limit exceeded");
    headers[headers_size] = ' ';
    headers_size = headers_size + 1;
    for (pos = 0; pos < size; pos = pos + 1) headers[headers_size + pos] = name[pos];
    headers_size = headers_size + size;
    return 0;
}

char *include_path(char *parent, char *name, int size) {
    int pos;
    int base = 0;
    char *path;
    for (pos = 0; parent[pos] != 0; pos = pos + 1) {
        if (parent[pos] == '/') base = pos + 1;
    }
    if (base + size >= MAX_PATH) die("include path limit exceeded");
    path = malloc(base + size + 1);
    if (path == 0) die("allocation failed");
    for (pos = 0; pos < base; pos = pos + 1) path[pos] = parent[pos];
    for (pos = 0; pos < size; pos = pos + 1) path[base + pos] = name[pos];
    path[base + size] = 0;
    return path;
}

void process(char *path, int depth) {
    int fd;
    int size = 0;
    int count;
    int pos;
    int start;
    int line_size;
    char extra;
    char *bytes;
    char *child;
    if (depth >= MAX_DEPTH) die("include depth limit exceeded");
    for (pos = 0; pos < depth; pos = pos + 1) {
        if (equal(path, active[pos])) die("include cycle");
    }
    active[depth] = path;
    fd = open(path, 0, 0);
    if (fd < 0) die("cannot open input");
    bytes = malloc(MAX_FILE + 1);
    if (bytes == 0) die("allocation failed");
    while (size < MAX_FILE) {
        count = read(fd, bytes + size, MAX_FILE - size);
        if (count < 0 || count > MAX_FILE - size) die("input read failed");
        if (count == 0) break;
        size = size + count;
    }
    if (size == MAX_FILE && read(fd, &extra, 1) != 0) die("input limit exceeded or read failed");
    if (close(fd) != 0) die("input close failed");
    if (size > MAX_TOTAL - total_size) die("total input limit exceeded");
    total_size = total_size + size;
    start = 0;
    for (pos = 0; pos < size; pos = pos + 1) {
        if (bytes[pos] == 0) die("NUL input is unsupported");
        if (pos - start >= MAX_LINE) die("line limit exceeded");
        if (bytes[pos] == '\n') {
            line_size = pos - start;
            if (prefix(bytes + start, line_size, "#include <") && bytes[pos - 1] == '>') {
                check_name(bytes + start + 10, line_size - 11, 1);
                if (!seen_header(bytes + start + 10, line_size - 11))
                    append(bytes + start, line_size + 1);
            } else if (prefix(bytes + start, line_size, "#include \"") && bytes[pos - 1] == '"') {
                check_name(bytes + start + 10, line_size - 11, 0);
                child = include_path(path, bytes + start + 10, line_size - 11);
                process(child, depth + 1);
                free(child);
            } else {
                append(bytes + start, line_size + 1);
            }
            start = pos + 1;
        }
    }
    free(bytes);
    active[depth] = 0;
}

int main(int argc, char **argv) {
    int done;
    int count;
    if (argc != 2) die("usage: flatten-includes INPUT");
    if (length(argv[1]) == 0 || length(argv[1]) >= MAX_PATH) die("input path limit exceeded");
    output = malloc(MAX_OUTPUT);
    headers = malloc(MAX_HEADERS);
    if (output == 0 || headers == 0) die("allocation failed");
    process(argv[1], 0);
    done = 0;
    while (done < output_size) {
        count = write(1, output + done, output_size - done);
        if (count <= 0 || count > output_size - done) die("output write failed");
        done = done + count;
    }
    free(output);
    free(headers);
    return 0;
}
