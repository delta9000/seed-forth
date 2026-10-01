# ladder/finish.sh: the last step under K1.  Write the results to the output
# disk (/dev/hdb) with the chain's tar, then hand the machine to the Linux
# kernel stage12.sh built (K1's reboot(KEXEC) loads /boot/bzImage).
set -eu
export PATH=/build-out/g64/g10/bin:/build-out/g64/bu2/bin:/usr/bin:/bin
cd /
tar -cf /dev/hdb build-out/linux build-out/s10-logs build-out/s12-logs build-out/g64/logs
echo "finish: results written to hdb"
mkdir -p /boot
cp /build-out/linux/bzImage /boot/bzImage
printf 'console=ttyS0 panic=-1' > /boot/cmdline
gcc -static -O2 -o /build-out/kexec /ladder/kexec.c
echo "finish: K1 hands the machine to the Linux kernel it built"
exec /build-out/kexec
