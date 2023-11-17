import intern/tls
import intern/chunk
import intern/region
import intern/deprecated
import intern/iobuf

import slice2

type
  IOBuf* = distinct InternIOBuf

proc initIOBuf*(): IOBuf {.inline.} =
  InternIOBuf(result).initIOBuf

proc initIOBuf*(buf: var IOBuf) {.inline.} =
  InternIOBuf(buf).initIOBuf

proc len*(buf: IOBuf): int {.inline.} =
  InternIOBuf(buf).len

proc clear*(buf: var IOBuf) {.inline.} =
  InternIOBuf(buf).clear

proc toSeq*(buf: IOBuf): seq[byte] {.inline.} =
  result = newSeqOfCap[byte](buf.len)

  for region in InternIOBuf(buf):
    result.add(region.toOpenArray())

iterator items*(buf: IOBuf): Slice2[byte] {.inline.} =
  for region in InternIOBuf(buf):
    yield region.toOpenArray().slice()

proc appendCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  InternIOBuf(buf).enqueueRightCopy(data, len)

proc appendCopy*(buf: var IOBuf, data: openArray[byte]) {.inline.} =
  InternIOBuf(buf).enqueueRightCopy(data[0].getAddr, data.len)

proc appendCopy*(buf: var IOBuf, data: Slice2[byte]) {.inline.} =
  InternIOBuf(buf).enqueueRightCopy(data.leftAddr, data.len)

proc appendZeroCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  var chunk = newChunk(data, len, len)
  var region = initRegion(move chunk, 0, len)
  InternIOBuf(buf).enqueueRightZeroCopy(move region)

proc appendZeroCopy*(buf: var IOBuf, data: sink seq[byte]) {.inline.} =
  let len = data.len
  var chunk = newChunk(move data)
  var region = initRegion(move chunk, 0, len)
  InternIOBuf(buf).enqueueRightZeroCopy(move region)

proc appendZeroCopy*(buf: var IOBuf, data: IOBuf) {.inline.} =
  InternIOBuf(buf).enqueueRightZeroCopy(InternIOBuf(data))

proc appendZeroCopy*(buf: var IOBuf, data: IOBuf, size: int) {.inline.} =
  let minSize = min(size, data.len)

  template peekLeft(it) =
    InternIOBuf(buf).enqueueRightZeroCopy(it)

  InternIOBuf(data).consumeLeft(minSize, dequeue = false, peekLeft)

proc append*(buf: var IOBuf, data: byte) {.inline.} =
  var lastChunk = sharedTlsChunk()
  let len = lastChunk.len
  let dstAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(len))
  cast[ptr byte](dstAddr)[] = data

  lastChunk.extendLen(1)

  var region = initRegion(move lastChunk, len, 1)
  InternIOBuf(buf).enqueueRightZeroCopy(move region)

proc discardLeft*(buf: var IOBuf, size: int) {.inline.} =
  if buf.len <= 0 or size <= 0:
    return

  InternIOBuf(buf).dequeueLeft(size)

proc peekLeftCopy*(buf: IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  template peekLeft(it) =
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

  InternIOBuf(buf).consumeLeft(size, dequeue = false, peekLeft)

proc peekLeftCopy*(buf: IOBuf, data: var seq[byte], size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len

  template peekLeft(it) =
    data.add(it.toOpenArray)

  InternIOBuf(buf).consumeLeft(size, dequeue = false, peekLeft)

  result = data.len - oldLen

proc peekLeftZeroCopy*(buf: IOBuf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  template peekLeft(it) =
    InternIOBuf(into).enqueueRightZeroCopy(it)
    inc result, it.len

  InternIOBuf(buf).consumeLeft(size, dequeue = false, peekLeft)

proc readLeftCopy*(buf: var IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  template readLeft(it) =
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

  InternIOBuf(buf).consumeLeft(size, dequeue = true, readLeft)

proc readLeftCopy*(buf: var IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len

  template readLeft(it) =
    data.add(it.toOpenArray)

  InternIOBuf(buf).consumeLeft(size, dequeue = true, readLeft)

  result = data.len - oldLen

proc readLeftZeroCopy*(buf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  template readLeft(it) =
    InternIOBuf(into).enqueueRightZeroCopy(move it)
    inc result, it.len

  InternIOBuf(buf).consumeLeft(size, dequeue = true, readLeft)

proc discardRight*(buf: var IOBuf, size: int) {.inline.} =
  if buf.len <= 0 or size <= 0:
    return

  InternIOBuf(buf).dequeueRight(size)

proc peekRightCopy*(buf: IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  template peekRight(it) =
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

  InternIOBuf(buf).consumeRight(size, dequeue = false, peekRight)

proc peekRightCopy*(buf: IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len

  template peekRight(it) =
    data.add(it.toOpenArray)

  InternIOBuf(buf).consumeRight(size, dequeue = false, peekRight)

  result = data.len - oldLen

proc peekRightZeroCopy*(buf: IOBuf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  template peekRight(it) =
    InternIOBuf(into).enqueueRightZeroCopy(it)
    inc result, it.len

  InternIOBuf(buf).consumeRight(size, dequeue = false, peekRight)

proc readRightCopy*(buf: var IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  template readRight(it) =
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

  InternIOBuf(buf).consumeRight(size, dequeue = true, readRight)

proc readRightCopy*(buf: var IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len

  template readRight(it) =
    data.add(it.toOpenArray)

  InternIOBuf(buf).consumeRight(size, dequeue = true, readRight)

  result = data.len - oldLen

proc readRightZeroCopy*(buf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  template readRight(it) =
    InternIOBuf(into).enqueueRightZeroCopy(move it)
    inc result, it.len

  InternIOBuf(buf).consumeRight(size, dequeue = true, readRight)
