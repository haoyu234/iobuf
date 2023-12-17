import ./chunk
import ./region
import ./deque

type
  InternalIOBuf* = object
    len: int
    lastChunk: Chunk
    queuedRegion: Deque[Region]

  LocatePos = object
    idx: int
    left: int
    right: int

  InternalPos = object
    idx: int
    offset: int

template len*(buf: InternalIOBuf): int =
  buf.len

template queueSize*(buf: InternalIOBuf): int =
  buf.queuedRegion.len

template clear*(buf: var InternalIOBuf) =
  if buf.len > 0:
    buf.len = 0
    buf.queuedRegion.clear

iterator items*(buf: InternalIOBuf): lent Region =
  for region in buf.queuedRegion:
    yield region

proc `=destroy`(buf: InternalIOBuf) =
  var last = buf.lastChunk
  while not last.isNil:
    discard last.dequeue

  `=destroy`(buf.lastChunk)
  `=destroy`(buf.queuedRegion.addr[])

proc `=copy`(buf: var InternalIOBuf, b: InternalIOBuf) =
  if b.len <= 0:
    return

  buf.len = b.len
  `=copy`(buf.queuedRegion, b.queuedRegion)

proc allocChunk*(buf: var InternalIOBuf): Chunk {.inline.} =
  result = buf.lastChunk.dequeue

  if result.isNil:
    result = newChunk(DEFAULT_CHUNK_SIZE)

iterator allocChunkMany*(buf: var InternalIOBuf, size: int): owned Chunk =
  var left = size

  while left > 0:
    let total = size - left
    if total >= DEFAULT_LARGE_CHUNK_SIZE and left >= DEFAULT_LARGE_CHUNK_SIZE:
      let chunk = newChunk(DEFAULT_LARGE_CHUNK_SIZE)
      dec left, DEFAULT_LARGE_CHUNK_SIZE
      yield chunk
    else:
      let chunk = buf.allocChunk()
      dec left, chunk.leftSpace
      yield chunk

proc releaseChunk*(buf: var InternalIOBuf, chunk: sink Chunk) {.inline.} =
  if not chunk.isFull:
    buf.lastChunk.enqueue(chunk)

iterator preprocessingEnqueueSlowCopy(
    buf: var InternalIOBuf, data: pointer, size: int
): Region =
  assert size > 0

  var offset = 0
  var lastChunk = Chunk(nil)

  for chunk in buf.allocChunkMany(size):
    let leftAddr = chunk.leftAddr
    let oldOffset = chunk.len

    let len = min(size - offset, chunk.leftSpace)
    let dstAddr = cast[pointer](cast[uint](leftAddr) + uint(oldOffset))
    let srcAddr = cast[pointer](cast[uint](data) + uint(offset))

    copyMem(dstAddr, srcAddr, len)

    inc offset, len
    lastChunk = chunk

    chunk.advanceWpos(len)

    yield initRegion(chunk, oldOffset, len)

  assert lastChunk != nil

  buf.releaseChunk(move lastChunk)

proc preprocessingEnqueueOneByte(
    buf: var InternalIOBuf, data: byte
): Region {.inline.} =
  var lastChunk = buf.allocChunk()
  let len = lastChunk.len
  let dstAddr = cast[pointer](cast[uint](lastChunk.leftAddr) + uint(len))
  cast[ptr byte](dstAddr)[] = data

  lastChunk.advanceWpos(1)

  buf.releaseChunk(lastChunk)

  initRegion(move lastChunk, len, 1)

proc enqueueLeftZeroCopy*(buf: var InternalIOBuf, data: InternalIOBuf) {.inline.} =
  inc buf.len, data.len

  for i in countdown(data.queueSize - 1, 0):
    buf.queuedRegion.addFirst(data.queuedRegion[i])

proc enqueueLeftZeroCopy*(buf: var InternalIOBuf, region: sink Region) {.inline.} =
  inc buf.len, region.len

  if buf.queueSize > 0:
    let head = buf.queuedRegion[0].addr
    if head[].chunk == region.chunk and head[].leftAddr == region.rightAddr:
      head[].extendLeft(region.len)
      return

  buf.queuedRegion.addFirst(move region)

proc enqueueLeftCopy*(buf: var InternalIOBuf, data: pointer, size: int) {.inline.} =
  for region in buf.preprocessingEnqueueSlowCopy(data, size):
    buf.enqueueLeftZeroCopy(region)

proc enqueueByteLeft*(buf: var InternalIOBuf, data: byte) {.inline.} =
  var region = buf.preprocessingEnqueueOneByte(data)
  buf.enqueueLeftZeroCopy(move region)

proc enqueueRightZeroCopy*(buf: var InternalIOBuf, data: InternalIOBuf) {.inline.} =
  inc buf.len, data.len

  for region in data.queuedRegion:
    buf.queuedRegion.addLast(region)

proc enqueueRightZeroCopy*(buf: var InternalIOBuf, region: sink Region) {.inline.} =
  inc buf.len, region.len

  if buf.queueSize > 0:
    let tail = buf.queuedRegion[^1].addr
    if tail[].chunk == region.chunk and tail[].rightAddr == region.leftAddr:
      tail[].extendRight(region.len)
      return

  buf.queuedRegion.addLast(move region)

