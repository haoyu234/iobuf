import std/math
import std/typetraits

import tls
import indices
import chunk
import region
import deprecated
import storage

const INLINE_STORAGE = true
const INITIAL_QUEUE_CAPACITY = 32

type
  InternIOBuf* = object
    len: int
    lastChunk: Chunk

    queueSize: int32
    when INLINE_STORAGE:
      queueCapacity: int32
    else:
      queueCapacity: int32
    queueStart: int32
    queueStorage: QueueStorage
    when INLINE_STORAGE:
      inlineStorage: array[2, Region]

  LocatePos = object
    idx: int
    left: int
    right: int

  InternPos* = object
    idx: int
    offset: int

  InternSlice* = object
    start: InternPos
    stop: InternPos

template len*(buf: InternIOBuf): int = buf.len
template queueSize*(buf: InternIOBuf): int = buf.queueSize

template clear*(buf: var InternIOBuf) =
  if buf.queueSize > 0:
    resetStorage(buf, 0 ..< buf.queueSize)

    buf.len = 0
    buf.queueSize = 0
    buf.queueStart = 0

template fastClear*(buf: var InternIOBuf) =
  if buf.queueSize > 0:
    buf.len = 0
    buf.queueSize = 0
    buf.queueStart = 0

template index*(buf: InternIOBuf, idx: Natural): QueueIndex =
  QueueIndex((buf.queueStart + int(idx)) and (buf.queueCapacity - 1))

template index*(buf: InternIOBuf, idx: BackwardsIndex): QueueIndex =
  QueueIndex((buf.queueStart + buf.queueSize - int(idx)) and (
      buf.queueCapacity - 1))

template storage*(buf: InternIOBuf): QueueStorage =
  when not INLINE_STORAGE:
    buf.queueStorage
  else:
    if buf.queueStorage != nil:
      buf.queueStorage
    else:
      cast[QueueStorage](buf.inlineStorage[0].getAddr)

template storage*(buf: var InternIOBuf): QueueStorage =
  when not INLINE_STORAGE:
    buf.queueStorage
  else:
    if buf.queueStorage != nil:
      buf.queueStorage
    else:
      cast[QueueStorage](buf.inlineStorage[0].getAddr)

template resetStorage*[U, V: Ordinal](buf: InternIOBuf, x: HSlice[U, V]) =
  let a = buf ^^ x.a
  let L = (buf ^^ x.b) - a + 1

  for idx in 0..<L:
    let newIdx = a + idx
    reset(buf.storage[buf.index(newIdx)])

template extendQueueStorageImpl(buf: var InternIOBuf, capacity: int) =
  let queueStorage = allocStorage(capacity)

  for idx in 0..<buf.queueSize:
    queueStorage[QueueIndex(idx)] = move buf.storage[buf.index(idx)]

  if buf.queueStorage != nil:
    freeStorage(buf.queueStorage)

  buf.queueStart = 0
  buf.queueStorage = queueStorage
  buf.queueCapacity = int32(capacity)

template extendQueueStorage(buf: var InternIOBuf) =
  if buf.queueSize == buf.queueCapacity or
    (not INLINE_STORAGE and buf.queueStorage.isNil):

    let newCapacity = max(int(buf.queueCapacity) * 2, INITIAL_QUEUE_CAPACITY)
    extendQueueStorageImpl(buf, newCapacity)

template reserveQueueStorage*(buf: var InternIOBuf, size: int) =
  if buf.queueCapacity < size:
    let newCapacity = nextPowerOfTwo(size)
    extendQueueStorageImpl(buf, newCapacity)

iterator items*(buf: InternIOBuf): Region =
  for idx in 0..<buf.queueSize:
    yield buf.storage[buf.index(idx)]

iterator items*(buf: var InternIOBuf): var Region =
  for idx in 0..<buf.queueSize:
    yield buf.storage[buf.index(idx)]

proc initBuf*(result: var InternIOBuf) {.inline.} =
  result.len = 0
  result.lastChunk = nil
  result.queueSize = 0
  result.queueStart = 0
  result.queueCapacity = 2
  result.queueStorage = QueueStorage(nil)

