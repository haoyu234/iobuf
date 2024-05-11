import std/nativesockets
import std/oserrors

when defined(windows):
  import std/winlean
else:
  import std/posix

proc socketPair*(p: var array[2, SocketHandle]): cint =
  let s1 = createNativeSocket()
  if s1 == osInvalidSocket:
    return cint(osLastError())

  var e = 0
  defer: close(s1)

  var sa: Sockaddr_in
  sa.sin_port = 0
  sa.sin_addr = InAddr(s_addr: nativesockets.htonl(INADDR_LOOPBACK))

  when defined(windows):
    sa.sin_family = uint16(AF_INET)
  else:
    sa.sin_family = TSa_Family(posix.AF_INET)

  setSockOptInt(s1, SOL_SOCKET, SO_REUSEADDR, 1)
  e = s1.bindAddr(cast[ptr SockAddr](sa.addr), SockLen(sizeof(sa)))
  if e != 0:
    return cint(e)

  when defined(windows):
    sa.sin_port = nativesockets.htons(s1.getSockName().uint16)
  else:
    sa.sin_port = nativesockets.htons(s1.getSockName().InPort)

  e = nativesockets.listen(s1, cint(1))
  if e != 0:
    return cint(e)

  let s2 = createNativeSocket()
  e = s2.connect(cast[ptr SockAddr](sa.addr), SockLen(sizeof(sa)))
  if e != 0:
    close(s2)
    return cint(e)

  let s3 = nativesockets.accept(s1, nil, nil)
  p[0] = s2
  p[1] = s3
