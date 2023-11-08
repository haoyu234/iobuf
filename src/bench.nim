import cbuf
import benchy

const SIZE = 102
const N = 250

var data = newSeqOfCap[byte](SIZE)
var data3 = newSeqOfCap[byte](SIZE * N)

for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

for _ in 0 ..< N:
  data3.add(data)

timeIt "stdSeq":
  var data2 = newSeqOfCap[byte](4096)
  for _ in 0 ..< N:
    data2.add(data)

  keep(data2)

timeIt "buf":
  var data2 = initBuf()
  for _ in 0 ..< N:
    data2.append(data.toOpenArray(0, data.len - 1))

  keep(data2)

timeIt "bufAppendEntire":
  var data2 = initBuf()
  data2.append(data3.toOpenArray(0, data3.len - 1))

  keep(data2)

timeIt "memcpy":
  var data2: array[SIZE * N, byte]
  copyMem(data2[0].addr, data3[0].addr, data3.len)
