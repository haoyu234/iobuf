import std/unittest
import std/asyncdispatch

import std/posix

import iobuf/iobuf
import iobuf/aio

const SIZE = 100

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  data.add(byte(i mod int(high(byte))))

proc produceSync(fd: AsyncFD, data: seq[byte]) {.async.} =
  defer:
    discard close(cint(fd))

  var num = 0
  while num < data.len:
    let left = data.len - num
    let result = write(cint(fd), data[num].addr, left)
    inc num, result

  assert num == data.len

proc produce(fd: AsyncFD, data: seq[byte]) {.async.} =
  defer:
    discard close(cint(fd))

  register(fd)

  defer:
    unregister(fd)

  var buf: IOBuf
  buf.initBuf()
  buf.writeZeroCopy(data[0].addr, data.len)

  check buf.len == data.len

  await writeIOBuf(fd, buf.addr, buf.len)

proc consume(fd: AsyncFD, buf: ptr IOBuf, maxSize: int) {.async.} =
  defer:
    discard close(cint(fd))

  register(fd)

  defer:
    unregister(fd)

  let result = await readIOBuf(fd, buf, maxSize)

  check result == maxSize
  check buf[].len == maxSize

test "readInto":
  var buf: IOBuf
  buf.initBuf()

  var fds: array[2, cint]

  check pipe(fds) == 0

  let fut1 = produceSync(AsyncFD(fds[1]), data)
  let fut2 = consume(AsyncFD(fds[0]), buf.addr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data

test "write":
  var buf: IOBuf
  buf.initBuf()

  var fds: array[2, cint]

  check pipe(fds) == 0

  let fut1 = produce(AsyncFD(fds[1]), data)
  let fut2 = consume(AsyncFD(fds[0]), buf.addr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data
