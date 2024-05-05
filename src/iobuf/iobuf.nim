import ./slice2

import ./intern/chunk
import ./intern/region
import ./intern/iobuf

type IOBuf* = distinct InternalIOBuf

proc `$`*(buf: IOBuf): string {.inline.} =
  $InternalIOBuf(buf)

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

proc consume*(buf: var IOBuf, size: int) {.inline.} =
  InternalIOBuf(buf).dequeueLeft(size)

proc writeCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  InternalIOBuf(buf).enqueueRightCopy(data, len)

proc writeCopy*(buf: var IOBuf, data: openArray[byte]) {.inline.} =
  InternalIOBuf(buf).enqueueRightCopy(data[0].addr, data.len)

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

proc peekCopyInto*(buf: IOBuf, data: pointer, size: int) {.inline.} =
  var offset = uint(0)

  for region in InternalIOBuf(buf).visitLeft(size):
    let dstAddr = cast[uint](data) + offset
    inc offset, region.len

    copyMem(cast[pointer](dstAddr), region.leftAddr, region.len)

proc peekCopyInto*(buf: IOBuf, data: var seq[byte], size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for region in InternalIOBuf(buf).visitLeft(size):
    data.add(region.toOpenArray)

proc peekZeroCopyInto*(buf: IOBuf, into: var IOBuf, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for region in InternalIOBuf(buf).visitLeftRegion(size):
    InternalIOBuf(into).enqueueRightZeroCopy(region)

proc peekCopy*(buf: IOBuf, size: int): seq[byte] {.inline.} =
  buf.peekCopyInto(result, size)

proc peekZeroCopy*(buf: IOBuf, size: int): IOBuf {.inline.} =
  buf.peekZeroCopyInto(result, size)

proc readCopyInto*(buf: var IOBuf, data: pointer, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  var offset = uint(0)

  for slice in InternalIOBuf(buf).visitLeftAndDequeue(size):
    let dstAddr = cast[uint](data) + offset
    inc offset, slice.len

    copyMem(cast[pointer](dstAddr), slice.leftAddr, slice.len)

proc readCopyInto*(buf: var IOBuf, data: var seq[byte], size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for slice in InternalIOBuf(buf).visitLeftAndDequeue(size):
    data.add(slice.toOpenArray)

proc readZeroCopyInto*(buf, into: var IOBuf, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for region in InternalIOBuf(buf).visitLeftRegionAndDequeue(size):
    InternalIOBuf(into).enqueueRightZeroCopy(region)

proc readCopy*(buf: var IOBuf, size: int): seq[byte] {.inline.} =
  buf.readCopyInto(result, size)

proc readZeroCopy*(buf: var IOBuf, size: int): IOBuf {.inline.} =
  buf.readZeroCopyInto(result, size)
