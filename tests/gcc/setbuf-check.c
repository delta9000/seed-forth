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
    if (strcmp(argv[1], "caller-buffer") == 0) {
        /* Accepted, never read or written: the stream stays unbuffered. */
        size_t index;
        memset(unsupported, 85, sizeof(unsupported));
        errno = 97;
        setbuf(stream, unsupported);
        if (errno != 97) return 15;
        if (fputs("written at once", stream) == EOF) return 16;
        reader = fopen(argv[2], "rb");
        if (reader == NULL || fread(bytes, 1, 15, reader) != 15 || memcmp(bytes, "written at once", 15)) return 17;
        for (index = 0; index < sizeof(unsupported); index++)
            if (unsupported[index] != 85) return 18;
        if (setvbuf(stream, unsupported, _IOFBF, sizeof(unsupported)) != 0) return 19;
        if (setvbuf(stream, NULL, _IOLBF, 0) != 0 || setvbuf(stream, NULL, _IONBF, 0) != 0) return 20;
        errno = 0;
        if (setvbuf(stream, NULL, 7, 0) != EOF || errno != EINVAL) return 21;
        fclose(reader);
        fclose(stream);
        puts("caller buffer accepted");
        return 0;
    }
    if (strcmp(argv[1], "bad-buffer") == 0) {
        setbuf(stream, (char *)1);
        if (fputc('Z', stream) != 'Z') return 22;
        puts("unused buffer pointer accepted");
        return 0;
    }
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
