import intern/chunk
import intern/region
import intern/deprecated
import intern/iobuf

import slice2

type
  IOBuf* = distinct InternalIOBuf

proc initBuf*(buf: var IOBuf) {.inline.} =
  InternalIOBuf(buf).initBuf

proc len*(buf: IOBuf): int {.inline.} =
  InternalIOBuf(buf).len

proc clear*(buf: var IOBuf) {.inline.} =
  InternalIOBuf(buf).clear

proc toSeq*(buf: IOBuf): seq[byte] {.inline.} =
  result = newSeqOfCap[byte](buf.len)

  for region in InternalIOBuf(buf):
    result.add(region.toOpenArray())

iterator items*(buf: IOBuf): Slice2[byte] {.inline.} =
  for region in InternalIOBuf(buf):
    yield region.toOpenArray().slice()

proc writeCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  InternalIOBuf(buf).enqueueRightCopy(data, len)

proc writeCopy*(buf: var IOBuf, data: openArray[byte]) {.inline.} =
  InternalIOBuf(buf).enqueueRightCopy(data[0].getAddr, data.len)

proc writeCopy*(buf: var IOBuf, data: Slice2[byte]) {.inline.} =
  InternalIOBuf(buf).enqueueRightCopy(data.leftAddr, data.len)

proc writeCopy*(buf: var IOBuf, data: byte) {.inline.} =
  InternalIOBuf(buf).enqueueByteRight(data)

proc writeZeroCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  var chunk = newChunk(data, len, len)
  var region = initRegion(move chunk, 0, len)
  InternalIOBuf(buf).enqueueRightZeroCopy(move region)

proc writeZeroCopy*(buf: var IOBuf, data: sink seq[byte]) {.inline.} =
  let len = data.len
  var chunk = newChunk(move data)
  var region = initRegion(move chunk, 0, len)
  InternalIOBuf(buf).enqueueRightZeroCopy(move region)

proc writeZeroCopy*(buf: var IOBuf, data: IOBuf) {.inline.} =
  InternalIOBuf(buf).enqueueRightZeroCopy(InternalIOBuf(data))

proc writeZeroCopy*(buf: var IOBuf, data: IOBuf, size: int) {.inline.} =
  let minSize = min(size, data.len)

  for region in InternalIOBuf(buf).visitLeftRegion(minSize):
    InternalIOBuf(buf).enqueueRightZeroCopy(region)

proc discardBytes*(buf: var IOBuf, size: int) {.inline.} =
  if buf.len <= 0 or size <= 0:
    return

  InternalIOBuf(buf).dequeueLeft(size)

proc peekCopy*(buf: IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  for region in InternalIOBuf(buf).visitLeftRegion(size):
    let dstAddr = cast[uint](data) + uint(result)
    inc result, region.len

    copyMem(cast[pointer](dstAddr), region.leftAddr, region.len)

proc peekCopy*(buf: IOBuf, data: var seq[byte], size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  for region in InternalIOBuf(buf).visitLeftRegion(size):
    data.add(region.toOpenArray)
    inc result, region.len

proc peekZeroCopy*(buf: IOBuf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  for region in InternalIOBuf(buf).visitLeftRegion(size):
    InternalIOBuf(into).enqueueRightZeroCopy(region)
    inc result, region.len

proc readCopy*(buf: var IOBuf, data: pointer, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  for region in InternalIOBuf(buf).visitLeftRegionAndDequeue(size):
    let dstAddr = cast[uint](data) + uint(result)
    inc result, region.len

    copyMem(cast[pointer](dstAddr), region.leftAddr, region.len)

proc readCopy*(buf: var IOBuf, data: var seq[byte],
    size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  for region in InternalIOBuf(buf).visitLeftRegionAndDequeue(size):
    data.add(region.toOpenArray)
    inc result, region.len

proc readZeroCopy*(buf, into: var IOBuf, size: int): int {.inline.} =
  if size <= 0 or buf.len <= 0:
    return

  for region in InternalIOBuf(buf).visitLeftRegionAndDequeue(size):
    InternalIOBuf(into).enqueueRightZeroCopy(region)
    inc result, region.len
