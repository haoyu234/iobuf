import std/nimprof

import ../src/iobuf/iobuf

const SIZE = 102
const N = 250

var data = newSeqOfCap[byte](SIZE)

for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

echo "profiler"

when defined(setSamplingFrequency):
  setSamplingFrequency(1)
enableProfiling()

proc main =
  for _ in 0..N:
    var data2 = initBuf()
    for _ in 0 ..< N:
      # data2.writeZeroCopy(data.toOpenArray(0, data.len - 1))
      for b in data:
        data2.writeCopy(b)

main()
