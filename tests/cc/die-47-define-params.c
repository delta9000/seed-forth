/* Error 47: a function-like #define whose parameter list holds something
   other than names and commas before its ')'. */
#define BAD(a, 2) a
int main() {
  return 0;
}
