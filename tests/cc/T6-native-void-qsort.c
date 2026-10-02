/* Regress GNU void* byte arithmetic used by portable_libc qsort. The
   qswap/qpartition/qsort bodies match libc64/src/stdlib.c in the direct kit;
   case_cmp matches TinyCC 0.9.27 tccgen.c. A zero pointee stride leaves the
   case table unsorted and makes TinyCC report duplicate switch cases. */
typedef unsigned long size_t;
typedef long long int64_t;
struct case_t { int64_t v1,v2; int sym; };
static int case_cmp(const void *pa, const void *pb)
{
    int64_t a = (*(struct case_t**) pa)->v1;
    int64_t b = (*(struct case_t**) pb)->v1;
    return a < b ? -1 : a > b;
}
void qswap (char *a, char *b, size_t size) {
  while (size > 0) {
    char tmp = *a;
    *a++ = *b;
    *b++ = tmp;
    size--;
  }
}

// Implement Lomuto partition scheme
size_t qpartition(void *base, size_t count, size_t size, int (*compare) (void const *, void const *)) {
  void *p = base + count * size;
  size_t i = 0;
  size_t j;
  for (j = 0; j < count; j++) {
    int c = compare(base + j * size, p);
    if (c <= 0) {
      // j^th element <= pivot => swap it with i^th element
      qswap (base + i * size, base + j * size, size);
      i++;
    }
  }

  int c2 = compare(base + count * size, base + i * size);
  if (c2 < 0)
    qswap (base + i * size, base + count * size, size);
  return i;
}

void qsort (void *base, size_t count, size_t size, int (*compare) (void const *, void const *)) {
  if (count > 1) {
    int p = qpartition(base, count - 1, size, compare);
    qsort (base, p, size, compare);
    qsort (base + p * size, count - p, size, compare);
  }
}

int main(void) {
 struct case_t a[8];
 struct case_t *p[8];
 int i;
 char bytes[16];
 void *cursor = bytes;
 if ((char *)(cursor + 3) != bytes + 3 || (char *)(3 + cursor) != bytes + 3) return 3;
 cursor++; ++cursor; cursor += 3; cursor -= 1;
 if ((char *)cursor != bytes + 4) return 4;
 cursor--; --cursor;
 if (cursor - (void *)bytes != 2) return 5;
 long values[8] = { 45, -1, 25, 2147483648L, -2147483649L, 15, 5, 35 };
 for(i=0;i<8;i++){ a[i].v1=values[i]; a[i].v2=values[i]; p[i]=&a[i]; }
 if(case_cmp(&p[0],&p[1])<=0 || case_cmp(&p[1],&p[0])>=0) return 1;
 qsort(p,8,sizeof(void*),case_cmp);
 for(i=1;i<8;i++) if(p[i-1]->v2>=p[i]->v1) return 2;
 return 0;
}
