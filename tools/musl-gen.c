/* musl-gen: the two generated headers of musl-1.1.24's build, without sed.
 *
 *   musl-gen alltypes ARCH_IN GENERIC_IN OUT
 *       = sed -f tools/mkalltypes.sed ARCH_IN GENERIC_IN > OUT
 *   musl-gen syscall IN OUT
 *       = cp IN OUT; sed -n -e s/__NR_/SYS_/p < IN >> OUT
 *
 * mkalltypes.sed rewrites three line forms and copies every other line:
 *   TYPEDEF <type> <name>;      (name = the last space-separated word)
 *   STRUCT <name> <body>;       (name = the first word after STRUCT and spaces)
 *   UNION <name> <body>;
 * into a guarded definition followed by an empty line, for example
 *   #if defined(__NEED_<name>) && !defined(__DEFINED_<name>)
 *   typedef <type> <name>;
 *   #define __DEFINED_<name>
 *   #endif
 *
 * Built by tcc-boot2 against portable_libc, like simple-patch.c.
 */
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

char *out;
int out_len;
int out_cap;

void fail(char *msg) {
    fprintf(stderr, "musl-gen: %s\n", msg);
    exit(1);
}

char *read_all(char *path, int *size) {
    int fd;
    int cap;
    int n;
    char *buf;
    fd = open(path, 0, 0);
    if (fd < 0) fail(path);
    cap = 1 << 20;
    buf = malloc(cap);
    *size = 0;
    while (1) {
        if (*size == cap) fail("input too large");
        n = read(fd, buf + *size, cap - *size);
        if (n < 0) fail("read");
        if (n == 0) break;
        *size = *size + n;
    }
    close(fd);
    return buf;
}

void put(char *s, int n) {
    if (out_len + n > out_cap) fail("output too large");
    memcpy(out + out_len, s, n);
    out_len = out_len + n;
}

void puts0(char *s) {
    put(s, strlen(s));
}

void write_out(char *path) {
    int fd;
    int done;
    int n;
    fd = open(path, 577, 420);           /* O_WRONLY|O_CREAT|O_TRUNC, 0644 */
    if (fd < 0) fail(path);
    done = 0;
    while (done < out_len) {
        n = write(fd, out + done, out_len - done);
        if (n <= 0) fail("write");
        done = done + n;
    }
    if (close(fd) != 0) fail("close");
}

int starts(char *s, int n, char *p) {
    int k;
    k = strlen(p);
    return n >= k && memcmp(s, p, k) == 0;
}

/* One guarded definition: kind is "", "struct_" or "union_"; word is the
 * C keyword ("typedef", "struct", "union"); a/an is the text before the
 * name (typedef) or after it (struct, union). */
void guard(char *kind, char *word, char *name, int nn, char *rest, int rn,
           int name_last) {
    puts0("#if defined(__NEED_"); puts0(kind); put(name, nn);
    puts0(") && !defined(__DEFINED_"); puts0(kind); put(name, nn);
    puts0(")\n"); puts0(word); puts0(" ");
    if (name_last) { put(rest, rn); puts0(" "); put(name, nn); }
    else { put(name, nn); puts0(" "); put(rest, rn); }
    puts0(";\n#define __DEFINED_"); puts0(kind); put(name, nn);
    puts0("\n#endif\n\n");
}

void line(char *s, int n) {
    int i;
    int j;
    char *kind;
    char *word;
    if (n >= 1 && s[n - 1] == ';' && starts(s, n, "TYPEDEF ")) {
        i = n - 2;                       /* last word: after the last space */
        while (i >= 8 && s[i] != ' ') i = i - 1;
        if (i >= 8 && s[i] == ' ' && i + 1 < n - 1 + 1) {
            guard("", "typedef", s + i + 1, n - 1 - (i + 1), s + 8, i - 8, 1);
            return;
        }
    }
    kind = 0;
    if (starts(s, n, "STRUCT")) { kind = "struct_"; word = "struct"; i = 6; }
    if (starts(s, n, "UNION")) { kind = "union_"; word = "union"; i = 5; }
    if (kind && n >= 1 && s[n - 1] == ';') {
        if (i < n && s[i] == ' ') {
            while (i < n && s[i] == ' ') i = i + 1;
            j = i;
            while (j < n && s[j] != ' ') j = j + 1;
            if (j < n - 1) {
                guard(kind, word, s + i, j - i, s + j + 1, n - 1 - (j + 1), 0);
                return;
            }
        }
    }
    put(s, n);
    puts0("\n");
}

void alltypes(char *path) {
    char *in;
    int size;
    int a;
    int b;
    in = read_all(path, &size);
    a = 0;
    while (a < size) {
        b = a;
        while (b < size && in[b] != '\n') b = b + 1;
        if (b == size) fail("input does not end in a newline");
        line(in + a, b - a);
        a = b + 1;
    }
}

int main(int argc, char **argv) {
    char *in;
    int size;
    int a;
    int b;
    out_cap = 1 << 20;
    out = malloc(out_cap);
    out_len = 0;
    if (argc == 5 && strcmp(argv[1], "alltypes") == 0) {
        alltypes(argv[2]);
        alltypes(argv[3]);
        write_out(argv[4]);
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "syscall") == 0) {
        in = read_all(argv[2], &size);
        put(in, size);
        a = 0;
        while (a < size) {
            b = a;
            while (b < size && in[b] != '\n') b = b + 1;
            if (b == size) fail("input does not end in a newline");
            /* s/__NR_/SYS_/p: replace the first __NR_ and print */
            for (int i = a; i + 5 <= b; i = i + 1) {
                if (memcmp(in + i, "__NR_", 5) == 0) {
                    put(in + a, i - a);
                    puts0("SYS_");
                    put(in + i + 5, b - (i + 5));
                    puts0("\n");
                    break;
                }
            }
            a = b + 1;
        }
        write_out(argv[3]);
        return 0;
    }
    fprintf(stderr, "usage: musl-gen alltypes ARCH_IN GENERIC_IN OUT\n"
                    "       musl-gen syscall IN OUT\n");
    return 1;
}
