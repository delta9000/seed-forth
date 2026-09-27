# Error 36: the preprocessed source overflows the 2 MiB cc-src-buf.  Each
# #include splices in a 60,000-byte header (one line of blanks); 40 of them
# are 2.4 MB.
{ head -c 59999 /dev/zero | tr '\0' ' '; echo; } > "$CC_DIE_TMP/part.h"
i=0
while [ $i -lt 40 ]; do
  echo "#include \"$CC_DIE_TMP/part.h\""
  i=$((i + 1))
done
echo "int main() { return 0; }"
