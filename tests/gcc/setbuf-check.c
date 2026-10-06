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
    static char caller[BUFSIZ];
    if (argc != 3) return 10;
#ifndef DIRECTORY_LIBC
    /* Runtime choice: an invalid stream is rejected with EBADF, no crash. */
    if (strcmp(argv[1], "null-stream") == 0) {
        errno = 0;
        setbuf(NULL, NULL);
        return errno == EBADF ? 0 : 11;
    }
    if (strcmp(argv[1], "closed-stream") == 0) {
        if (fclose(stdin) != 0) return 12;
        errno = 0;
        setbuf(stdin, NULL);
        return errno == EBADF ? 0 : 13;
    }
#endif
    stream = fopen(argv[2], "w+b");
    if (stream == NULL) return 14;
    if (strcmp(argv[1], "buffered") == 0) {
        /* A caller buffer holds output until fflush. */
        memset(caller, 85, sizeof(caller));
        setbuf(stream, caller);
        if (fputs("held in the caller buffer", stream) < 0) return 15;
        reader = fopen(argv[2], "rb");
        if (reader == NULL || fread(bytes, 1, 4, reader) != 0) return 16;
        if (memchr(caller, 'h', sizeof(caller)) == NULL) return 27;
        if (fflush(stream)) return 28;
        clearerr(reader);
        if (fread(bytes, 1, 4, reader) != 4 || memcmp(bytes, "held", 4) != 0) return 29;
        if (fclose(reader) || fclose(stream)) return 30;
        puts("caller buffer contract passed");
        return 0;
    }
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
