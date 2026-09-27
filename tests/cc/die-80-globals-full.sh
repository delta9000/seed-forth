# Error 80: file-scope scalars fill the 64 KiB data area.  A struct value
# of 16 ints is 128 bytes, so 512 of them fill it exactly and the 513th is
# one too many.  (Arrays go to the bss instead: die-82.)
echo "struct s { int f0; int f1; int f2; int f3; int f4; int f5; int f6; int f7;"
echo "           int f8; int f9; int fa; int fb; int fc; int fd; int fe; int ff; };"
awk 'BEGIN { for (i = 0; i < 513; i++) print "struct s g" i ";" }'
echo "int main() { return 0; }"
