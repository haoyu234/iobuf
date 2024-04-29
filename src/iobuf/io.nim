import ./iobuf
import ./slice2

import ./intern/chunk
import ./intern/region
import ./intern/iobuf

const MAX_IOVEC_NUM = 32

proc releaseManyChunk(
    buf: var InternalIOBuf, vecChunk: var openArray[Chunk]
) {.inline.} =
  var idx = vecChunk.len
  while idx > 0:
    dec idx
    buf.releaseChunk(move vecChunk[idx])

when defined(linux):
  import std/posix

  proc readIntoIOBuf*(fd: cint, buf: var IOBuf, maxSize: int): int =
    assert maxSize > 0

    var num = 0
    var size = 0

    var vecBuf: array[MAX_IOVEC_NUM, IOVec]
    var vecChunk: array[MAX_IOVEC_NUM, Chunk]

    for chunk in InternalIOBuf(buf).allocChunkMany(maxSize):
      let left = maxSize - size

      let len = min(chunk.leftSpace(), left)
      inc size, len

      vecBuf[num].iov_base = chunk.writeAddr
      vecBuf[num].iov_len = csize_t(len)
      vecChunk[num] = chunk

      inc num
      if num >= MAX_IOVEC_NUM:
        break

    if num == 1:
      result = read(cint(fd), vecBuf[0].iov_base, int(vecBuf[0].iov_len))
    else:
      result = readv(cint(fd), vecBuf[0].addr, cint(num))

    if result > 0:
      size = result

      for idx in 0 ..< num:
        if size > 0:
          let len = min(int(vecBuf[idx].iov_len), size)
          dec size, len

          let oldLen = vecChunk[idx].len
          vecChunk[idx].advanceWpos(len)

          var region = initRegion(vecChunk[idx], oldLen, len)
          InternalIOBuf(buf).enqueueRightZeroCopy(move region)

    releaseManyChunk(InternalIOBuf(buf), vecChunk.toOpenArray(0, num - 1))

  proc writeIOBuf*(fd: cint, buf: var IOBuf, maxSize: int): int =
    assert maxSize > 0

    var num = 0
    var size = 0

    var vecBuf: array[MAX_IOVEC_NUM, IOVec]

    for slice in buf.items():
      if size >= maxSize:
        break

      let left = maxSize - size
      let len = min(slice.len, left)
      inc size, len

      vecBuf[num].iov_base = slice.leftAddr
      vecBuf[num].iov_len = csize_t(len)

      inc num
      if num >= MAX_IOVEC_NUM:
        break

    if num == 1:
      result = write(cint(fd), vecBuf[0].iov_base, int(vecBuf[0].iov_len))
    else:
      result = writev(cint(fd), vecBuf[0].addr, cint(num))

    if result > 0:
      InternalIOBuf(buf).dequeueLeft(result)
