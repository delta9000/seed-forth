/* Error 128: a '?' in a constant expression without its ':'. */
enum { A = 1 ? 2 };
int main() {
  return 0;
}
