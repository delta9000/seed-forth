# Error 21: the code fills the 1 MiB output buffer (cc-out-buf).  Each
# `x = x + 1;` compiles to a few dozen bytes; 40,000 of them are too many.
echo "int main() {"
echo "  int x;"
echo "  x = 0;"
awk 'BEGIN { for (i = 0; i < 40000; i++) print "  x = x + 1;" }'
echo "  return x;"
echo "}"
