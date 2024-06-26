import std/unittest

import iobuf/iobuf
import iobuf/binary

import std/streams

const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

test "readSth":
  var buf: IOBuf
  let s = newStringStream()

  s.writeData(data[0].addr, data.len)
  buf.writeZeroCopy(data[0].addr, data.len)

  s.setPosition(0)

  template checkOp(OP) =
    check s.OP == buf.OP

  checkOp readChar
  checkOp readUint8
  checkOp readUint16
  checkOp readUint32
  checkOp readUint64
  checkOp readInt8
  checkOp readInt16
  checkOp readInt32
  checkOp readInt64

test "consumeByte":
  var buf: IOBuf
  let data2: array[2, byte] = [byte(1), 2]

  for _ in 0 ..< 4:
    buf.writeZeroCopy(data2.addr, data2.len)

  check buf.len == 8

  check buf.peekUint8() == data2[0]
  check buf.readUint8() == data2[0]
  check buf.peekUint8() == data2[1]
  check buf.readUint8() == data2[1]
  check buf.peekUint8() == data2[0]
