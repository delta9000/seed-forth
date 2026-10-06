/* Original seed-forth implementation; see LICENSE and PROCESS-POSIX.md.
   popen/pclose: a pipe to or from "sh -c COMMAND". */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <paths.h>
#include <errno.h>

struct seed_pipe_stream {
    FILE *stream;
    int descriptor;
    pid_t child;
    struct seed_pipe_stream *next;
};
static struct seed_pipe_stream *seed_pipe_streams;

FILE *popen(const char *command, const char *mode)
{
    struct seed_pipe_stream *record, *other;
    int ends[2], reading, mine, theirs, target, cloexec = 0, index = 1;
    char *arguments[4];
    pid_t child;
    if (mode == NULL || (mode[0] != 'r' && mode[0] != 'w')) {
        errno = EINVAL;
        return NULL;
    }
    /* glibc's "e" suffix keeps the caller's end close-on-exec. */
    while (mode[index]) {
        if (mode[index] != 'e') { errno = EINVAL; return NULL; }
        cloexec = 1;
        index++;
    }
    reading = mode[0] == 'r';
    record = malloc(sizeof(*record));
    if (record == NULL) return NULL;
    if (pipe2(ends, O_CLOEXEC) < 0) {
        free(record);
        return NULL;
    }
    mine = reading ? ends[0] : ends[1];
    theirs = reading ? ends[1] : ends[0];
    target = reading ? STDOUT_FILENO : STDIN_FILENO;
    child = fork();
    if (child == 0) {
        /* POSIX: streams from earlier popen calls are not inherited. */
        for (other = seed_pipe_streams; other; other = other->next)
            close(other->descriptor);
        if (theirs == target) {
            if (fcntl(theirs, F_SETFD, 0) < 0) _exit(127);
        } else if (dup2(theirs, target) < 0) {
            _exit(127);
        }
        arguments[0] = "sh";
        arguments[1] = "-c";
        arguments[2] = (char *)command;
        arguments[3] = NULL;
        execve(_PATH_BSHELL, arguments, environ);
        _exit(127);
    }
    close(theirs);
    if (child < 0) {
        close(mine);
        free(record);
        return NULL;
    }
    if (!cloexec) fcntl(mine, F_SETFD, 0);
    record->stream = fdopen(mine, reading ? "r" : "w");
    if (record->stream == NULL) {
        close(mine);
        while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {
        }
        free(record);
        return NULL;
    }
    record->descriptor = mine;
    record->child = child;
    record->next = seed_pipe_streams;
    seed_pipe_streams = record;
    return record->stream;
}

int pclose(FILE *stream)
{
    struct seed_pipe_stream **link, *record;
    int status;
    pid_t child;
    for (link = &seed_pipe_streams; *link; link = &(*link)->next)
        if ((*link)->stream == stream) break;
    record = *link;
    if (record == NULL) {
        /* Not a popen stream. */
        errno = ECHILD;
        return -1;
    }
    *link = record->next;
    child = record->child;
    free(record);
    fclose(stream);
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return status;
}
