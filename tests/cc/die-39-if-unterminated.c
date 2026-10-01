/* Error 39: an #if still open at the end of the program. */
#ifdef FEATURE
int unused;
int main() {
  return 0;
}