proc `=destroy`(buf: var InternIOBuf) {.inline, raises: [Exception],
    `fix=destroy(var T)`.} =
  var lastChunk = buf.lastChunk
  while lastChunk != nil:
    lastChunk = lastChunk.dequeueChunk()

  if buf.lastChunk != nil:
    `=destroy`(buf.lastChunk)

  resetStorage(buf, 0 ..< buf.queueSize)

  if buf.queueStorage != nil:
    freeStorage(buf.queueStorage)

proc `=copy`*(buf: var InternIOBuf, b: InternIOBuf) {.inline.} =
  if buf.getAddr == b.getAddr: return

  resetStorage(buf, 0 ..< buf.queueSize)

  buf.queueSize = 0
  buf.queueStart = 0

  buf.reserveQueueStorage(b.queueSize)

  for idx in 0..<b.queueSize:
    buf.queueStorage[QueueIndex(idx)] = b.storage[b.index(idx)]

  buf.queueSize = b.queueSize

proc `=sink`*(buf: var InternIOBuf, b: InternIOBuf) {.inline.} =
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

  buf.initBuf()

  for idx in 0..<b.queueSize:
    buf.queueStorage[QueueIndex(idx)] = move b.storage[b.index(idx)]

  buf.queueSize = b.queueSize

proc extendAdjacencyRegionRight*(buf: var InternIOBuf, wirteAddr: pointer,
    size: int): bool {.inline.} =
  if buf.queueSize > 0:
    let idx = buf.index(^1)

    if wirteAddr == buf.storage[idx].rightAddr:
      inc buf.len, size
      buf.storage[idx].extendLen(size)
      result = true

proc enqueueZeroCopyRight*(buf: var InternIOBuf,
    region: sink Region) {.inline.} =
  let dataLen = region.len

  buf.extendQueueStorage()
  buf.storage[buf.index(buf.queueSize)] = move region

  inc buf.queueSize
  inc buf.len, dataLen

proc enqueueZeroCopyRight*(buf: var InternIOBuf, chunk: sink Chunk, offset,
    size: int) {.inline.} =
  assert size > 0

  buf.extendQueueStorage()
  buf.storage[buf.index(buf.queueSize)].initRegion(move chunk, offset, size)

  inc buf.queueSize
  inc buf.len, size

proc enqueueZeroCopyRight*(buf: var InternIOBuf, data: pointer,
    size: int) {.inline.} =
  assert size > 0

  var chunk = newChunk(data, size, size)

  buf.extendQueueStorage()
  buf.storage[buf.index(buf.queueSize)].initRegion(move chunk, 0, size)

  inc buf.queueSize
  inc buf.len, size

proc allocChunk*(buf: var InternIOBuf): Chunk {.inline.} =
  while true:
    result = move buf.lastChunk
    if result.isNil:
      return allocTlsChunk()

    buf.lastChunk = result.dequeueChunk()
    if not result.isFull:
      break

proc releaseChunk*(buf: var InternIOBuf, chunk: sink Chunk) {.inline.} =
  if not chunk.isFull:
    if not buf.lastChunk.isNil:
      buf.lastChunk.enqueueChunk(move chunk)
    else:
      buf.lastChunk = move chunk

