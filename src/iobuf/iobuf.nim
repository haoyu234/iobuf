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
  for region in InternIOBuf(data):
    InternIOBuf(buf).enqueueRightZeroCopy(region)

proc appendZeroCopy*(buf: var IOBuf, data: byte) {.inline.} =
  var lastChunk = sharedTlsChunk()
  let len = lastChunk.len
  let dstAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(len))
  cast[ptr byte](dstAddr)[] = data

  lastChunk.extendLen(1)

  var region = initRegion(move lastChunk, len, 1)
  InternIOBuf(buf).enqueueRightZeroCopy(move region)

proc discardLeft*(buf: var IOBuf, size: int) {.inline.} =
  InternIOBuf(buf).dequeueLeft(size)

proc peekLeftCopy*(buf: IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeLeft(size, false):
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

proc peekLeftCopy*(buf: IOBuf, data: var seq[byte], size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len
  InternIOBuf(buf).consumeLeft(size, false):
    data.add(it.toOpenArray)

  result = data.len - oldLen

proc peekLeft*(buf: IOBuf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeLeft(size, false):
    InternIOBuf(into).enqueueRightZeroCopy(it)
    inc result, it.len

proc readLeftCopy*(buf: var IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeLeft(size, true):
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

proc readLeftCopy*(buf: var IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len
  InternIOBuf(buf).consumeLeft(size, true):
    data.add(it.toOpenArray)

  result = data.len - oldLen

proc readLeft*(buf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeLeft(size, true):
    InternIOBuf(into).enqueueRightZeroCopy(move it)
    inc result, it.len

proc discardRight*(buf: var IOBuf, size: int) {.inline.} =
  InternIOBuf(buf).dequeueRight(size)

proc peekRightCopy*(buf: IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeRight(size, false):
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

proc peekRightCopy*(buf: IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len
  InternIOBuf(buf).consumeRight(size, false):
    data.add(it.toOpenArray)

  result = data.len - oldLen

proc peekRight*(buf: IOBuf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeRight(size, false):
    InternIOBuf(into).enqueueRightZeroCopy(it)
    inc result, it.len

proc readRightCopy*(buf: var IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeRight(size, true):
    copyMem(data2[result].getAddr, it.leftAddr, it.len)
    inc result, it.len

proc readRightCopy*(buf: var IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  let oldLen = data.len
  InternIOBuf(buf).consumeRight(size, true):
    data.add(it.toOpenArray)

  result = data.len - oldLen

proc readRight*(buf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeRight(size, true):
    InternIOBuf(into).enqueueRightZeroCopy(move it)
    inc result, it.len
