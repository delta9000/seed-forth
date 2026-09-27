# Error 32: an #include'd file fills its 64 KiB include-pool slot.
head -c 65536 /dev/zero | tr '\0' '\n' > "$CC_DIE_TMP/big.h"
echo "#include \"$CC_DIE_TMP/big.h\""
echo "int main() { return 0; }"
