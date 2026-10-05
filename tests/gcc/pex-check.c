/* Drives original binutils 2.30 libiberty pex_* through the runtime process API.
   Usage: pex-check CHILD DIRECTORY; CHILD is the Forth-built process-api-child. */
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include "libiberty.h"

static int read_stream(FILE *stream, char *buffer, int size)
{
    int count = 0, byte;
    while (count < size - 1 && (byte = getc(stream)) != EOF) buffer[count++] = (char)byte;
    buffer[count] = '\0';
    return count;
}

int main(int argc, char **argv)
{
    static char printf_name[] = "printf", hello[] = "hello, pex", tr[] = "tr";
    static char lower[] = "a-z", upper[] = "A-Z", sh[] = "sh", dash_c[] = "-c";
    static char exit_script[] = "echo to-file; exit 3", kill_script[] = "kill -TERM $$";
    static char missing[] = "no-such-seed-program", exit_word[] = "exit", fortytwo[] = "42";
    char *arguments[4], buffer[256], output[512];
    struct pex_obj *pex;
    const char *message;
    int error = 0, status[2];
    FILE *stream;
    if (argc != 3) return 1;

    /* Two-stage pipeline found by PATH search; read the last stage's output. */
    pex = pex_init(PEX_USE_PIPES, "pex-check", NULL);
    if (pex == NULL) return 2;
    arguments[0] = printf_name; arguments[1] = hello; arguments[2] = NULL;
    message = pex_run(pex, PEX_SEARCH, printf_name, arguments, NULL, NULL, &error);
    if (message) return 3;
    arguments[0] = tr; arguments[1] = lower; arguments[2] = upper; arguments[3] = NULL;
    message = pex_run(pex, PEX_SEARCH, tr, arguments, NULL, NULL, &error);
    if (message) return 4;
    stream = pex_read_output(pex, 0);
    if (stream == NULL || read_stream(stream, buffer, sizeof(buffer)) != 10
        || strcmp(buffer, "HELLO, PEX")) return 5;
    if (!pex_get_status(pex, 2, status) || status[0] != 0 || status[1] != 0) return 6;
    pex_free(pex);

    /* PEX_LAST with an output file, a nonzero exit status. */
    if (snprintf(output, sizeof(output), "%s/pex-output", argv[2]) < 0) return 7;
    pex = pex_init(0, "pex-check", NULL);
    arguments[0] = sh; arguments[1] = dash_c; arguments[2] = exit_script; arguments[3] = NULL;
    message = pex_run(pex, PEX_LAST | PEX_SEARCH, sh, arguments, output, NULL, &error);
    if (message || !pex_get_status(pex, 1, status)
        || !WIFEXITED(status[0]) || WEXITSTATUS(status[0]) != 3) return 8;
    pex_free(pex);
    stream = fopen(output, "r");
    if (stream == NULL || read_stream(stream, buffer, sizeof(buffer)) != 8
        || strcmp(buffer, "to-file\n") || fclose(stream) || remove(output)) return 9;

    /* A signal death, and an absolute path without search (Forth child). */
    pex = pex_init(0, "pex-check", NULL);
    arguments[2] = kill_script;
    message = pex_run(pex, PEX_LAST | PEX_SEARCH, sh, arguments, NULL, NULL, &error);
    if (message || !pex_get_status(pex, 1, status)
        || !WIFSIGNALED(status[0]) || WTERMSIG(status[0]) != 15) return 10;
    pex_free(pex);
    pex = pex_init(0, "pex-check", NULL);
    arguments[0] = argv[1]; arguments[1] = exit_word; arguments[2] = fortytwo; arguments[3] = NULL;
    message = pex_run(pex, PEX_LAST, argv[1], arguments, NULL, NULL, &error);
    if (message || !pex_get_status(pex, 1, status) || WEXITSTATUS(status[0]) != 42) return 11;
    pex_free(pex);

    /* A missing program: the child reports on stderr and exits 255. */
    pex = pex_init(0, "pex-check", NULL);
    arguments[0] = missing; arguments[1] = NULL;
    message = pex_run(pex, PEX_LAST | PEX_SEARCH, missing, arguments, NULL, NULL, &error);
    if (message || !pex_get_status(pex, 1, status)
        || !WIFEXITED(status[0]) || WEXITSTATUS(status[0]) != 255) return 12;
    pex_free(pex);
    printf("pex contracts passed\n");
    return 0;
}
