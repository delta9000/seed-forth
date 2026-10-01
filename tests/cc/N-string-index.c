/* A string literal is a char*: "abc"[1] loads the byte 'b' (98), not the
   eight bytes starting there. */
int main() {
  return "abc"[1];
}
