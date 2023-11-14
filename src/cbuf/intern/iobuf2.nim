import std/math
import std/typetraits

import tls
import chunk
import region
import deprecated

const USE_STD_DEQUE = false

when USE_STD_DEQUE:
  import std/deques
else:
  import deque

type
  InternIOBuf* = object
    len: int
    lastChunk: Chunk
    queuedRegion: Deque[Region]

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
template queueSize*(buf: InternIOBuf): int = buf.queuedRegion.len

template clear*(buf: var InternIOBuf) =
  if buf.len > 0:
    buf.len = 0
    buf.queuedRegion.clear

iterator items*(buf: InternIOBuf): lent Region =
  for region in buf.queuedRegion:
    yield region

proc initBuf*(result: var InternIOBuf) {.inline.} =
  result.len = 0
  result.lastChunk = nil

proc `=destroy`(buf: var InternIOBuf) {.`fix=destroy(var T)`.} =
  var lastChunk = buf.lastChunk
  while lastChunk != nil:
    lastChunk = lastChunk.dequeueChunk()

  `=destroy`(buf.lastChunk)
  `=destroy`(buf.queuedRegion.getAddr[])

proc extendAdjacencyRegionRight*(buf: var InternIOBuf, wirteAddr: pointer,
    size: int): bool {.inline.} =
  if buf.queueSize > 0:
    if wirteAddr == buf.queuedRegion[^1].rightAddr:
      inc buf.len, size
      buf.queuedRegion[^1].extendLen(size)
      result = true

proc enqueueZeroCopyRight*(buf: var InternIOBuf,
    region: sink Region) {.inline.} =

  inc buf.len, region.len
  buf.queuedRegion.addLast(move region)

proc enqueueZeroCopyRight*(buf: var InternIOBuf, chunk: sink Chunk, offset,
    size: int) {.inline.} =
  assert size > 0

  var region: Region
  region.initRegion(move chunk, offset, size)

  inc buf.len, region.len
  buf.queuedRegion.addLast(move region)

proc enqueueZeroCopyRight*(buf: var InternIOBuf, data: pointer,
    size: int) {.inline.} =
  assert size > 0

  var region: Region
  region.initRegion(newChunk(data, size, size), 0, size)

  inc buf.len, region.len
  buf.queuedRegion.addLast(move region)

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

  if offset > 0:
    buf.queuedRegion[idx].discardLeft(offset)

  for idx2 in 0..<idx:
    discard buf.queuedRegion.popFirst()

  dec buf.len, size

proc dequeueAdjustRight*(buf: var InternIOBuf,
  idx, offset, size: int) {.inline.} =

  assert size <= buf.len

  if offset > 0:
    buf.queuedRegion[idx].discardRight(offset)

  for idx2 in (idx + 1) ..< buf.queueSize:
    discard buf.queuedRegion.popLast()

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

proc dequeueLeft*(buf: var InternIOBuf, size: int) {.inline.} =
  if buf.len > 0 and size > 0:
    if size >= buf.len:
      buf.clear()
    else:
      let locatePos = buf.locate(size)
      buf.dequeueAdjustLeft(locatePos.idx, locatePos.left, size)

proc dequeueRight*(buf: var InternIOBuf, size: int) {.inline.} =
  if buf.len > 0 and size > 0:
    if size >= buf.len:
      buf.clear()
    else:
      let locatePos = buf.locate(size, reverseSearch = true)
      buf.dequeueAdjustRight(locatePos.idx, locatePos.right, size)

template consumeRange*(buf: InternIOBuf, start, stop: InternPos,
    consumeBuf: untyped) =
  block consumeRangeScope:
    var idx {.inject.} = start.idx

    if idx == stop.idx:
      var it {.inject.} =
        buf.queuedRegion[idx][start.offset ..< stop.offset]
      consumeBuf

      break consumeRangeScope

    if start.offset > 0:
      var it {.inject.} =
        buf.queuedRegion[idx][start.offset .. ^1]
      consumeBuf

      inc idx

    while idx < stop.idx:
      template it: untyped {.inject.} =
        buf.queuedRegion[idx]
      consumeBuf

      inc idx

    if stop.offset > 0:
      var it {.inject.} =
        buf.queuedRegion[idx][0 ..< stop.offset]
      consumeBuf

template consumeLeft*(buf, size, dequeueLeft, consumeBuf) =
  block consumeLeftScope:
    if size >= buf.len:
      for idx in 0 ..< buf.queueSize:
        template it: untyped {.inject.} =
          buf.queuedRegion[idx]

        consumeBuf

      when dequeueLeft:
        buf.clear()

      break consumeLeftScope

    let locatePos = buf.locate(size)
    let leftPos = InternPos(idx: 0, offset: 0)
    let rightPos = InternPos(idx: locatePos.idx, offset: locatePos.left)

    consumeRange(buf, leftPos, rightPos):
      consumeBuf

    when dequeueLeft:
      buf.dequeueAdjustLeft(locatePos.idx, locatePos.left, size)

template consumeRight*(buf, size, dequeueRight, consumeBuf) =
  block consumeRightScope:
    if size >= buf.len:
      for idx in 0 ..< buf.queueSize:
        template it: untyped {.inject.} =
          buf.queuedRegion[idx]

        consumeBuf

      when dequeueRight:
        buf.clear()

      break consumeRightScope

    let locatePos = buf.locate(size, reverseSearch = true)
    let leftPos = InternPos(idx: locatePos.idx, offset: locatePos.left)
    let rightPos = InternPos(idx: buf.queueSize - 1, offset: buf.queuedRegion[^1].len)

    consumeRange(buf, leftPos, rightPos):
      consumeBuf

    when dequeueRight:
      buf.dequeueAdjustRight(locatePos.idx, locatePos.right, size)
