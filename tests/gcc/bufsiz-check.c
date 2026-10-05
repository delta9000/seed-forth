/* Original seed-forth regression fixture; see LICENSE. */
#include <stdio.h>
#include <string.h>
#if BUFSIZ < 256
#error BUFSIZ must permit at least256 bytes
#endif
int main(int argc, char **argv)
{
    unsigned char output[BUFSIZ];
    unsigned char input[BUFSIZ];
    FILE *stream;
    unsigned int i;
    if (argc != 2) return 1;
    for (i = 0; i < BUFSIZ; i++) output[i] = (unsigned char)i;
    stream = fopen(argv[1],"w");
    if (stream == NULL) return 2;
    if (fwrite(output,1,sizeof(output),stream) != sizeof(output) || fclose(stream)) return 3;
    stream = fopen(argv[1],"r");
    if (stream == NULL) return 4;
    memset(input,0,sizeof(input));
    if (fread(input,1,sizeof(input),stream) != sizeof(input) || memcmp(input,output,sizeof(input))) return 5;
    if (fgetc(stream) != EOF || !feof(stream) || ferror(stream) || fclose(stream)) return 6;
    printf("%u\n",(unsigned int)sizeof(input));
    return 0;
}
