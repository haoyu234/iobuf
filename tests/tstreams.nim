import std/unittest
import std/streams

import iobuf/iobuf
import iobuf/streams
import iobuf/intern/deprecated

const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

test "read Stream":

  var buf = initIOBuf()
  buf.appendZeroCopy(data)

  var data2 = byte(0)
  var reader = newIOBufStream(buf.getAddr)

  var idx = byte(0)
  while not reader.atEnd:
    reader.read(data2)

    check data2 == idx
    inc idx

  check buf.len == 0

test "write Stream":

  var buf = initIOBuf()
  var writer = newIOBufStream(buf.getAddr)

  for data2 in data:
    writer.write(data2)

  check buf.len == data.len
  check buf.toSeq() == data
