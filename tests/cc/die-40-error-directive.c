/* Error 40: an #error that is not in a dropped group. */
#if 0
#error "dropped: never reached"
#endif
#error "this configuration is not supported"
int main() {
  return 0;
}
