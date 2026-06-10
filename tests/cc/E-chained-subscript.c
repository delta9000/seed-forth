/* Chained subscript on an array of char pointers.  `v[i]` (the IDENT-`[`
   fast path) loads the i'th char* element, but it never recorded the
   element's type, so the second `[j]` fell back to qword stride/deref and
   read the wrong bytes.  v[1] points at s1, and s1[1] = 91, so v[1][1] must
   read back the single byte 91.  The buggy qword deref returns 0. */
char s0[4];
char s1[4];
char* v[2];
int main() {
  v[0] = s0;
  v[1] = s1;
  s1[0] = 7;
  s1[1] = 91;
  s1[2] = 13;
  return v[1][1];
}
