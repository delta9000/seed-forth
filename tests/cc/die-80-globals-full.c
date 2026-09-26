/* Error 80: file-scope variables fill the 4,096-byte globals buffer.
   512 eight-byte cells fill it exactly; one more global is too many. */
int table[512];
int one_too_many;
int main() {
  return 0;
}
