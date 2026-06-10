/* g is a 16-byte struct but is allocated only 8 bytes; writing g.b (offset 8)
   clobbers the next global, `sentinel`. Correct -> sentinel stays 7. */
struct P { int a; int b; };
struct P g;
int sentinel;
int main() {
  sentinel = 7;
  g.a = 11;
  g.b = 22;
  return sentinel;
}
