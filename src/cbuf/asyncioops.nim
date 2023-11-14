import std/asyncdispatch
import std/oserrors
import std/nativesockets
import std/net

import iobuf
import ioops

when defined(linux):

  proc readInto*(socket: AsyncFD, buf: ptr IOBuf, maxSize: int,
                 flags = {SocketFlag.SafeDisconn}): owned(Future[int]) =
    var retFuture = newFuture[int]("recvInto")

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = readv(cint(sock), buf[], maxSize)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EINTR and lastError.int32 != EWOULDBLOCK and
           lastError.int32 != EAGAIN:
          if flags.isDisconnectionError(lastError):
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
