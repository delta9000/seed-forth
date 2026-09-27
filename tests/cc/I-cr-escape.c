/* '\r' is carriage return, 13.  Character literals decoded their escapes
   with their own table, which lacked \r, so '\r' compiled to 'r' (114);
   string literals had it.  Both now share cc-decode-escape.  Exit 13 only
   if the literal and the string agree on 13. */
int main() {
  char* s = "\r\n";
  if (s[0] != 13) return 1;
  if (s[1] != 10) return 2;
  if ('\n' != 10) return 3;
  return '\r';
}
