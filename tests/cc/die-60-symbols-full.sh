# Error 60: more than 4096 symbols.  Every enumerator is one; 23 symbols
# are built in, so the 4,074th enumerator (E4073) is one too many.
echo "enum big {"
awk 'BEGIN { for (i = 0; i < 4200; i++) print "  E" i "," }'
echo "  LAST"
echo "};"
echo "int main() { return 0; }"
