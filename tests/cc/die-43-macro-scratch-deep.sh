# Error 43: the preprocessor's 2 MiB scratch area runs out.  Each macro
# call nested in another call's argument holds a 64 KiB temporary buffer
# while it is expanded, so 40 nested calls need more than 2 MiB.
echo "#define ID(x) x"
printf 'int main() { return '
i=0; while [ $i -lt 40 ]; do printf 'ID('; i=$((i + 1)); done
printf '0'
i=0; while [ $i -lt 40 ]; do printf ')'; i=$((i + 1)); done
echo '; }'
