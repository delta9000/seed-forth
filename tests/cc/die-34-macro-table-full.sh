# Error 34: more than 1,024 macros.  11 are built in, so the 1,014th
# #define is one too many.
i=1
while [ $i -le 1100 ]; do
  echo "#define M$i $i"
  i=$((i + 1))
done
echo "int main() { return 0; }"
