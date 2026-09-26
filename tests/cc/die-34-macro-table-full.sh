# Error 34: more than 256 macros.  7 are built in, so the 250th #define
# is one too many.
i=1
while [ $i -le 260 ]; do
  echo "#define M$i $i"
  i=$((i + 1))
done
echo "int main() { return 0; }"
