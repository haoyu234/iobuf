import std/unittest

import cbuf

const SIZE = 6000

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

let slice = data.slice()

test "append":

  const N = 3
  var buf = initBuf()

  for _ in 0 ..< N:
    buf.append(slice)

  var num = 0

  for sliceBuf in buf:
    let slice = sliceBuf.slice()
    inc num, slice.len

  check buf.len == num
  check N * SIZE == num

test "slice":

  const N = 3
  var buf = initBuf()
  var data2 = newSeq[byte]()

  for _ in 0 ..< N:
    data2.add(slice.toOpenArray())
    buf.append(slice)

  let buf2 = buf[0 ..< data2.len]
  let data3 = buf2.toSeq()

  check buf2.len == data2.len
  check data3 == data2
