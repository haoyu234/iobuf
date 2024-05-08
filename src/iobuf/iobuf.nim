import ./slice2

import ./intern/chunk
import ./intern/dequebuf

type IOBuf* = distinct DequeBuf

proc `$`*(buf: IOBuf): string {.inline.} =
  $DequeBuf(buf)

proc len*(buf: IOBuf): int {.inline.} =
  DequeBuf(buf).len

proc clear*(buf: var IOBuf) {.inline.} =
  DequeBuf(buf).clear

proc toSeq*(buf: IOBuf): seq[byte] {.inline.} =
  result = newSeqOfCap[byte](buf.len)

  for region in DequeBuf(buf):
    result.add(region.toOpenArray())

iterator items*(buf: IOBuf): Slice2[byte] {.inline.} =
  for region in DequeBuf(buf):
    yield region.toOpenArray().slice()

proc consume*(buf: var IOBuf, size: int) {.inline.} =
  DequeBuf(buf).dequeueLeft(size)

proc writeCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  DequeBuf(buf).enqueueRightCopy(data, len)

proc writeCopy*(buf: var IOBuf, data: openArray[byte]) {.inline.} =
  DequeBuf(buf).enqueueRightCopy(data[0].addr, data.len)

proc writeCopy*(buf: var IOBuf, data: Slice2[byte]) {.inline.} =
  DequeBuf(buf).enqueueRightCopy(data.leftAddr, data.len)

proc writeCopy*(buf: var IOBuf, data: byte) {.inline.} =
  DequeBuf(buf).enqueueByteRight(data)

proc writeZeroCopy*(buf: var IOBuf, data: pointer, len: int) {.inline.} =
  let chunk = newChunk(data, len, len)
  DequeBuf(buf).enqueueRightZeroCopy(chunk.region())

proc writeZeroCopy*(buf: var IOBuf, data: sink seq[byte]) {.inline.} =
  var chunk = newChunk(move data)
  DequeBuf(buf).enqueueRightZeroCopy(chunk.region())

proc writeZeroCopy*(buf: var IOBuf, data: IOBuf) {.inline.} =
  DequeBuf(buf).enqueueRightZeroCopy(DequeBuf(data))

proc writeZeroCopy*(buf: var IOBuf, data: IOBuf, size: int) {.inline.} =
  let minSize = min(size, data.len)

  for region in DequeBuf(buf).visitLeftRegion(minSize):
    DequeBuf(buf).enqueueRightZeroCopy(region)

proc peekCopyInto*(buf: IOBuf, data: pointer, size: int) {.inline.} =
  var offset = uint(0)

  for region in DequeBuf(buf).visitLeft(size):
    let dstAddr = cast[uint](data) + offset
    inc offset, region.len

    copyMem(cast[pointer](dstAddr), region.leftAddr, region.len)

proc peekCopyInto*(buf: IOBuf, data: var seq[byte], size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for region in DequeBuf(buf).visitLeft(size):
    data.add(region.toOpenArray)

proc peekZeroCopyInto*(buf: IOBuf, into: var IOBuf, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for region in DequeBuf(buf).visitLeftRegion(size):
    DequeBuf(into).enqueueRightZeroCopy(region)

proc peekCopy*(buf: IOBuf, size: int): seq[byte] {.inline.} =
  buf.peekCopyInto(result, size)

proc peekZeroCopy*(buf: IOBuf, size: int): IOBuf {.inline.} =
  buf.peekZeroCopyInto(result, size)

proc readCopyInto*(buf: var IOBuf, data: pointer, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  var offset = uint(0)

  for slice in DequeBuf(buf).visitLeftAndDequeue(size):
    let dstAddr = cast[uint](data) + offset
    inc offset, slice.len

    copyMem(cast[pointer](dstAddr), slice.leftAddr, slice.len)

proc readCopyInto*(buf: var IOBuf, data: var seq[byte], size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for slice in DequeBuf(buf).visitLeftAndDequeue(size):
    data.add(slice.toOpenArray)

proc readZeroCopyInto*(buf, into: var IOBuf, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  for region in DequeBuf(buf).visitLeftRegionAndDequeue(size):
    DequeBuf(into).enqueueRightZeroCopy(region)

proc readCopy*(buf: var IOBuf, size: int): seq[byte] {.inline.} =
  buf.readCopyInto(result, size)

proc readZeroCopy*(buf: var IOBuf, size: int): IOBuf {.inline.} =
  buf.readZeroCopyInto(result, size)
