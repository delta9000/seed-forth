/* Error 46: a macro call with more than 16 arguments. */
#define F(a) a
int main() {
  return F(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17);
}
