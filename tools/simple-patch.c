/* Exact byte replacement for the amd64 bootstrap, built by stage-3 pnut.
 *
 * replace INPUT BEFORE AFTER OUTPUT: BEFORE must occur exactly once and must
 * be nonempty. copy INPUT OUTPUT: copy bytes, including an empty input.
 * OUTPUT must not exist. Inputs are never opened for writing. The caller
 * verifies OUTPUT's hash before promoting it with a same-directory rename.
 * This is deliberately not a unified-diff parser or a general GNU patch clone.
 */
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* All bootstrap inputs are much smaller. Bound allocations and arithmetic. */
#define MAX_INPUT 16777216

char *output_path;
int output_fd = -1;
int file_size;

void fail(char *message) {
    if (output_fd >= 0) close(output_fd);
    /* Only set after this process successfully creates OUTPUT exclusively. */
    if (output_path != 0) unlink(output_path);
    fprintf(stderr, "simple-patch: %s\n", message);
    exit(1);
}

char *read_all(char *path) {
    int fd;
    int size;
    int done;
    int count;
    char extra;
    char *data;
    fd = open(path, O_RDONLY);
    if (fd < 0) fail("cannot open input");
    size = lseek(fd, 0, SEEK_END);
    if (size < 0 || size > MAX_INPUT) fail("input size unavailable or over limit");
    if (lseek(fd, 0, SEEK_SET) != 0) fail("cannot rewind input");
    data = malloc(size + 1);
    if (data == 0) fail("cannot allocate input");
    done = 0;
    while (done < size) {
        count = read(fd, data + done, size - done);
        if (count <= 0 || count > size - done) fail("input read failed or shortened");
        done = done + count;
    }
    if (read(fd, &extra, 1) != 0) fail("input read failed or grew");
    if (close(fd) != 0) fail("input close failed");
    file_size = size;
    return data;
}

void write_all(char *data, int size) {
    int done;
    int count;
    done = 0;
    while (done < size) {
        count = write(output_fd, data + done, size - done);
        if (count <= 0 || count > size - done) fail("output write failed");
        done = done + count;
    }
}

void create_output(char *path) {
    output_fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (output_fd < 0) fail("cannot create a new output");
    output_path = path;
}

void finish_output(void) {
    int result;
    result = close(output_fd);
    output_fd = -1;
    if (result != 0) fail("output close failed");
    output_path = 0;
}

int main(int argc, char **argv) {
    char *input;
    char *before;
    char *after;
    int input_size;
    int before_size;
    int after_size;
    int pos;
    int match;
    if (argc == 4 && strcmp(argv[1], "copy") == 0) {
        input = read_all(argv[2]);
        input_size = file_size;
        create_output(argv[3]);
        write_all(input, input_size);
        finish_output();
        free(input);
        return 0;
    }
    if (argc != 6 || strcmp(argv[1], "replace") != 0) {
        fprintf(stderr, "Usage: simple-patch replace INPUT BEFORE AFTER OUTPUT\n");
        fprintf(stderr, "       simple-patch copy INPUT OUTPUT\n");
        return 1;
    }
    input = read_all(argv[2]);
    input_size = file_size;
    before = read_all(argv[3]);
    before_size = file_size;
    after = read_all(argv[4]);
    after_size = file_size;
    if (before_size == 0) fail("empty before pattern");
    match = -1;
    pos = 0;
    while (pos <= input_size - before_size) {
        if (memcmp(input + pos, before, before_size) == 0) {
            if (match >= 0) fail("ambiguous before pattern");
            match = pos;
        }
        pos = pos + 1;
    }
    if (match < 0) fail("before pattern not found");
    if (input_size - before_size + after_size > MAX_INPUT) fail("output over limit");
    create_output(argv[5]);
    write_all(input, match);
    write_all(after, after_size);
    write_all(input + match + before_size, input_size - match - before_size);
    finish_output();
    free(input);
    free(before);
    free(after);
    return 0;
}
