import std/typetraits

import region
import alloc

type
  QueueIndex* = distinct int
  QueueStorage* = distinct ptr UncheckedArray[Region]

template `[]`*(storage: QueueStorage, index: QueueIndex): var Region =
  distinctBase(storage)[distinctBase(index)]

template `[]=`*(storage: QueueStorage, index: QueueIndex, data: Region) =
  distinctBase(storage)[distinctBase(index)] = data

converter autoToPointer*(storage: QueueStorage): pointer {.inline.} =
  cast[pointer](distinctBase(storage))

template allocStorage*(capacity: int): QueueStorage =
  cast[QueueStorage](c_calloc(csize_t(sizeof(Region)), csize_t(capacity)))

template freeStorage*(storage: QueueStorage) =
  c_free(storage)
