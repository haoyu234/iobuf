import std/asyncdispatch
import std/oserrors
import std/nativesockets
import std/net

import iobuf
import ioops

proc isDisconnectionError(lastError: OSErrorCode): bool =
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

  proc readInto*(socket: AsyncFD, buf: ptr IOBuf, maxSize: int): owned(Future[int]) =
    var retFuture = newFuture[int]("recvInto")

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = readv(cint(sock), buf[], maxSize)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EINTR and lastError.int32 != EWOULDBLOCK and
           lastError.int32 != EAGAIN:
          if isDisconnectionError(lastError):
            retFuture.complete(0)
          else:
            retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        else:
          result = false # We still want this callback to be called.
      else:
        retFuture.complete(res)
    # TODO: The following causes a massive slowdown.
    #if not cb(socket):
    addRead(socket, cb)
    return retFuture
