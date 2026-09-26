# Error 10: the 32 KiB arena is full.  Each struct definition takes one
# 656-byte descriptor from it, so the 50th struct does not fit.
i=1
while [ $i -le 60 ]; do
  echo "struct s$i { int a; };"
  i=$((i + 1))
done
echo "int main() { return 0; }"
