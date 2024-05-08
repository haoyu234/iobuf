import std/unittest

import iobuf/iobuf
import iobuf/intern/dequebuf

test "releaseChunk":
  var buf: IOBuf

  var c1 = DequeBuf(buf).allocChunk
  var c2 = DequeBuf(buf).allocChunk

  DequeBuf(buf).releaseChunk(c1)
  DequeBuf(buf).releaseChunk(c2)

  var c3 = DequeBuf(buf).allocChunk
  var c4 = DequeBuf(buf).allocChunk

  assert c3 == c2
  assert c4 == c1
