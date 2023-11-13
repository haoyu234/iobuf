import std/typetraits
import system/ansi_c

import region

type
  StorageIndex* = distinct int
  Storage*[T] = distinct ptr UncheckedArray[T]

template `[]`*[T](storage: Storage[T], index: StorageIndex): var T =
  distinctBase(storage)[distinctBase(index)]

template `[]=`*[T](storage: Storage[T], index: StorageIndex, data: T) =
  distinctBase(storage)[distinctBase(index)] = data

converter autoToPointer*[T](storage: Storage[T]): pointer {.inline.} =
  cast[pointer](distinctBase(storage))

template allocStorage*[T](capacity: int): Storage[T] =
  cast[Storage[T]](c_calloc(csize_t(sizeof(T)), csize_t(capacity)))

template freeStorage*[T](storage: Storage[T]) =
  c_free(storage)
