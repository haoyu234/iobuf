import std/streams

import iobuf
import intern/deprecated

type
  ReaderStream* = ref ReaderStreamObj
  ReaderStreamObj = object of StreamObj
    buf: ptr IOBuf

  WriterStream* = ref WriterStreamObj
  WriterStreamObj = object of StreamObj
    buf: ptr IOBuf

proc closeImpl(s: Stream) =
  var readerStream = ReaderStream(s)
  reset(readerStream.buf)

proc atEndImpl(s: Stream): bool =
  var readerStream = ReaderStream(s)
  readerStream.buf[].len == 0

proc readDataStrImpl(s: Stream, buffer: var string, slice: Slice[int]): int =
  var readerStream = ReaderStream(s)

  when declared(prepareMutation):
    prepareMutation(buffer) # buffer might potentially be a CoW literal with ARC

  result = min(slice.b + 1 - slice.a, readerStream.buf[].len)
  if result > 0:
    readerStream.buf[].readLeftCopy(buffer[slice.a].getAddr, result)
  else:
    result = 0

proc readDataImpl(s: Stream, buffer: pointer, bufLen: int): int =
  var readerStream = ReaderStream(s)
  result = min(bufLen, readerStream.buf[].len)

  if result > 0:
    readerStream.buf[].readLeftCopy(buffer, result)
  else:
    result = 0

proc peekDataImpl(s: Stream, buffer: pointer, bufLen: int): int =
  var readerStream = ReaderStream(s)
  result = min(bufLen, readerStream.buf[].len)

  if result > 0:
    readerStream.buf[].peekLeftCopy(buffer, result)
  else:
    result = 0

proc writeDataImpl(s: Stream, buffer: pointer, bufLen: int) =
  var writerStream = WriterStream(s)
  if bufLen <= 0:
    return

  writerStream.buf[].appendCopy(buffer, bufLen)

proc readerStream*(buf: ptr IOBuf): ReaderStream {.inline.} =
  new (result)

  result.buf = buf
  result.closeImpl = closeImpl
  result.atEndImpl = atEndImpl
  result.readDataStrImpl = readDataStrImpl
  result.readDataImpl = readDataImpl
  result.peekDataImpl = peekDataImpl

proc writerStream*(buf: ptr IOBuf): WriterStream {.inline.} =
  new (result)

  result.buf = buf
  result.closeImpl = closeImpl
  result.writeDataImpl = writeDataImpl
