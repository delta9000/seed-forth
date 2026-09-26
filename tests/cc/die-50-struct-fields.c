/* Error 50: a struct with more than the 16 fields a descriptor holds. */
struct wide {
  int f0;
  int f1;
  int f2;
  int f3;
  int f4;
  int f5;
  int f6;
  int f7;
  int f8;
  int f9;
  int f10;
  int f11;
  int f12;
  int f13;
  int f14;
  int f15;
  int f16;
};
int main() { return 0; }
