import ./chunk
import ./indices

type Region* = object
  offset: uint32
  size: uint32
  chunk: Chunk

proc initRegion*(result: var Region, chunk: Chunk, offset, size: int) {.inline.} =
  result.size = uint32(size)
  result.offset = uint32(offset)
  result.chunk = chunk

proc initRegion*(chunk: Chunk, offset, size: int): Region {.inline.} =
  result.size = uint32(size)
  result.offset = uint32(offset)
  result.chunk = chunk

proc len*(region: Region): int {.inline.} =
  int(region.size)

proc chunk*(region: Region): Chunk {.inline.} =
  region.chunk

proc leftAddr*(region: Region): pointer {.inline.} =
  cast[pointer](cast[uint](region.chunk.leftAddr) + uint(region.offset))

proc rightAddr*(region: Region): pointer {.inline.} =
  cast[pointer](cast[uint](region.leftAddr) + uint(region.size))

proc extendLeft*(region: var Region, size: int) {.inline.} =
  dec region.offset, size

proc extendRight*(region: var Region, size: int) {.inline.} =
  inc region.size, size

proc discardLeft*(region: var Region, size: int) {.inline.} =
  dec region.size, size
  inc region.offset, size

proc discardRight*(region: var Region, size: int) {.inline.} =
  dec region.size, size

template toOpenArray*(region: Region): openArray[byte] =
  cast[ptr UncheckedArray[byte]](region.leftAddr).toOpenArray(0, int(region.size) - 1)

proc `[]`*[U, V: Ordinal](region: Region, x: HSlice[U, V]): Region {.inline.} =
  let a = region ^^ x.a
  let L = (region ^^ x.b) - a + 1

  checkSliceOp(region.len, a, a + L)

  result.initRegion(region.chunk, int(region.offset) + a, L)
