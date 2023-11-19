import std/unittest
import std/sequtils

import iobuf/iobuf
import iobuf/slice2
import iobuf/intern/chunk
import iobuf/intern/deprecated

const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

let slice = data.slice()

test "append":

  var buf = initIOBuf()

  let num = DEFAULT_CHUNK_SIZE div SIZE
  for _ in 0 ..< num:
    buf.writeCopy(slice)
    buf.writeZeroCopy(data[0].getAddr, data.len)
    buf.writeCopy(data[0].getAddr, data.len)

  assert buf.len == data.len * num * 3

  let data2 = buf.toSeq
  for idx in 0 ..< num * 3:
    let start = idx * data.len
    let s = slice(data2, start, data.len)
    check data == s

test "consumeLeft Empty":

  var buf = initIOBuf()
  var data2: array[SIZE * 2, byte]

  # peek empty buf
  check buf.peekCopy(data2[0].getAddr, 0) == 0
  check buf.peekCopy(data2[0].getAddr, SIZE + 1) == 0
  check buf.peekCopy(data2[0].getAddr, -1) == 0

  # read empty buf
  check buf.readCopy(data2[0].getAddr, 0) == 0
  check buf.readCopy(data2[0].getAddr, SIZE + 1) == 0
  check buf.readCopy(data2[0].getAddr, -1) == 0

test "consumeLeft":

  var buf = initIOBuf()
  let data2: array[2, byte] = [byte(1), 2]
  var data3: array[20, byte]
  var data4 = newSeq[byte]()

  template append() =
    buf.writeZeroCopy(data2.getAddr, data2.len)
    data4.add(toOpenArray(cast[ptr UncheckedArray[byte]](data2.getAddr), 0,
        data2.len - 1))

  template checkPeekLeft(size) =
    zeroMem(data3[0].getAddr, data3.len)
    check buf.peekCopy(data3.getAddr, size) == size

    let s = 0 ..< size
    check data4[s] == data3[s]
    check data4 == buf.toSeq

  template checkReadLeft(size) =
    zeroMem(data3[0].getAddr, data3.len)
    check buf.readCopy(data3.getAddr, size) == size

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
