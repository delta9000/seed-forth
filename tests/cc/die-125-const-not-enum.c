/* Error 125: a constant expression names something that isn't an enum
   constant (here a variable). */
int n;
int table[n];
int main() {
  return 0;
}
