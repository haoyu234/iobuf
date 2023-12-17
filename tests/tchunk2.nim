import std/unittest

import iobuf/iobuf
import iobuf/intern/iobuf

test "releaseChunk":
  var buf: IOBuf

  var c1 = InternalIOBuf(buf).allocChunk
  var c2 = InternalIOBuf(buf).allocChunk

  InternalIOBuf(buf).releaseChunk(c1)
  InternalIOBuf(buf).releaseChunk(c2)

  var c3 = InternalIOBuf(buf).allocChunk
  var c4 = InternalIOBuf(buf).allocChunk

  assert c3 == c2
  assert c4 == c1
