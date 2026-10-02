void exit(int status);
long write(int fd, const void *data, unsigned long count);
int main(void) {
    write(1, "native-exit-ok\n", 15);
    exit(37);
    write(1, "unreachable\n", 12);
    return 99;
}
