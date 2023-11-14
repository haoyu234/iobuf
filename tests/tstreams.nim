import std/unittest
import std/streams

import iobuf/iobuf
import iobuf/streams
import iobuf/intern/deprecated

const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

test "readerStream":

  var buf = initBuf()
  buf.appendZeroCopy(data)

  var data2 = byte(0)
  var reader = readerStream(buf.getAddr)

  var idx = byte(0)
  while not reader.atEnd:
    reader.read(data2)

    check data2 == idx
    inc idx

  check buf.len == 0

test "writerStream":

  var buf = initBuf()
  var writer = writerStream(buf.getAddr)

  for data2 in data:
    writer.write(data2)

  check buf.len == data.len
  check buf.toSeq() == data
