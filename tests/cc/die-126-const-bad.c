/* Error 126: a case label that isn't a constant expression. */
int main() {
  switch (1) {
    case 1 + : return 0;
  }
  return 1;
}
