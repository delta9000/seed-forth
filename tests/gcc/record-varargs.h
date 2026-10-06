/* Records passed by value to variadic and unprototyped functions.
   No member is floating except the one X87 record (struct X). */
struct S1 { int a, b; };                 /* one INTEGER eightbyte */
struct S2 { long l; char c; };           /* two INTEGER eightbytes */
struct S3 { char c[3]; };                /* three bytes, one eightbyte */
struct Big { long x, y, z; };            /* MEMORY */
union U { long l; char c[12]; };         /* two INTEGER eightbytes */
struct X { long double v; };             /* X87: always on the stack */

long knr_sum();
struct S2 knr_make();
struct Big empty_make();
long proto_sum(struct S1 a, long x, struct Big b);
long vsum(const char *format, ...);
struct Big vbig(int n, ...);
long vnamed(struct S2 s, int n, ...);
long vlist(const char *format, ...);
