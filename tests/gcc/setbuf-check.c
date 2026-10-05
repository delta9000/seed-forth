#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    FILE *stream;
    FILE *reader;
    char bytes[16];
    int descriptor;
#ifndef DIRECTORY_LIBC
    char unsupported[BUFSIZ];
#endif
    if (argc != 3) return 10;
#ifndef DIRECTORY_LIBC
    if (strcmp(argv[1], "null-stream") == 0) { setbuf(NULL, NULL); return 11; }
    if (strcmp(argv[1], "closed-stream") == 0) {
        if (fclose(stdin) != 0) return 12;
        setbuf(stdin, NULL);
        return 13;
    }
#endif
    stream = fopen(argv[2], "w+b");
    if (stream == NULL) return 14;
#ifndef DIRECTORY_LIBC
    if (strcmp(argv[1], "unsupported") == 0) {
        memset(unsupported, 85, sizeof(unsupported));
        setbuf(stream, unsupported);
        fputs("incorrectly continued", stream);
        return 15;
    }
    if (strcmp(argv[1], "bad-buffer") == 0) { setbuf(stream, (char *)1); return 16; }
#endif
    errno = 97;
    setbuf(stream, NULL);
    if (errno != 97 || fileno(stream) < 0 || ftell(stream) != 0) return 17;
    if (ferror(stream) || feof(stream)) return 18;
    if (fwrite("A\0B\377", 1, 4, stream) != 4) return 19;
    reader = fopen(argv[2], "rb");
    if (reader == NULL) return 20;
    setbuf(reader, NULL);
    if (fread(bytes, 1, 4, reader) != 4 || memcmp(bytes, "A\0B\377", 4) != 0) return 21;
    if (fclose(reader) || fclose(stream)) return 22;
    descriptor = open(argv[2], O_RDWR, 0);
    if (descriptor < 0) return 23;
    stream = fdopen(descriptor, "r+");
    if (stream == NULL) return 24;
    errno = 97;
    setbuf(stream, NULL);
    if (errno != 97 || fileno(stream) != descriptor || fgetc(stream) != 'A') return 25;
    if (fclose(stream)) return 26;
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);
    puts("unbuffered stream contract passed");
    return 0;
}
