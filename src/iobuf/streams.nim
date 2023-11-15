import std/streams

import iobuf
import intern/deprecated

type
  IOBufStream = ref object of StreamObj
    buf: ptr IOBuf

proc closeImpl(s: Stream) =
  var stream = IOBufStream(s)
  reset(stream.buf)

proc atEndImpl(s: Stream): bool =
  var stream = IOBufStream(s)
  stream.buf[].len == 0

proc readDataStrImpl(s: Stream, buffer: var string, slice: Slice[int]): int =
  var stream = IOBufStream(s)

  when declared(prepareMutation):
    prepareMutation(buffer) # buffer might potentially be a CoW literal with ARC

  result = min(slice.b + 1 - slice.a, stream.buf[].len)
  if result > 0:
    result = stream.buf[].readLeftCopy(buffer[slice.a].getAddr, result)
  else:
    result = 0

proc readDataImpl(s: Stream, buffer: pointer, bufLen: int): int =
  var stream = IOBufStream(s)

  if bufLen > 0:
    result = stream.buf[].readLeftCopy(buffer, bufLen)

proc peekDataImpl(s: Stream, buffer: pointer, bufLen: int): int =
  var stream = IOBufStream(s)

  if bufLen > 0:
    result = stream.buf[].peekLeftCopy(buffer, bufLen)

proc writeDataImpl(s: Stream, buffer: pointer, bufLen: int) =
  var writerStream = IOBufStream(s)
  if bufLen <= 0:
    return

  writerStream.buf[].appendCopy(buffer, bufLen)

proc newIOBufStream*(buf: ptr IOBuf): owned IOBufStream {.inline.} =
  result = IOBufStream()
  result.buf = buf
  result.closeImpl = closeImpl
  result.atEndImpl = atEndImpl
  result.readDataStrImpl = readDataStrImpl
  result.readDataImpl = readDataImpl
  result.peekDataImpl = peekDataImpl
  result.writeDataImpl = writeDataImpl
