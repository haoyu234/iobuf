import std/streams

import ./iobuf
import ./binary

type IOBufStream* = ref object of StreamObj
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
  result = min(result, stream.buf[].len)
  if result > 0:
    stream.buf[].readCopyInto(buffer[slice.a].addr, result)

proc readDataImpl(s: Stream, buffer: pointer, bufLen: int): int =
  var stream = IOBufStream(s)
  result = min(bufLen, stream.buf[].len)

  if result <= 0:
    return

  if result == 1:
    cast[ptr byte](buffer)[] = byte(stream.buf[].readUint8)
    return

  stream.buf[].readCopyInto(buffer, result)

proc peekDataImpl(s: Stream, buffer: pointer, bufLen: int): int =
  var stream = IOBufStream(s)
  result = min(bufLen, stream.buf[].len)

  if result <= 0:
    return

  if result == 1:
    cast[ptr byte](buffer)[] = byte(stream.buf[].peekUint8)
    return

  stream.buf[].peekCopyInto(buffer, result)

proc writeDataImpl(s: Stream, buffer: pointer, bufLen: int) =
  if bufLen <= 0:
    return

  var writerStream = IOBufStream(s)

  writerStream.buf[].writeCopy(buffer, bufLen)

proc newIOBufStream*(buf: ptr IOBuf): owned IOBufStream {.inline.} =
  result = IOBufStream()
  result.buf = buf
  result.closeImpl = closeImpl
  result.atEndImpl = atEndImpl
  result.readDataStrImpl = readDataStrImpl
  result.readDataImpl = readDataImpl
  result.peekDataImpl = peekDataImpl
  result.writeDataImpl = writeDataImpl
