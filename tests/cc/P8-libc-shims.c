/* The shims emitted only when a program calls them: malloc, open, read,
   write, close, strlen, memcpy, strrchr.  Writes "ok\n" through write and
   reads its own source back through open/read.  Exit 42. */
int main() {
  char* buf = malloc(64);
  char* path = "tests/cc/P8-libc-shims.c";
  int fd;
  int n;
  memcpy(buf, "ok\n", 4);
  if (strlen(buf) != 3) return 1;
  if (write(1, buf, 3) != 3) return 2;
  fd = open(path, 0, 0);
  if (fd < 0) return 3;
  n = read(fd, buf, 2);
  if (n != 2) return 4;
  if (buf[0] != '/' || buf[1] != '*') return 5;
  if (close(fd) != 0) return 6;
  if (open("/nonexistent/x", 0, 0) != -1) return 7;
  if (strrchr(path, '/') != path + 8) return 8;
  if (strrchr(path, 'Q') != 0) return 9;
  return 42;
}
