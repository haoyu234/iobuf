import std/unittest
import std/asyncnet
import std/asyncdispatch
import std/nativesockets

import iobuf/iobuf
import iobuf/aio
import iobuf/slice2

import ./socketpair

const SIZE = 1000000

type
  ASocketPair = object
    fds: array[2, AsyncFD]

proc setBlocking(p: array[2, SocketHandle]) =
  p[0].setBlocking(false)
  p[1].setBlocking(false)

proc pipe(): ASocketPair =
  var fds: array[2, SocketHandle]
  check socketPair(fds) == 0

  setBlocking(fds)

  result.fds[0] = AsyncFD(fds[0])
  result.fds[1] = AsyncFD(fds[1])

  register(result.fds[0])
  register(result.fds[1])

proc destroy(s: ASocketPair) =
  unregister(s.fds[0])
  unregister(s.fds[1])
  nativesockets.close(SocketHandle(s.fds[0]))
  nativesockets.close(SocketHandle(s.fds[1]))

var data = newSeqOfCap[byte](SIZE)
for i in 0 ..< SIZE:
  let d = byte(i mod int(high(byte)))
  data.add(d)

proc sum(s: openArray[byte]): int =
  for v in s:
    inc result, int(v)

let total = sum(data)

proc produceAsync(fd: AsyncFD, data: seq[byte]) {.async.} =
  let f = newAsyncSocket(fd)

  var num = 0
  while num < data.len:
    let left = data.len - num
    let sz = min(1024, left)
    await f.send(data[num].addr, sz)
    inc num, sz

  assert num == data.len

proc produceAsyncIOBuf(fd: AsyncFD, data: seq[byte]) {.async.} =
  when defined(windows):
    let s = newAsyncSocket(fd)
  else:
    let s = fd

  var buf: IOBuf
  buf.writeZeroCopy(data[0].addr, data.len)

  check buf.len == data.len

  await writeIOBuf(s, buf.addr)

proc consumeAsyncIOBuf(fd: AsyncFD, buf: ptr IOBuf,
    maxSize: int) {.async.} =
  when defined(windows):
    let s = newAsyncSocket(fd)
  else:
    let s = fd

  var num = 0
  while num < maxSize:
    let left = maxSize - num
    let sz = await readIntoIOBuf(s, buf, left)
    inc num, sz

  var checkTotal = 0
  for r in buf[]:
    inc checkTotal, sum(r.toOpenArray)

  check num == maxSize
  check checkTotal == total
  check buf[].len == maxSize

test "readInto":
  var buf: IOBuf

  let p = pipe()
  defer: p.destroy()

  let fut1 = produceAsync(p.fds[1], data)
  let fut2 = consumeAsyncIOBuf(p.fds[0], buf.addr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data

test "write":
  var buf: IOBuf

  let p = pipe()
  defer: p.destroy()

  let fut1 = produceAsyncIOBuf(p.fds[1], data)
  let fut2 = consumeAsyncIOBuf(p.fds[0], buf.addr, data.len)

  waitFor all(fut1, fut2)

  check buf.len == data.len
  check buf.toSeq() == data
