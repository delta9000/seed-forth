# Error 60: more than 4096 symbols.  Every enumerator is one; 32 symbols
# are built in, so the 4,065th enumerator (E4064) is one too many.
echo "enum big {"
awk 'BEGIN { for (i = 0; i < 4200; i++) print "  E" i "," }'
echo "  LAST"
echo "};"
echo "int main() { return 0; }"
