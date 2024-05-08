import std/strformat

import ./indices

const DEFAULT_CHUNK_SIZE* = 8192
const DEFAULT_LARGE_CHUNK_SIZE* = DEFAULT_CHUNK_SIZE * 4

type
  ChunkBase* {.acyclic.} = object of RootObj
    len: int
    capacity: int
    storage: pointer
    nextChunk: Chunk

  Chunk* = ref ChunkBase
  ChunkObj2 = object of ChunkBase
  Chunk2 = ref ChunkObj2

  Chunk3 = ref ChunkObj3
  ChunkObj3 = object of ChunkBase
    data: seq[byte]

  Region* = object
    offset: uint32
    len: uint32
    chunk: Chunk

proc `=destroy`(chunk: ChunkObj2) =
  let storage = chunk.storage
  if not storage.isNil:
    deallocShared(storage)

proc newChunk*(storage: pointer, len, capacity: int): owned Chunk {.inline.} =
  var chunk = new(Chunk)

  chunk.len = len
  chunk.capacity = capacity
  chunk.storage = storage

  chunk

proc newChunk*(capacity: int): owned Chunk {.inline.} =
  var chunk = new(Chunk2)

  chunk.len = 0
  chunk.capacity = capacity
  chunk.storage = allocShared(capacity)

  chunk

proc newChunk*(data: sink seq[byte]): owned Chunk {.inline.} =
  var chunk = new(Chunk3)

  chunk.len = data.len
  chunk.capacity = data.len
  chunk.data = move data
  chunk.storage = chunk.data[0].addr

  chunk

template len*(chunk: Chunk): int =
  chunk.len

template isFull*(chunk: Chunk): bool =
  chunk.len >= chunk.capacity

template storage*(chunk: Chunk): pointer =
  chunk.storage

template freeSpace*(chunk: Chunk): int =
  int(chunk.capacity - chunk.len)

template writeAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.len))

template leftAddr*(chunk: Chunk): pointer =
  chunk.storage

template rightAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.capacity))

template advanceWpos*(chunk: Chunk, size: int) =
  assert size <= chunk.freeSpace()

  inc chunk.len, size

proc advanceWposRegion*(chunk: Chunk, size: int): Region {.inline.} =
  assert size >= 0

  result.chunk = chunk
  result.offset = uint32(chunk.len)
  result.len = uint32(size)

  chunk.advanceWpos(size)

proc region*(chunk: Chunk): Region {.inline.} =
  result.chunk = chunk
  result.offset = 0
  result.len = uint32(chunk.len)

proc region*(chunk: Chunk, offset, len: int): Region {.inline.} =
  assert len >= 0
  assert offset >= 0
  assert offset + len <= chunk.len

  result.chunk = chunk
  result.offset = 0
  result.len = uint32(chunk.len)

template capacity*(chunk: Chunk): int =
  chunk.capacity

template enqueue*(chunk: var Chunk, next: Chunk) =
  next.nextChunk = chunk
  chunk = next

template dequeue*(chunk: var Chunk): Chunk =
  var result = move chunk
  if not result.isNil:
    chunk = result.nextChunk
  result

proc `$`*(chunk: Chunk): string {.inline.} =
  fmt"Chunk(len: {chunk.len}, capacity: {chunk.capacity}, storage: {cast[uint](chunk.storage)})"

template toOpenArray*(chunk: Chunk): openArray[byte] =
  cast[ptr UncheckedArray[byte]](chunk.storage).toOpenArray(0, chunk.len - 1)

template len*(region: Region): int =
  int(region.len)

template chunk*(region: Region): Chunk =
  region.chunk

template leftAddr*(region: Region): pointer =
  cast[pointer](cast[uint](region.chunk.leftAddr) + uint(region.offset))

template rightAddr*(region: Region): pointer =
  cast[pointer](cast[uint](region.leftAddr) + uint(region.len))

template extendLeft*(region: var Region, size: int) =
  dec region.offset, size

template extendRight*(region: var Region, size: int) =
  inc region.len, size

template discardLeft*(region: var Region, size: int) =
  dec region.len, size
  inc region.offset, size

template discardRight*(region: var Region, size: int) =
  dec region.len, size

template toOpenArray*(region: Region): openArray[byte] =
  cast[ptr UncheckedArray[byte]](region.leftAddr).toOpenArray(0, int(
      region.len) - 1)

proc `[]`*[U, V: Ordinal](region: Region, x: HSlice[U, V]): Region {.inline.} =
  let a = region ^^ x.a
  let L = (region ^^ x.b) - a + 1

  checkSliceOp(int(region.len), a, a + L)

  result.chunk = region.chunk
  result.offset = uint32(int(region.offset) + a)
  result.len = uint32(L)
