import intern/tls
import intern/indices
import intern/chunk
import intern/region
import intern/deprecated
import intern/iobuf

import slice2

type
  IOBuf* = distinct InternIOBuf

proc initBuf*(): IOBuf {.inline.} =
  InternIOBuf(result).initBuf

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
  InternIOBuf(buf).enqueueSlowCopyRight(data, len)

proc appendCopy*(buf: var IOBuf, data: openArray[byte]) {.inline.} =
  InternIOBuf(buf).enqueueSlowCopyRight(data[0].getAddr, data.len)

proc appendCopy*(buf: var IOBuf, data: Slice2[byte]) {.inline.} =
  InternIOBuf(buf).enqueueSlowCopyRight(data.leftAddr, data.len)

proc appendZeroCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  InternIOBuf(buf).enqueueZeroCopyRight(data, len)

proc appendZeroCopy*(buf: var IOBuf, data: sink seq[byte]) {.inline.} =
  let dataLen = data.len
  var chunk = newChunk(move data)
  InternIOBuf(buf).enqueueZeroCopyRight(move chunk, 0, dataLen)

proc appendZeroCopy*(buf: var IOBuf, data: IOBuf) {.inline.} =
  for region in InternIOBuf(data):
    InternIOBuf(buf).enqueueZeroCopyRight(region)

proc appendZeroCopy*(buf: var IOBuf, data: byte) {.inline.} =
  var lastChunk = sharedTlsChunk()
  let oldLen = lastChunk.len
  let writeAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(oldLen))
  cast[ptr byte](writeAddr)[] = data

  lastChunk.extendLen(1)

  if InternIOBuf(buf).extendAdjacencyRegionRight(writeAddr, 1):
    return

  InternIOBuf(buf).enqueueZeroCopyRight(move lastChunk, oldLen, 1)

proc discardLeft*(buf: var IOBuf, size: int) {.inline.} =
  InternIOBuf(buf).dequeueLeft(size)

proc peekLeftCopy*(buf: IOBuf, data: pointer, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  var written = 0
  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeLeft(size, false):
    copyMem(data2[written].getAddr, it.leftAddr, it.len)
    inc written, it.len

proc peekLeft*(buf: IOBuf, into: var IOBuf, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeLeft(size, false):
    InternIOBuf(into).enqueueZeroCopyRight(it)

proc readLeftCopy*(buf: var IOBuf, data: pointer, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  var written = 0
  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeLeft(size, true):
    copyMem(data2[written].getAddr, it.leftAddr, it.len)
    inc written, it.len

proc readLeft*(buf, into: var IOBuf, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeLeft(size, true):
    InternIOBuf(into).enqueueZeroCopyRight(move it)

proc discardRight*(buf: var IOBuf, size: int) {.inline.} =
  InternIOBuf(buf).dequeueRight(size)

proc peekRightCopy*(buf: IOBuf, data: pointer, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  var written = 0
  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeRight(size, false):
    copyMem(data2[written].getAddr, it.leftAddr, it.len)
    inc written, it.len

proc peekRight*(buf: IOBuf, into: var IOBuf, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeRight(size, false):
    InternIOBuf(into).enqueueZeroCopyRight(it)

proc readRightCopy*(buf: var IOBuf, data: pointer, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  var written = 0
  let data2 = cast[ptr UncheckedArray[byte]](data)

  InternIOBuf(buf).consumeRight(size, true):
    copyMem(data2[written].getAddr, it.leftAddr, it.len)
    inc written, it.len

proc readRight*(buf, into: var IOBuf, size: int) {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  InternIOBuf(buf).consumeRight(size, true):
    InternIOBuf(into).enqueueZeroCopyRight(move it)
