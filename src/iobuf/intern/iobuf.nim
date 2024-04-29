import std/deques
import std/strformat

import ./chunk
import ./region
import ../slice2

type InternalIOBuf* = object
  len: int
  lastChunk: Chunk
  queuedRegion: Deque[Region]

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

proc `=sink`(buf: var InternalIOBuf, b: InternalIOBuf) =
  `=destroy`(buf)

  buf.len = b.len
  buf.lastChunk = b.lastChunk

  `=sink`(buf.queuedRegion, b.queuedRegion)

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

proc dequeueLeft*(buf: var InternalIOBuf, size: int) =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    buf.clear()
    return

  var searchPos = size

  for idx in 0 ..< buf.queueSize:
    let region = buf.queuedRegion[0].addr

    if searchPos < region[].len:
      if searchPos > 0:
        region[].discardLeft(searchPos)
      break

    dec searchPos, region[].len
    discard buf.queuedRegion.popFirst()

  dec buf.len, size

proc dequeueRight*(buf: var InternalIOBuf, size: int) =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    buf.clear()
    return

  var searchPos = size

  for idx in 0 ..< buf.queueSize:
    let region = buf.queuedRegion[^1].addr

    if searchPos < region[].len:
      if searchPos > 0:
        region[].discardRight(searchPos)
      break

    dec searchPos, region[].len
    discard buf.queuedRegion.popLast()

  dec buf.len, size

iterator visitLeft*(buf: InternalIOBuf, size: int): Slice2[byte] =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      yield buf.queuedRegion[idx].toOpenArray.slice
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let region = buf.queuedRegion[idx].addr

      if searchPos < region[].len:
        if searchPos > 0:
          yield region[].toOpenArray.slice(0, searchPos)
        break

      dec searchPos, region[].len

      yield region[].toOpenArray.slice

iterator visitLeftAndDequeue*(buf: var InternalIOBuf, size: int): Slice2[byte] =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    while buf.queueSize > 0:
      let region = buf.queuedRegion.popFirst()
      dec buf.len, region.len
      yield region.toOpenArray.slice
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let len = buf.queuedRegion[0].len

      if searchPos < len:
        if searchPos > 0:
          dec buf.len, searchPos
          var r = buf.queuedRegion[0].toOpenArray.slice(0, searchPos)
          buf.queuedRegion[0].discardLeft(searchPos)
          yield r
        break

      dec buf.len, len
      dec searchPos, len

      let region = buf.queuedRegion.popFirst()
      yield region.toOpenArray.slice

iterator visitLeftRegion*(buf: InternalIOBuf, size: int): Region =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    for idx in 0 ..< buf.queueSize:
      yield buf.queuedRegion[idx]
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let region = buf.queuedRegion[idx].addr

      if searchPos < region[].len:
        if searchPos > 0:
          yield region[][0 ..< searchPos]
        break

      dec searchPos, region[].len

      yield region[]

iterator visitLeftRegionAndDequeue*(buf: var InternalIOBuf, size: int): Region =
  assert size > 0
  assert size <= buf.len

  if size >= buf.len:
    while buf.queueSize > 0:
      dec buf.len, buf.queuedRegion[0].len
      yield buf.queuedRegion.popFirst()
  else:
    var searchPos = size

    for idx in 0 ..< buf.queueSize:
      let len = buf.queuedRegion[0].len

      if searchPos < len:
        if searchPos > 0:
          dec buf.len, searchPos
          var region = buf.queuedRegion[0][0 ..< searchPos]
          buf.queuedRegion[0].discardLeft(searchPos)
          yield move region
        break

      dec buf.len, len
      dec searchPos, len

      yield buf.queuedRegion.popFirst()

proc `$`*(buf: InternalIOBuf): string {.inline.} =
  result = fmt"IOBuf(len: {buf.len}, queueSize: {buf.queueSize}, queuedRegion: ["
  for i, region in buf.queuedRegion.pairs:
    if i != 0:
      result.add(", ")
    result.addQuoted(region)
  result.add("])")
