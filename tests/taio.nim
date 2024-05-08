import std/unittest
import std/asyncdispatch
import std/asyncfile
import std/nativesockets

import std/posix

import iobuf/iobuf
import iobuf/aio
import iobuf/slice2

const SIZE = 1000000

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  let d = byte(i mod int(high(byte)))
  data.add(d)

proc sum(s: openArray[byte]): int =
  for v in s:
    inc result, int(v)

let total = sum(data)

proc produceAsync(fd: AsyncFD, data: seq[byte]) {.async.} =
  let f = newAsyncFile(fd)

  var num = 0
  while num < data.len:
    let left = data.len - num
    let sz = min(1024, left)
    await f.writeBuffer(data[num].addr, sz)
    inc num, sz

  assert num == data.len

proc produceAsyncIOBuf(fd: AsyncFD, data: seq[byte]) {.async.} =
  defer:
    discard close(cint(fd))

  register(fd)

  defer:
    unregister(fd)

  var buf: IOBuf
  buf.writeZeroCopy(data[0].addr, data.len)

  check buf.len == data.len

  await writeIOBuf(fd, buf.addr)

proc consumeAsyncIOBuf(fd: AsyncFD, buf: ptr IOBuf, maxSize: int) {.async.} =
  defer:
    discard close(cint(fd))

  register(fd)

  defer:
    unregister(fd)

  var num = 0
  while num < maxSize:
    let left = maxSize - num
    let sz = await readIntoIOBuf(fd, buf, left)
    inc num, sz

  var checkTotal = 0
  for r in buf[]:
    inc checkTotal, sum(r.toOpenArray)

  check num == maxSize
  check checkTotal == total
  check buf[].len == maxSize

proc setBlocking(p: array[2, cint]) =
  SocketHandle(p[0]).setBlocking(false)
  SocketHandle(p[1]).setBlocking(false)

test "readInto":
  var buf: IOBuf

  var fds: array[2, cint]

  check pipe(fds) == 0
  setBlocking(fds)

  let fut1 = produceAsync(AsyncFD(fds[1]), data)
  let fut2 = consumeAsyncIOBuf(AsyncFD(fds[0]), buf.addr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data

test "write":
  var buf: IOBuf

  var fds: array[2, cint]

  check pipe(fds) == 0
  setBlocking(fds)

  let fut1 = produceAsyncIOBuf(AsyncFD(fds[1]), data)
  let fut2 = consumeAsyncIOBuf(AsyncFD(fds[0]), buf.addr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data
