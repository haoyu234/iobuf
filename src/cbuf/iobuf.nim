import std/math

import intern/tls
import intern/indices
import intern/chunk
import intern/region
import intern/deprecated

import slice2

const INLINE_STORAGE = true
const INITIAL_QUEUE_CAPACITY = 32

type
  IOBuf* = object
    len: int
    lastChunk: Chunk

    queueSize: int32
    when INLINE_STORAGE:
      queueCapacity: int32
    else:
      queueCapacity: int32
    queueStart: int32
    queueStorage: ptr UncheckedArray[Region]
    when INLINE_STORAGE:
      inlineStorage: array[2, Region]

template storage(buf: IOBuf): ptr UncheckedArray[Region] =
  when not INLINE_STORAGE:
    buf.queueStorage
  else:
    if buf.queueStorage != nil:
      buf.queueStorage
    else:
      cast[ptr UncheckedArray[Region]](buf.inlineStorage[0].getAddr)

template storage(buf: var IOBuf): ptr UncheckedArray[Region] =
  when not INLINE_STORAGE:
    buf.queueStorage
  else:
    if buf.queueStorage != nil:
      buf.queueStorage
    else:
      cast[ptr UncheckedArray[Region]](buf.inlineStorage[0].getAddr)

template index(buf: IOBuf, idx: Natural): int =
  (buf.queueStart + int(idx)) and (buf.queueCapacity - 1)

template index(buf: IOBuf, idx: BackwardsIndex): int =
  (buf.queueStart + buf.queueSize - int(idx)) and (buf.queueCapacity - 1)

template resetStorage[U, V: Ordinal](buf: IOBuf, x: HSlice[U, V]) =
  let a = buf ^^ x.a
  let L = (buf ^^ x.b) - a + 1

  for idx in 0..<L:
    let newIdx = a + idx
    reset(buf.storage[buf.index(newIdx)])

proc `=destroy`(buf: var IOBuf) {.inline, `fix=destroy(var T)`.} =
  var lastChunk = buf.lastChunk
  while lastChunk != nil:
    lastChunk = lastChunk.dequeueChunk()

  if buf.queueStorage != nil:
    resetStorage(buf, 0 ..< buf.queueSize)
    freeShared(buf.queueStorage)

proc initBuf*(result: var IOBuf) {.inline.} =
  result.len = 0
  result.lastChunk = nil
  result.queueSize = 0
  result.queueStart = 0
  result.queueCapacity = 2
  result.queueStorage = nil

proc initBuf*(): IOBuf {.inline.} =
  result.len = 0
  result.lastChunk = nil
  result.queueSize = 0
  result.queueStart = 0
  result.queueCapacity = 2
  result.queueStorage = nil

template len*(buf: IOBuf): int = buf.len

template clear*(buf: var IOBuf) =
  if buf.queueSize > 0:
    resetStorage(buf, 0 ..< buf.queueSize)

    buf.len = 0
    buf.queueSize = 0
    buf.queueStart = 0

proc toSeq*(buf: IOBuf): seq[byte] {.inline.} =
  result = newSeqOfCap[byte](buf.len)

  for idx in 0..<buf.queueSize:
    result.add(buf.storage[buf.index(idx)].toOpenArray())

iterator items*(buf: IOBuf): Slice2[byte] {.inline.} =
  for idx in 0..<buf.queueSize:
    let newIdx = buf.index(idx)
    yield buf.storage[newIdx].toOpenArray().slice()

iterator regions*(buf: IOBuf): Region {.inline.} =
  for idx in 0..<buf.queueSize:
    yield buf.storage[buf.index(idx)]

template extendQueueStorageImpl(buf: var IOBuf, capacity: int) =
  let queueStorage = cast[ptr UncheckedArray[Region]](allocShared0(sizeof(
      Region) * capacity))

  for idx in 0..<buf.queueSize:
    queueStorage[idx] = buf.storage[buf.index(idx)]

  if buf.queueStorage != nil:
    freeShared(buf.queueStorage)
  else:
    when INLINE_STORAGE:
      reset(buf.inlineStorage)

  buf.queueStart = 0
  buf.queueStorage = queueStorage
  buf.queueCapacity = int32(capacity)

template extendQueueStorage(buf: var IOBuf) =
  if buf.queueSize == buf.queueCapacity or
    (not INLINE_STORAGE and buf.queueStorage.isNil):

    let newCapacity = max(int(buf.queueCapacity) * 2, INITIAL_QUEUE_CAPACITY)
    extendQueueStorageImpl(buf, newCapacity)

proc reserveQueueStorage*(buf: var IOBuf, size: int) {.inline.} =
  if buf.queueCapacity < size:
    let newCapacity = nextPowerOfTwo(size)
    extendQueueStorageImpl(buf, newCapacity)

