import std/asyncdispatch
import std/asyncnet
import std/oserrors
import std/nativesockets
import std/importutils

import ./iobuf
import ./intern/dequebuf
import ./intern/chunk
import ./io
import ./slice2

proc isDisconnectionError*(lastError: OSErrorCode): bool =
  ## Determines whether `lastError` is a disconnection error.
  when defined(windows):
    (
      lastError.int32 == WSAECONNRESET or lastError.int32 == WSAECONNABORTED or
      lastError.int32 == WSAENETRESET or lastError.int32 == WSAEDISCON or
      lastError.int32 == WSAESHUTDOWN or lastError.int32 == ERROR_NETNAME_DELETED
    )
  else:
    (
      lastError.int32 == ECONNRESET or lastError.int32 == EPIPE or
      lastError.int32 == ENETRESET
    )

when defined(linux):
  proc readIntoIOBuf*(
      socket: AsyncFD, buf: ptr IOBuf, maxSize: int
  ): owned(Future[int]) =
    assert maxSize > 0

    var retFuture = newFuture[int]("readIntoIOBuf")

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = readIntoIOBuf(cint(sock), buf[], maxSize)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EINTR and lastError.int32 != EWOULDBLOCK and
            lastError.int32 != EAGAIN:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        else:
          result = false # We still want this callback to be called.
      else:
        retFuture.complete(res)

    # TODO: The following causes a massive slowdown.
    #if not cb(socket):
    addRead(socket, cb)
    return retFuture

  proc writeIOBuf*(socket: AsyncFD, buf: ptr IOBuf): owned(Future[void]) =
    assert buf[].len > 0

    var written = 0
    let maxSize = buf[].len
    var retFuture = newFuture[void]("writeIOBuf")

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = writeIOBuf(cint(sock), buf[])
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EINTR and lastError.int32 != EWOULDBLOCK and
            lastError.int32 != EAGAIN:
          retFuture.fail(newOSError(lastError))
        else:
          result = false # We still want this callback to be called.
      else:
        written.inc(res)
        if written < maxSize:
          result = false # We still have data to send.
        else:
          retFuture.complete()

    # TODO: The following causes crashes.
    #if not cb(socket):
    addWrite(socket, cb)
    return retFuture

proc readIntoIOBufFailback(
    socket: AsyncSocket, buf: ptr IOBuf, maxSize: int): owned(Future[
        int]) {.async.} =
  let chunk = DequeBuf(buf[]).allocChunk()
  let n = await socket.recvInto(chunk.writeAddr, min(chunk.freeSpace, maxSize))
  if n > 0:
    var region = chunk.advanceWposRegion(n)
    DequeBuf(buf[]).enqueueRightZeroCopy(move region)
  n

proc writeIOBufFailback(
    socket: AsyncSocket, buf: ptr IOBuf): owned(Future[void]) {.async.} =
  var written = 0
  defer:
    DequeBuf(buf[]).dequeueLeft(written)

  for slice in buf[].items():
    await socket.send(slice.leftAddr, slice.len)
    inc written, slice.len

proc readIntoIOBuf*(
    socket: AsyncSocket, buf: ptr IOBuf, maxSize: int): owned(Future[int]) =
  assert maxSize > 0

  when defined(linux):
    privateAccess(AsyncSocket)

    # readv
    if not socket.isBuffered and not socket.isSsl:
      return AsyncFD(socket.fd).readIntoIOBuf(buf, maxSize)

  readIntoIOBufFailback(socket, buf, maxSize)

proc writeIOBuf*(socket: AsyncSocket, buf: ptr IOBuf): owned(Future[void]) =
  assert buf[].len > 0

  when defined(linux):
    privateAccess(AsyncSocket)

    # writev
    if not socket.isBuffered and not socket.isSsl:
      return writeIOBuf(AsyncFD(socket.fd), buf)

  writeIOBufFailback(socket, buf)
