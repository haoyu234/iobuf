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

proc main() =
  for _ in 0 .. N:
    var buf: IOBuf
    buf.initBuf()

    for _ in 0 ..< N:
      # buf.writeZeroCopy(data.toOpenArray(0, data.len - 1))
      for b in data:
        buf.writeCopy(b)

main()
