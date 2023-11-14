import std/unittest
import std/asyncdispatch

import std/posix

import cbuf/iobuf
import cbuf/asyncioops
import cbuf/intern/deprecated


const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

proc produce(fd: AsyncFD, data: seq[byte]) {.async.} =
  defer: discard close(cint(fd))

  var num = 0
  while num < data.len:
    let left = data.len - num
    let result = write(cint(fd), data[num].getAddr, left)
    inc num, result

  assert num == data.len

proc consume(fd: AsyncFD, buf: ptr IOBuf, maxSize: int) {.async.} =
  defer: discard close(cint(fd))

  register(fd)

  let result = await readInto(fd, buf, maxSize)

  check result == maxSize
  check buf[].len == maxSize

test "readInto":

  var buf = initBuf()
  var fds: array[2, cint]

  check pipe(fds) == 0

  let fut1 = produce(AsyncFD(fds[1]), data)
  let fut2 = consume(AsyncFD(fds[0]), buf.getAddr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data
