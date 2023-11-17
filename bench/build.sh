nim=nim
# nim=nlvm

echo "use $nim compiler"

$nim -d:release -d:useMalloc c bench
$nim -d:release --profiler:on --stackTrace:on c profiler
