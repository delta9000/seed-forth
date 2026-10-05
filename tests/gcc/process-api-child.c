/* Forth-built child program exec'd by process-api-check.c. */
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    char buffer[256];
    ssize_t count, i;
    if (argc < 2) return 100;
    if (!strcmp(argv[1], "upper")) {
        /* Copy stdin to stdout in upper case. */
        while ((count = read(0, buffer, sizeof(buffer))) > 0) {
            for (i = 0; i < count; i++)
                if (buffer[i] >= 'a' && buffer[i] <= 'z') buffer[i] = (char)(buffer[i] - 32);
            if (write(1, buffer, (size_t)count) != count) return 101;
        }
        return count < 0 ? 102 : 0;
    }
    if (!strcmp(argv[1], "exit") && argc == 3) return atoi(argv[2]);
    if (!strcmp(argv[1], "signal") && argc == 3) {
        kill(getpid(), atoi(argv[2]));
        return 103;
    }
    if (!strcmp(argv[1], "env") && argc == 3) {
        /* Exit 0 exactly when NAME=value appears in the environment. */
        char *value = getenv(argv[2]);
        return value && !strcmp(value, "seen") ? 0 : 104;
    }
    return 105;
}
