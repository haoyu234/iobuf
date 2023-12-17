const DEFAULT_CHUNK_SIZE* = 8192
const DEFAULT_LARGE_CHUNK_SIZE* = DEFAULT_CHUNK_SIZE * 4

type
  ChunkObj* {.acyclic.} = object of RootObj
    len: int
    capacity: int
    storage: pointer
    nextChunk: Chunk

  Chunk* = ref ChunkObj
  ChunkObj2 = object of ChunkObj
  Chunk2 = ref ChunkObj2

  Chunk3 = ref ChunkObj3
  ChunkObj3 = object of ChunkObj
    data: seq[byte]

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

template leftSpace*(chunk: Chunk): int =
  int(chunk.capacity - chunk.len)

template writeAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.len))

template leftAddr*(chunk: Chunk): pointer =
  chunk.storage

template rightAddr*(chunk: Chunk): pointer =
  cast[pointer](cast[uint](chunk.storage) + uint(chunk.capacity))

template advanceWpos*(chunk: Chunk, dataLen: int) =
  assert dataLen <= chunk.leftSpace()

  inc chunk.len, dataLen

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

template toOpenArray*(chunk: Chunk): openArray[byte] =
  cast[ptr UncheckedArray[byte]](chunk.storage).toOpenArray(0, chunk.len - 1)
