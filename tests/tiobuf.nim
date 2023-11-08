import std/unittest

import cbuf
import cbuf/intern/region
import cbuf/intern/deprecated

const SIZE = 100

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

  for region in buf.regions:
    let slice = region.toOpenArray().slice()
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

test "discard":

  var buf = initBuf()
  buf.append(slice.toOpenArray())

  buf.discardLeft(1)

  check buf.len == slice.len - 1
  check buf.toSeq() == slice[1..^1]

  buf.discardRight(1)

  check buf.len == slice.len - 2
  check buf.toSeq() == slice[1..^2]

  let half = slice.len div 2

  buf.discardLeft(half)

  check buf.len == slice.len - half - 2
  check buf.toSeq() == slice[(1 + half)..^2]

  buf.clear()
  buf.append(slice.toOpenArray())

  buf.discardRight(half)

  check buf.len == slice.len - half
  check buf.toSeq() == slice[0..^(half + 1)]

test "readLeft":

  var buf = initBuf()
  var data3: array[SIZE - 2, byte]

  buf.append(slice.toOpenArray())
  check buf.len == slice.len

  buf.peekLeft(data3[0].getAddr, SIZE - 2)
  check buf.len == slice.len
  check data3.slice() == slice[0..^3]

  buf.readLeft(data3[0].getAddr, SIZE - 2)
  check buf.len == 2
  check data3.slice() == slice[0..^3]

  buf.discardLeft(1)
  buf.readLeft(data3[0].getAddr, 1)
  check buf.len == 0
  check data3[0] == slice[slice.len - 1]
