extern long host_value;
int host_function(int x);
extern int unused_external;
int tentative[];
int read_tentative(void) { return tentative[2]; }
int tentative[] = {10, 20, 42};
int zeroed[4];
char banner[] = "ab" "c";
char exact[3] = "abc";
char *message = "xy";
unsigned long wrapped = (unsigned int)4294967295U + 1U;
int (*callback)(int) = host_function;
struct Pair { int x; long y; };
struct Pair pair = {7, 40};
long *field_address = &pair.y;
int rows[2][3] = {{1,2,3},{4,5,42}};
int *row_address = &rows[1][2];
static int first(void) { static int value=10; value++; return value; }
static int second(void) { static int value=20; value++; return value; }
int check_storage(void) {
  char local[4]="abc";
  extern long host_value;
  if (host_value != 40 || callback(40) != 42) return 1;
  if (read_tentative()!=42 || zeroed[0]!=0 || zeroed[3]!=0) return 2;
  if (sizeof(banner)!=4 || banner[0]!='a' || banner[3]!=0) return 3;
  if (sizeof(exact)!=3 || exact[2]!='c') return 4;
  if (message[0]!='x' || message[1]!='y' || message[2]!=0) return 5;
  if (wrapped!=0) return 6;
  if (pair.x!=7 || *field_address!=40 || *row_address!=42) return 7;
  if (first()!=11 || second()!=21 || first()!=12 || second()!=22) return 8;
  if (local[0]!='a' || local[2]!='c' || local[3]!=0) return 9;
  host_value=42;
  return 0;
}
