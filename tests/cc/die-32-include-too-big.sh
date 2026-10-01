# Error 32: an #include'd file fills its 256 KiB include-pool slot.
head -c 262144 /dev/zero | tr '\0' '\n' > "$CC_DIE_TMP/big.h"
echo "#include \"$CC_DIE_TMP/big.h\""
echo "int main() { return 0; }"