proc extendAdjacencyRegionRight*(buf: var IOBuf, wirteAddr: pointer,
    size: int): bool {.inline.} =
  if buf.queueSize > 0:
    let idx = buf.index(^1)

    if wirteAddr == buf.storage[idx].rightAddr:
      inc buf.len, size
      buf.storage[idx].extendLen(size)
      result = true

proc enqueueZeroCopyRight*(buf: var IOBuf, region: sink Region) {.inline.} =
  let dataLen = region.len

  buf.extendQueueStorage()
  buf.storage[buf.index(buf.queueSize)] = move region

  inc buf.queueSize
  inc buf.len, dataLen

proc enqueueZeroCopyRight*(buf: var IOBuf, chunk: sink Chunk, offset,
    size: int) {.inline.} =
  assert size > 0

  buf.extendQueueStorage()
  buf.storage[buf.index(buf.queueSize)].initRegion(move chunk, offset, size)

  inc buf.queueSize
  inc buf.len, size

proc enqueueZeroCopyRight*(buf: var IOBuf, data: pointer,
    size: int) {.inline.} =
  assert size > 0

  var chunk = newChunk(data, size, size)

  buf.extendQueueStorage()
  buf.storage[buf.index(buf.queueSize)].initRegion(move chunk, 0, size)

  inc buf.queueSize
  inc buf.len, size

proc allocChunk*(buf: var IOBuf): Chunk {.inline.} =
  while true:
    result = buf.lastChunk
    if result.isNil:
      return allocTlsChunk()

    buf.lastChunk = result.dequeueChunk()
    if not result.isFull:
      break

proc releaseChunk*(buf: var IOBuf, chunk: sink Chunk) {.inline.} =
  if not chunk.isFull:
    if not buf.lastChunk.isNil:
      buf.lastChunk.enqueueChunk(move chunk)
    else:
      buf.lastChunk = chunk

proc enqueueSlowCopyRight*(buf: var IOBuf, data: pointer,
    size: int) {.inline.} =
  if size == 1:
    var lastChunk = sharedTlsChunk()
    let oldLen = lastChunk.len
    let writeAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(oldLen))
    cast[ptr byte](writeAddr)[] = cast[ptr byte](data)[]

    lastChunk.extendLen(1)

    if buf.extendAdjacencyRegionRight(writeAddr, 1):
      return

    buf.enqueueZeroCopyRight(move lastChunk, oldLen, 1)
    return

  var written = 0
  var lastChunk: Chunk = nil

  while written < size:
    let left = size - written

    lastChunk = if written >= DEFAULT_LARGE_CHUNK_SIZE and left >= DEFAULT_LARGE_CHUNK_SIZE:
      newChunk(DEFAULT_LARGE_CHUNK_SIZE)
    else:
      buf.allocChunk()

    let oldLen = lastChunk.len
    let writeAddr = cast[uint](lastChunk.leftAddr) + uint(oldLen)
    let dataLen = min(lastChunk.leftSpace(), left)

    copyMem(cast[pointer](writeAddr),
      cast[pointer](cast[uint](data) + uint(written)), dataLen)

    inc written, dataLen
    lastChunk.extendLen(dataLen)
    buf.enqueueZeroCopyRight(lastChunk, oldLen, dataLen)

  if lastChunk.isNil:
    return

  buf.releaseChunk(lastChunk)

proc append*(buf: var IOBuf, data: openArray[byte]) {.inline.} =
  buf.enqueueSlowCopyRight(data[0].getAddr, data.len)

proc append*(buf: var IOBuf, data: Slice2[byte]) {.inline.} =
  buf.enqueueSlowCopyRight(data.leftAddr, data.len)

proc append*(buf: var IOBuf, data: sink seq[byte]) {.inline.} =
  let dataLen = data.len
  var chunk = newChunk(move data)
  buf.enqueueZeroCopyRight(move chunk, 0, dataLen)

proc append*(buf: var IOBuf, data: IOBuf) {.inline.} =
  for idx in 0..<data.queueSize:
    buf.enqueueZeroCopyRight(data.storage[data.index(idx)])

proc append*(buf: var IOBuf, data: byte) {.inline.} =
  var lastChunk = sharedTlsChunk()
  let oldLen = lastChunk.len
  let writeAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(oldLen))
  cast[ptr byte](writeAddr)[] = data

  lastChunk.extendLen(1)

  if buf.extendAdjacencyRegionRight(writeAddr, 1):
    return

  buf.enqueueZeroCopyRight(move lastChunk, oldLen, 1)

proc whereRegion(buf: IOBuf,
  where: int, reverseSearch: static[bool] = false): (int, int) {.inline.} =

  assert where <= buf.len

  var searchPos = where

  when reverseSearch:
    for idx in countdown(int(buf.queueSize-1), 0):
      let dataLen = buf.storage[buf.index(idx)].len

      if searchPos < dataLen:
        result[0] = idx
        result[1] = searchPos
        return

      dec searchPos, dataLen
  else:
    for idx in countup(0, int(buf.queueSize-1)):
      let dataLen = buf.storage[buf.index(idx)].len

      if searchPos < dataLen:
        result[0] = idx
        result[1] = searchPos
        return

      dec searchPos, dataLen

