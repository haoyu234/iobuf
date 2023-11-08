echo -e "\n# dd if=/dev/zero of=/dev/null bs=100000000 count=1 -----------"
time dd if=/dev/zero of=/dev/null bs=100000000 count=1

echo -e "\n# bench -------------------------------------------------------"
time ./bench
