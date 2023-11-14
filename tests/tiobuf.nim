import std/unittest
import std/sequtils

import cbuf/iobuf
import cbuf/slice2
import cbuf/intern/chunk
import cbuf/intern/deprecated

const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

let slice = data.slice()

test "append":

  var buf = initBuf()

  let num = DEFAULT_CHUNK_SIZE div SIZE
  for _ in 0 ..< num:
    buf.appendCopy(slice)
    buf.appendZeroCopy(data[0].getAddr, data.len)
    buf.appendCopy(data[0].getAddr, data.len)

  assert buf.len == data.len * num * 3

  let data2 = buf.toSeq
  for idx in 0 ..< num * 3:
    let start = idx * data.len
    let s = slice(data2, start, data.len)
    check data == s

test "consumeLeft Empty":

  var buf = initBuf()
  var data2: array[SIZE * 2, byte]

  # peek empty buf
  check buf.peekLeftCopy(data2[0].getAddr, 0) == 0
  check buf.peekLeftCopy(data2[0].getAddr, SIZE + 1) == 0
  check buf.peekLeftCopy(data2[0].getAddr, -1) == 0

  # read empty buf
  check buf.readLeftCopy(data2[0].getAddr, 0) == 0
  check buf.readLeftCopy(data2[0].getAddr, SIZE + 1) == 0
  check buf.readLeftCopy(data2[0].getAddr, -1) == 0

test "consumeRight Empty":

  var buf = initBuf()
  var data2: array[SIZE * 2, byte]

  # peek empty buf
  check buf.peekRightCopy(data2[0].getAddr, 0) == 0
  check buf.peekRightCopy(data2[0].getAddr, SIZE + 1) == 0
  check buf.peekRightCopy(data2[0].getAddr, -1) == 0

  # read empty buf
  check buf.readRightCopy(data2[0].getAddr, 0) == 0
  check buf.readRightCopy(data2[0].getAddr, SIZE + 1) == 0
  check buf.readRightCopy(data2[0].getAddr, -1) == 0

test "consumeLeft":

  var buf = initBuf()
  let data2: array[2, byte] = [byte(1), 2]
  var data3: array[20, byte]
  var data4 = newSeq[byte]()

  template append() =
    buf.appendZeroCopy(data2.getAddr, data2.len)
    data4.add(toOpenArray(cast[ptr UncheckedArray[byte]](data2.getAddr), 0,
        data2.len - 1))

  template checkPeekLeft(size) =
    zeroMem(data3[0].getAddr, data3.len)
    check buf.peekLeftCopy(data3.getAddr, size) == size

    let s = 0 ..< size
    check data4[s] == data3[s]
    check data4 == buf.toSeq

  template checkReadLeft(size) =
    zeroMem(data3[0].getAddr, data3.len)
    check buf.readLeftCopy(data3.getAddr, size) == size

    let s = 0 ..< size
    check data4[s] == data3[s]
    data4.delete(s)
    check data4 == buf.toSeq

  template checkOp(size) =
    checkPeekLeft(size)
    checkReadLeft(size)

  for _ in 0..12:
    append()

  checkOp(1)
  checkOp(data2.len)
  checkOp(data2.len - 1)
  checkOp(data2.len + 1)
  checkOp(data2.len)
  checkOp(data2.len * 2 - 1)
  checkOp(data2.len * 2)
  checkOp(data2.len)
  checkOp(data2.len * 2 + 1)
  checkOp(data2.len)
  checkOp(1)

  check data4.len == 0
  check buf.len == 0

test "consumeRight":

  var buf = initBuf()
  let data2: array[2, byte] = [byte(1), 2]
  var data3: array[20, byte]
  var data4 = newSeq[byte]()

  template append() =
    buf.appendZeroCopy(data2.getAddr, data2.len)
    data4.add(toOpenArray(cast[ptr UncheckedArray[byte]](data2.getAddr), 0,
        data2.len - 1))

  template checkPeekRight(size) =
    zeroMem(data3[0].getAddr, data3.len)
    check buf.peekRightCopy(data3.getAddr, size) == size

    let s = (data4.len - size) ..< data4.len
    check data4[s] == data3[0 ..< size]
    check data4 == buf.toSeq

  template checkReadRight(size) =
    zeroMem(data3[0].getAddr, data3.len)
    check buf.readRightCopy(data3.getAddr, size) == size

    let s = (data4.len - size) ..< data4.len
    check data4[s] == data3[0 ..< size]
    data4.delete((data4.len - size) ..< data4.len)
    check data4 == buf.toSeq

  template checkOp(size) =
    checkPeekRight(size)
    checkReadRight(size)

  for _ in 0..12:
    append()

  checkOp(1)
  checkOp(data2.len)
  checkOp(data2.len - 1)
  checkOp(data2.len + 1)
  checkOp(data2.len)
  checkOp(data2.len * 2 - 1)
  checkOp(data2.len * 2)
  checkOp(data2.len)
  checkOp(data2.len * 2 + 1)
  checkOp(data2.len)
  checkOp(1)

  check data4.len == 0
  check buf.len == 0