proc enqueueRightCopy*(buf: var InternalIOBuf, data: pointer, size: int) {.inline.} =
  for region in buf.preprocessingEnqueueSlowCopy(data, size):
    buf.enqueueRightZeroCopy(region)

proc enqueueByteRight*(buf: var InternalIOBuf, data: byte) {.inline.} =
  var region = buf.preprocessingEnqueueOneByte(data)
  buf.enqueueRightZeroCopy(move region)

proc dequeueLeftAdjust*(buf: var InternalIOBuf, idx, offset, size: int) {.inline.} =
  assert size <= buf.len

  if offset > 0:
    buf.queuedRegion[idx].discardLeft(offset)

  for idx2 in 0 ..< idx:
    discard buf.queuedRegion.popFirst()

  dec buf.len, size

proc dequeueRightAdjust*(buf: var InternalIOBuf, idx, offset, size: int) {.inline.} =
  assert size <= buf.len

  if offset > 0:
    buf.queuedRegion[idx].discardRight(offset)

  for idx2 in (idx + 1) ..< buf.queueSize:
    discard buf.queuedRegion.popLast()

  dec buf.len, size

proc locate(
    buf: InternalIOBuf, offset: int, reverseSearch: static[bool] = false
): LocatePos {.inline.} =
  assert offset < buf.len

  var searchPos = offset
  let upperBound = buf.queueSize - 1

  for idx in 0 .. upperBound:
    when reverseSearch:
      let newIdx = upperBound - idx
    else:
      let newIdx = idx

    let dataLen = buf.queuedRegion[newIdx].len

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

proc dequeueLeft*(buf: var InternalIOBuf, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    buf.clear()
    return

  if size == 1:
    dec buf.len, 1

    let region = buf.queuedRegion[0].addr
    if region[].len > 1:
      region[].discardLeft(1)
      return

    discard buf.queuedRegion.popFirst()
    return

  let locatePos = buf.locate(size)
  buf.dequeueLeftAdjust(locatePos.idx, locatePos.left, size)

proc dequeueRight*(buf: var InternalIOBuf, size: int) {.inline.} =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    buf.clear()
    return

  if size == 1:
    dec buf.len, 1

    let region = buf.queuedRegion[^1].addr
    if region[].len > 1:
      region[].discardRight(1)
      return

    discard buf.queuedRegion.popLast()
    return

  let locatePos = buf.locate(size, reverseSearch = true)
  buf.dequeueRightAdjust(locatePos.idx, locatePos.right, size)

iterator visitRegion*(buf: InternalIOBuf, start, stop: InternalPos): Region =
  var idx {.inject.} = start.idx

  if idx != stop.idx:
    if start.offset > 0:
      yield buf.queuedRegion[idx][start.offset .. ^1]

      inc idx

    while idx < stop.idx:
      yield buf.queuedRegion[idx]

      inc idx

    if stop.offset > 0:
      yield buf.queuedRegion[idx][0 ..< stop.offset]
  else:
    yield buf.queuedRegion[idx][start.offset ..< stop.offset]

template visitLeftRegionImpl(
    buf: InternalIOBuf, size: int, dequeue: static[bool] = false
) =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      yield buf.queuedRegion[idx]

    when dequeue:
      buf.clear()
  else:
    let locatePos = buf.locate(size)
    let leftPos = InternalPos(idx: 0, offset: 0)
    let rightPos = InternalPos(idx: locatePos.idx, offset: locatePos.left)

    for region in buf.visitRegion(leftPos, rightPos):
      yield region

    when dequeue:
      buf.dequeueLeftAdjust(locatePos.idx, locatePos.left, size)

iterator visitLeftRegion*(buf: InternalIOBuf, size: int): Region =
  buf.visitLeftRegionImpl(size)

iterator visitLeftRegionAndDequeue*(buf: var InternalIOBuf, size: int): Region =
  buf.visitLeftRegionImpl(size, dequeue = true)

template visitRightRegionImpl(
    buf: InternalIOBuf, size: int, dequeue: static[bool] = false
) =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      yield buf.queuedRegion[idx]

    when dequeue:
      buf.clear()
  else:
    let locatePos = buf.locate(size, reverseSearch = true)
    let leftPos = InternalPos(idx: locatePos.idx, offset: locatePos.left)
    let rightPos = InternalPos(idx: buf.queueSize - 1, offset: buf.queuedRegion[^1].len)

    for region in buf.visitRegion(leftPos, rightPos):
      yield region

    when dequeue:
      buf.dequeueRightAdjust(locatePos.idx, locatePos.right, size)

iterator visitRightRegion*(buf: InternalIOBuf, size: int): Region =
  buf.visitRightRegionImpl(size)

iterator visitRightRegionAndDequeue*(buf: var InternalIOBuf, size: int): Region =
  buf.visitRightRegionImpl(size, dequeue = true)

proc debugDump*(buf: InternalIOBuf) =
  if buf.len <= 0:
    return

  let leftPos = InternalPos(idx: 0, offset: 0)
  let rightPos = InternalPos(idx: buf.queueSize - 1, offset: buf.queuedRegion[^1].len)

  for region in buf.visitRegion(start = leftPos, stop = rightPos):
    debugEcho region.toOpenArray
