/* Compile with the pinned bootstrap portable-libc root and include paths. */
#define PNUT_CC 1
#define PNUT_EXE 1
#define PNUT_EXE_64 1
#define PNUT_X86_64 1
#define PNUT_X86_64_LINUX 1
#define __linux__ 1
#define __x86_64__ 1
#define BOOTSTRAP 1
#define HAVE_LONG_LONG 1
#include "libc.c"

int main(int argc, char **argv) {
    FILE *stream;
    char data[8];
    if (argc != 2) return 1;
    stream = fopen(argv[1], "w");
    if (!stream) return 2;
    if (fwrite("abcdefg", 1, 7, stream) != 7) return 3;
    if (fclose(stream) != 0) return 4;
    stream = fopen(argv[1], "r");
    if (!stream) return 5;
    if (fseek(stream, 3, SEEK_SET) != 3) return 6;
    if (ftell(stream) != 3) return 7;
    if (fread(data, 1, 4, stream) != 4) return 8;
    if (data[0] != 'd' || data[3] != 'g') return 9;
    if (fclose(stream) != 0) return 10;
    if (remove(argv[1]) != 0) return 11;
    if (fopen(argv[1], "r") != NULL) return 12;
    if (fprintf(stdout, "%d:%d:%d:%d:%d:%d:%d:%d\n",
                1, 2, 3, 4, 5, 6, 7, 8) != 16) return 13;
    return 0;
}
