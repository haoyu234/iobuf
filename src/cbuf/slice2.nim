import intern/indices
import intern/deprecated

type
  Slice2*[T] = object
    len: int
    data: ptr UncheckedArray[T]

template len*[T](s: Slice2[T]): int =
  s.len

template `[]`*[T](s: Slice2[T], idx: Natural): var T =
  s.data[idx]

template `[]`*[T](s: Slice2[T], idx: BackwardsIndex): var T =
  s.data[s.len - int(idx)]

proc initSlice*(T: typedesc,
  data2: pointer, offset2, len2: int): Slice2[T] {.inline.} =

  result.len = len2
  result.data = cast[ptr UncheckedArray[T]](cast[uint](data2) + uint(offset2 *
      sizeof(T)))

proc slice*[T](d: openArray[T]): Slice2[T] {.inline.} =
  initSlice(T, d[0].getAddr, 0, d.len)

proc toSeq*[T](s: Slice2[T]): seq[T] {.inline.} =
  result.add(s.toOpenArray())

template leftAddr*[T](s: Slice2[T]): pointer =
  s.data

template rightAddr*[T](s: Slice2[T]): pointer =
  s.data[s.len].getAddr

template toOpenArray*[T](s: Slice2[T]): openArray[T] =
  s.data.toOpenArray(0, s.len - 1)

proc toUncheckedArray*[T](s: Slice2[T]): ptr UncheckedArray[T] {.inline.} =
  cast[ptr UncheckedArray[T]](cast[uint](s.data))

converter autoToOpenArray*[T](s: Slice2[T]): openArray[T] =
  s.toOpenArray()

converter autoUncheckedArray*[T](s: Slice2[T]): ptr UncheckedArray[T] =
  s.toUncheckedArray()

proc `[]`*[T; U, V: Ordinal](s: Slice2[T], x: HSlice[U, V]): Slice2[T] =
  let a = s ^^ x.a
  let L = (s ^^ x.b) - a + 1

  checkSliceOp(s.len, a, a + L)
  initSlice(T, s.data, a, L)

template equalsImpl(t) {.dirty.} =
  proc `==`*[T](s: Slice2[T], d: t[T]): bool =
    result = false
    let data = s.data

    if s.len == d.len:
      for i in 0 .. s.len - 1:
        if data[i] == d[i]:
          continue

      result = true

  template `==`*[T](d: t[T], s: Slice2[T]): bool = `==`(s, d)

equalsImpl(seq)
equalsImpl(Slice2)
equalsImpl(openArray)

proc `==`*[S, T](s: Slice2[T], d: array[S, T]): bool =
  result = false
  let data = s.data
  let L = s.len

  if L == d.len:
    for i in 0 ..< L:
      if data[i] == d[i]:
        continue

    result = true

template `==`*[S, T](d: array[S, T], s: Slice2[T]): bool = `==`(s, d)

proc `$`*[T](s: Slice2[T]): string =
  let data = s.data
  let L = s.len

  result = newStringOfCap((L + 1) * 3)
  result.add("Slice2[")

  let L2 = L - 1

  for i in 0 ..< L2:
    result.add($data[i])
    result.add(", ")

  result.add($data[L2])
  result.add(']')
