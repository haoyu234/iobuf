import std/asyncdispatch
import std/oserrors
import std/nativesockets
import std/net

import iobuf
import vio

proc isDisconnectionError*(lastError: OSErrorCode): bool =
  ## Determines whether `lastError` is a disconnection error.
  when defined(windows):
    (lastError.int32 == WSAECONNRESET or
       lastError.int32 == WSAECONNABORTED or
       lastError.int32 == WSAENETRESET or
       lastError.int32 == WSAEDISCON or
       lastError.int32 == WSAESHUTDOWN or
       lastError.int32 == ERROR_NETNAME_DELETED)
  else:
    (lastError.int32 == ECONNRESET or
       lastError.int32 == EPIPE or
       lastError.int32 == ENETRESET)

when defined(linux):

  proc readIntoIOBuf*(socket: AsyncFD, buf: ptr IOBuf, maxSize: int): owned(Future[int]) =
    var retFuture = newFuture[int]("readIntoIOBuf")

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = readv(cint(sock), buf[], maxSize)
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

  proc writeIOBuf*(socket: AsyncFD, buf: ptr IOBuf, size: int): owned(Future[void]) =
    var retFuture = newFuture[void]("writeIOBuf")

    var written = 0

    proc cb(sock: AsyncFD): bool =
      result = true
      let netSize = size - written
      let res = writev(cint(sock), buf[], netSize)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EINTR and
           lastError.int32 != EWOULDBLOCK and
           lastError.int32 != EAGAIN:
          retFuture.fail(newOSError(lastError))
        else:
          result = false # We still want this callback to be called.
      else:
        written.inc(res)
        if res != netSize:
          result = false # We still have data to send.
        else:
          retFuture.complete()
    # TODO: The following causes crashes.
    #if not cb(socket):
    addWrite(socket, cb)
    return retFuture
