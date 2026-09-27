/* Error 82: global arrays fill the 256 MiB bss.  40,000,000 eight-byte
   elements are 320 MB. */
int huge[40000000];
int main() {
  return 0;
}
