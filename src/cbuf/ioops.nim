import buf
import intern/tls
import intern/blockbuf

const MAX_BUF_NUM = 64

when defined(linux):
  import std/posix

  proc readIntoBuf*(fd: int, buf: var Buf, maxSize: int): int =
    var num = 0
    var written = 0
    var vecBuf: array[MAX_BUF_NUM, IOVec]
    var vecBlockBuf: array[MAX_BUF_NUM, BlockBuf]

    while num < vecBuf.len:
      if written >= maxSize:
        break

      var blockBuf = buf.allocBlockBuf(occupyBuf = true)

      let len = min(blockBuf.leftSpace(), maxSize - written)
      inc written, len

      vecBuf[num].iov_base = blockBuf.writeAddr
      vecBuf[num].iov_len = csize_t(len)
      vecBlockBuf[num] = move blockBuf

      inc num

    result = readv(cint(fd), vecBuf[0].addr, cint(num))
    if result <= 0:
      for idx in 0 ..< num:
        releaseTlsBlockBuf(vecBlockBuf[idx])
      return

    written = result

    template appendBuf(idx, extendBuf) =
      if written > 0:
        let len = min(int(vecBuf[idx].iov_len), written)
        dec written, len

        var sliceBuf = vecBlockBuf[idx].extendIntoSliceBuf(len)
        buf.append(move sliceBuf, extendBuf)

      buf.releaseBlockBuf(vecBlockBuf[idx])

    appendBuf(0, true)

    for idx in 1 ..< num:
      appendBuf(idx, false)
