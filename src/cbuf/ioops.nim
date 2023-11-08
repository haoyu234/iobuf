import iobuf
import slice2

import intern/tls
import intern/chunk
import intern/deprecated

const MAX_IOVEC_NUM = 64

when defined(linux):
  import std/posix

  proc readv*(fd: cint, buf: var IOBuf, maxSize: int): int =
    var num = 0
    var size = 0

    var vecBuf: array[MAX_IOVEC_NUM, IOVec]
    var vecChunk: array[MAX_IOVEC_NUM, Chunk]

    while num < MAX_IOVEC_NUM:
      if size >= maxSize:
        break

      let left = maxSize - size
      var chunk = if size >= DEFAULT_LARGE_CHUNK_SIZE and left >= DEFAULT_LARGE_CHUNK_SIZE:
        newChunk(DEFAULT_LARGE_CHUNK_SIZE)
      else:
        buf.allocChunk()

      let len = min(chunk.leftSpace(), left)
      inc size, len

      vecBuf[num].iov_base = chunk.writeAddr
      vecBuf[num].iov_len = csize_t(len)
      vecChunk[num] = move chunk

      inc num

    if num == 1:
      result = read(cint(fd), vecBuf[0].iov_base, int(vecBuf[0].iov_len))
    else:
      result = readv(cint(fd), vecBuf[0].getAddr, cint(num))

    if result <= 0:
      for idx in 0 ..< num:
        releaseTlsChunk(vecChunk[idx])
      return

    size = result

    template appendBuf(idx, extendBuf) =
      block appendBufScope:
        if size > 0:
          let len = min(int(vecBuf[idx].iov_len), size)
          dec size, len

          let oldLen = vecChunk[idx].len
          vecChunk[idx].extendLen(len)

          when extendBuf:
            if buf.extendAdjacencyRegionRight(vecBuf[idx].iov_base, len):
              break appendBufScope

          buf.enqueueZeroCopyRight(vecChunk[idx], oldLen, len)
      buf.releaseChunk(move vecChunk[idx])

    appendBuf(0, true)

    for idx in 1 ..< num:
      appendBuf(idx, false)

  proc writev*(fd: cint, buf: var IOBuf, maxSize: int): int =
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
      result = writev(cint(fd), vecBuf[0].getAddr, cint(num))

    if result <= 0:
      return

    size = result

    for idx in 0 ..< num:
      let dataLen = int(vecBuf[idx].iov_len)

      if size < dataLen:
        buf.internalDequeueAdjustLeft(idx, size, result)
        break
      elif size == dataLen:
        buf.internalDequeueAdjustLeft(idx + 1, 0, result)
        break

      dec size, dataLen
