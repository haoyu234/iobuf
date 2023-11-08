import chunk
import indices

const DEFAULT_CHUNK_SIZE* = 8192
const DEFAULT_LARGE_CHUNK_SIZE* = DEFAULT_CHUNK_SIZE * 4

type
  Region* = object
    offset: int32
    len: int32
    chunk: Chunk

template initRegion*(result: var Region,
  chunk2: Chunk, offset2, size2: int) =
  result.len = int32(size2)
  result.offset = int32(offset2)
  result.chunk = chunk2

template len*(region: Region): int =
  int(region.len)

template chunk*(region: Region): Chunk =
  region.chunk

template leftAddr*(region: Region): pointer =
  cast[pointer](cast[uint](region.chunk.leftAddr) + uint(region.offset))

template rightAddr*(region: Region): pointer =
  cast[pointer](cast[uint](region.leftAddr) + uint(region.len))

template extendLen*(region: var Region, size: int) =
  inc region.len, size

template discardLeft*(region: var Region, size: int) =
  inc region.offset, size
  dec region.len, size

template discardRight*(region: var Region, size: int) =
  dec region.len, size

template toOpenArray*(region: Region): openArray[byte] =
  cast[ptr UncheckedArray[byte]](region.leftAddr).toOpenArray(0, region.len - 1)

proc `[]`*[U, V: Ordinal](region: Region, x: HSlice[U, V]): Region {.inline.} =

  let a = region ^^ x.a
  let L = (region ^^ x.b) - a + 1

  checkSliceOp(region.len, a, a + L)

  result.initRegion(
    region.chunk,
    int32(region.offset + a),
    int32(L),
  )
