#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    DIR *directory;
    struct dirent *entry;
    int count = 0;
    int cycle;
    if (argc != 2) return 2;
    directory = opendir(argv[1]);
    if (!directory) { printf("open:%d\n", errno); return 3; }
    errno = 71;
    while ((entry = readdir(directory)) != NULL) {
        printf("%s\n", entry->d_name);
        count++;
        if (count > 10000) return 4;
    }
    if (errno != 71) return 5;
    errno = 72;
    if (readdir(directory) != NULL || errno != 72) return 6;
    if (closedir(directory) != 0 || errno != 72) return 7;
    for (cycle = 0; cycle < 200; cycle++) {
        directory = opendir(argv[1]);
        if (!directory) return 8;
        if (!readdir(directory)) return 9;
        if (closedir(directory) != 0) return 10;
    }
    return 0;
}