proc internalDequeueAdjustLeft*(buf: var IOBuf,
  idx, offset, size: int) {.inline.} =

  when defined(debug):
    var size2 = offset
    for idx2 in 0..<idx:
      inc size2, buf.storage[buf.index(idx2)].len
    assert size2 == size

  dec buf.len, size
  resetStorage(buf, 0 ..< idx)

  buf.storage[buf.index(idx)].discardLeft(offset)
  if idx > 0:
    buf.queueStart = int32((buf.queueStart + idx) mod buf.queueCapacity)
    dec buf.queueSize, idx

proc internalDequeueAdjustRight*(buf: var IOBuf,
  idx, offset, size: int) {.inline.} =

  when defined(debug):
    var size2 = offset
    for idx2 in idx+1..<buf.queueSize:
      inc size2, buf.storage[buf.index(idx2)].len
    assert size2 == size

  dec buf.len, size
  resetStorage(buf, int32(idx + 1) ..< buf.queueSize)

  buf.storage[buf.index(idx)].discardRight(offset)
  buf.queueSize = int32(idx + 1)

proc discardLeft*(buf: var IOBuf, size: int) {.inline.} =
  if buf.queueSize > 0 and size > 0:
    if size >= buf.len:
      buf.clear()
    else:
      let (idx, offset) = buf.whereRegion(size)
      buf.internalDequeueAdjustLeft(idx, offset, size)

proc discardRight*(buf: var IOBuf, size: int) {.inline.} =
  if buf.queueSize > 0 and size > 0:
    if size >= buf.len:
      buf.clear()
    else:
      let (idx, offset) = buf.whereRegion(size, reverseSearch = true)
      buf.internalDequeueAdjustRight(idx, offset, size)

proc internalReadLeft(buf: var IOBuf,
  data: pointer, size: int, popLeft: static[bool]) {.inline.} =

  if size > 0:
    assert buf.len >= size

    var lastIdx = 0
    var written = 0
    let data2 = cast[ptr UncheckedArray[byte]](data)

    when popLeft:
      var readTailLen = 0

    while written < size:
      let newIdx = buf.index(lastIdx)

      let dataLen = buf.storage[newIdx].len
      let dataLeft = size - written

      var len = dataLen
      if dataLen > dataLeft:
        when popLeft:
          readTailLen = dataLeft
        len = dataLeft
      else:
        inc lastIdx

      copyMem(data2[written].getAddr, buf.storage[newIdx].leftAddr, len)
      inc written, len

    when popLeft:
      buf.internalDequeueAdjustLeft(lastIdx, readTailLen, size)

template peekLeft*(buf: var IOBuf, data: pointer, size: int) =
  buf.internalReadLeft(data, size, popLeft = false)

template readLeft*(buf: var IOBuf, data: pointer, size: int) =
  buf.internalReadLeft(data, size, popLeft = true)

proc `=copy`*(buf: var IOBuf, b: IOBuf) {.inline.} =
  if buf.getAddr == b.getAddr: return

  if buf.queueStorage != nil:
    resetStorage(buf, 0 ..< buf.queueSize)
  else:
    reset(buf.inlineStorage)

  buf.queueSize = 0
  buf.queueStart = 0

  buf.reserveQueueStorage(b.queueSize)
  buf.append(b)

proc `=sink`*(buf: var IOBuf, b: IOBuf) {.inline.} =
  `=destroy`(buf)
  wasMoved(buf)

  if b.queueStorage != nil:
    buf.len = b.len
    buf.lastChunk = b.lastChunk
    buf.queueSize = b.queueSize
    buf.queueStart = b.queueStart
    buf.queueCapacity = b.queueCapacity
    buf.queueStorage = b.queueStorage
    return

  buf.append(b)

proc `[]`*[U, V: Ordinal](buf: IOBuf, x: HSlice[U, V]): IOBuf {.inline.} =
  let a = buf ^^ x.a
  let L = (buf ^^ x.b) - a + 1

  checkSliceOp(buf.len, a, a + L)

  initBuf(result)

  if buf.queueSize > 0:
    var (idx, len) = buf.whereRegion(a)
    var region = buf.storage[buf.index(idx)][len..^1]
    result.enqueueZeroCopyRight(region)

    var left = L - region.len

    while left > 0:
      inc idx

      region = buf.storage[buf.index(idx)]
      if left < region.len:
        result.enqueueZeroCopyRight(region[0..<left])
        break

      dec left, region.len
      result.enqueueZeroCopyRight(region)
