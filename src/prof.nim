import std/nimprof

import cbuf

const SIZE = 102
const N = 2500

var data = newSeqOfCap[byte](SIZE)

for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

echo "profiler"

setSamplingFrequency(1)
enableProfiling()

proc main =
  for _ in 0..N:
    var data2 = initBuf()
    for _ in 0 ..< N:
      data2.append(data.toOpenArray(0, data.len - 1))

main()