proc enqueueSlowCopyRight*(buf: var InternIOBuf, data: pointer,
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

    if written >= DEFAULT_LARGE_CHUNK_SIZE and left >= DEFAULT_LARGE_CHUNK_SIZE:
      lastChunk = newChunk(DEFAULT_LARGE_CHUNK_SIZE)
    else:
      lastChunk = buf.allocChunk()

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

  buf.releaseChunk(move lastChunk)

proc dequeueAdjustLeft*(buf: var InternIOBuf,
  idx, offset, size: int) {.inline.} =

  assert size <= buf.len

  when defined(debug):
    var size2 = offset
    for idx2 in 0..<idx:
      inc size2, buf.storage[buf.index(idx2)].len
    assert size2 == size

  if offset > 0:
    buf.storage[buf.index(idx)].discardLeft(offset)

  if idx > 0:
    resetStorage(buf, 0 ..< idx)

    buf.queueStart = int32((buf.queueStart + idx) mod buf.queueCapacity)
    dec buf.queueSize, idx

  dec buf.len, size

proc dequeueAdjustRight*(buf: var InternIOBuf,
  idx, offset, size: int) {.inline.} =

  assert size <= buf.len

  when defined(debug):
    var size2 = offset
    for idx2 in idx+1..<buf.queueSize:
      inc size2, buf.storage[buf.index(idx2)].len
    assert size2 == size

  resetStorage(buf, int32(idx + 1) ..< buf.queueSize)

  buf.storage[buf.index(idx)].discardRight(offset)
  buf.queueSize = int32(idx + 1)

  dec buf.len, size

proc locate(buf: InternIOBuf,
  offset: int, reverseSearch: static[bool] = false): LocatePos {.inline.} =

  assert offset < buf.len

  var searchPos = offset
  let upperBound = buf.queueSize - 1

  for idx in 0 .. upperBound:
    when reverseSearch:
      let newIdx = upperBound - idx
    else:
      let newIdx = idx

    let dataLen = buf.storage[buf.index(newIdx)].len

    if searchPos < dataLen:
      when reverseSearch:
        result.idx = newIdx
        result.left = dataLen - searchPos
        result.right = searchPos
      else:
        result.idx = newIdx
        result.left = searchPos
        result.right = dataLen - searchPos
      return

    dec searchPos, dataLen

  assert false

proc dequeueLeft*(buf: var InternIOBuf, size: int) {.inline.} =
  if buf.queueSize > 0 and size > 0:
    if size >= buf.len:
      buf.clear()
    else:
      let locatePos = buf.locate(size)
      buf.dequeueAdjustLeft(locatePos.idx, locatePos.left, size)

proc dequeueRight*(buf: var InternIOBuf, size: int) {.inline.} =
  if buf.queueSize > 0 and size > 0:
    if size >= buf.len:
      buf.clear()
    else:
      let locatePos = buf.locate(size, reverseSearch = true)
      buf.dequeueAdjustRight(locatePos.idx, locatePos.right, size)

template `..<`*(a, b: InternPos): InternSlice =
  InternSlice(
    start: a,
    stop: b
  )

proc left*(buf: InternIOBuf): InternPos {.inline.} =
  result.idx = 0
  result.offset = 0

proc right*(buf: InternIOBuf): InternPos {.inline.} =
  if buf.queueSize > 0:
    result.idx = buf.queueSize - 1
    result.offset = buf.storage[buf.index(^1)].len

template consumeSlice*(buf: InternIOBuf, x: InternSlice, consumeBuf: untyped) =
  var idx {.inject.} = x.start.idx

  if x.start.offset > 0:
    var it {.inject.} =
      buf.storage[buf.index(idx)][x.start.offset .. ^1]
    consumeBuf

    inc idx

  while idx < x.stop.idx:
    template it: untyped {.inject.} =
      buf.storage[buf.index(idx)]
    consumeBuf

    inc idx

  if idx == x.stop.idx and x.stop.offset > 0:
    var it {.inject.} =
      buf.storage[buf.index(idx)][0 ..< x.stop.offset]
    consumeBuf

template consumeLeft*(buf, size, dequeueLeft, consumeBuf) =
  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      template it: untyped {.inject.} =
        buf.storage[buf.index(idx)]

      consumeBuf

    when dequeueLeft:
      buf.fastClear()
    return

  let locatePos = buf.locate(size)
  let rightPos = InternPos(idx: locatePos.idx, offset: locatePos.left)

  consumeSlice(buf, buf.left ..< rightPos):
    consumeBuf

  when dequeueLeft:
    buf.dequeueAdjustLeft(locatePos.idx, locatePos.left, size)

template consumeRight*(buf, size, dequeueRight, consumeBuf) =
  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      template it: untyped {.inject.} =
        buf.storage[buf.index(idx)]

      consumeBuf

    when dequeueRight:
      buf.fastClear()
    return

  let locatePos = buf.locate(size, reverseSearch = true)
  let leftPos = InternPos(idx: locatePos.idx, offset: locatePos.left)

  consumeSlice(buf, leftPos ..< buf.right):
    consumeBuf

  when dequeueRight:
    buf.dequeueAdjustRight(locatePos.idx, locatePos.right, size)
