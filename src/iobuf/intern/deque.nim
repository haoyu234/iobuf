import std/math
import system/ansi_c

import deprecated

const INLINE_STORAGE_CAPACITY = 2
const DEFAULT_STORAGE_CAPACITY = 32

type
  Deque*[T] = object
    len, head, tail, mask: int
    data: pointer
    inlineStorage: array[INLINE_STORAGE_CAPACITY, T]

template allocStorage[T](capacity: int): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](c_calloc(csize_t(sizeof(T)), csize_t(capacity)))

template freeStorage(storage: pointer) =
  c_free(storage)

template initImpl(result: typed, initSize: int) =
  if initSize > INLINE_STORAGE_CAPACITY:
    let cap = if initSize > DEFAULT_STORAGE_CAPACITY:
      nextPowerOfTwo(initSize)
    else:
      DEFAULT_STORAGE_CAPACITY

    result.mask = cap - 1
    result.data = allocStorage[T](cap)
  else:
    result.mask = 1
    result.data = cast[ptr UncheckedArray[T]](deq.inlineStorage[0].getAddr)

template checkIfInitialized(deq: typed) =
  if deq.mask == 0:
    initImpl(deq, INLINE_STORAGE_CAPACITY)

template storage[T](deq: Deque[T]): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](deq.data)

template destroy(x: untyped) =
  reset(x)

template checkAndFreeStorage[T](deq: Deque[T]) =
  let inlineStorage = deq.inlineStorage[0].getAddr
  if deq.data != inlineStorage:
    freeStorage(deq.data)

proc `=destroy`*[T](deq: var Deque[T]) {.inline, `fix=destroy(var T)`.} =
  if deq.data.isNil:
    return

  var i = deq.head
  for _ in 0 ..< deq.len:
    destroy(deq.storage[i])
    i = (i + 1) and deq.mask

  checkAndFreeStorage(deq)

proc `=sink`*[T](deq: var Deque[T], source: Deque[T]) {.inline.} =
  if not deq.data.isNil:
    `=destroy`(deq)

  deq.len = source.len
  deq.head = source.head
  deq.tail = source.tail
  deq.mask = source.mask

  let inlineStorage = source.inlineStorage[0].getAddr
  if source.data != inlineStorage:
    deq.data = source.data
    return

  deq.data = deq.inlineStorage[0].getAddr

  var i = source.head
  for c in 0 ..< source.len:
    deq.storage[c] = move source.storage[i]
    i = (i + 1) and source.mask

proc `=copy`*[T](deq: var Deque[T], source: Deque[T]) {.inline.} =
  if deq.data != source.data:
    `=destroy`(deq)

    deq.len = source.len
    deq.head = 0
    deq.tail = 0
    initImpl(deq, source.len)

    var i = source.head
    for c in 0 ..< source.len:
      deq.storage[c] = source.storage[i]
      i = (i + 1) and source.mask

proc initDeque*[T](deq: var Deque[T],
  initSize: int = INLINE_STORAGE_CAPACITY) {.inline.} =

  initImpl(deq, initSize)

proc len*[T](deq: Deque[T]): int {.inline.} =
  result = deq.len

template emptyCheck(deq) =
  # Bounds check for the regular deque access.
  when compileOption("boundChecks"):
    if unlikely(deq.len < 1):
      raise newException(IndexDefect, "Empty deque.")

template xBoundsCheck(deq, i) =
  # Bounds check for the array like accesses.
  when compileOption("boundChecks"): # `-d:danger` or `--checks:off` should disable this.
    if unlikely(i >= deq.len): # x < deq.low is taken care by the Natural parameter
      raise newException(IndexDefect,
                         "Out of bounds: " & $i & " > " & $(deq.len - 1))
    if unlikely(i < 0): # when used with BackwardsIndex
      raise newException(IndexDefect,
                         "Out of bounds: " & $i & " < 0")

proc `[]`*[T](deq: Deque[T], i: Natural): lent T {.inline.} =
  xBoundsCheck(deq, i)
  deq.storage[(deq.head + i) and deq.mask]

proc `[]`*[T](deq: var Deque[T], i: Natural): var T {.inline.} =
  xBoundsCheck(deq, i)
  deq.storage[(deq.head + i) and deq.mask]

proc `[]=`*[T](deq: var Deque[T], i: Natural, val: sink T) {.inline.} =
  checkIfInitialized(deq)
  xBoundsCheck(deq, i)
  deq.storage[(deq.head + i) and deq.mask] = move val

proc `[]`*[T](deq: Deque[T], i: BackwardsIndex): lent T {.inline.} =
  xBoundsCheck(deq, deq.len - int(i))
  deq[deq.len - int(i)]

proc `[]`*[T](deq: var Deque[T], i: BackwardsIndex): var T {.inline.} =
  xBoundsCheck(deq, deq.len - int(i))
  deq[deq.len - int(i)]

proc `[]=`*[T](deq: var Deque[T], i: BackwardsIndex, x: sink T) {.inline.} =
  checkIfInitialized(deq)
  xBoundsCheck(deq, deq.len - int(i))
  deq[deq.len - int(i)] = move x

iterator items*[T](deq: Deque[T]): lent T =
  var i = deq.head
  for c in 0 ..< deq.len:
    yield deq.storage[i]
    i = (i + 1) and deq.mask

iterator mitems*[T](deq: var Deque[T]): var T =
  var i = deq.head
  for c in 0 ..< deq.len:
    yield deq.storage[i]
    i = (i + 1) and deq.mask

iterator pairs*[T](deq: Deque[T]): tuple[key: int, val: T] =
  var i = deq.head
  for c in 0 ..< deq.len:
    yield (c, deq.storage[i])
    i = (i + 1) and deq.mask

proc expandIfNeeded[T](deq: var Deque[T]) =
  checkIfInitialized(deq)
  var cap = deq.mask + 1
  if unlikely(deq.len >= cap):
    var n = allocStorage[T](cap * 2)
    var i = 0
    for x in mitems(deq):
      when nimvm: n[i] = x # workaround for VM bug
      else: n[i] = move(x)
      inc i

    checkAndFreeStorage(deq)

    deq.data = n
    deq.mask = cap * 2 - 1
    deq.tail = deq.len
    deq.head = 0

proc addFirst*[T](deq: var Deque[T], item: sink T) =
  expandIfNeeded(deq)
  inc deq.len
  deq.head = (deq.head - 1) and deq.mask
  deq.storage[deq.head] = item

proc addLast*[T](deq: var Deque[T], item: sink T) =
  expandIfNeeded(deq)
  inc deq.len
  deq.storage[deq.tail] = item
  deq.tail = (deq.tail + 1) and deq.mask

proc peekFirst*[T](deq: Deque[T]): lent T {.inline.} =
  emptyCheck(deq)
  deq.storage[deq.head]

proc peekLast*[T](deq: Deque[T]): lent T {.inline.} =
  emptyCheck(deq)
  deq.storage[(deq.tail - 1) and deq.mask]

proc peekFirst*[T](deq: var Deque[T]): var T {.inline.} =
  emptyCheck(deq)
  deq.storage[deq.head]

proc peekLast*[T](deq: var Deque[T]): var T {.inline.} =
  emptyCheck(deq)
  deq.storage[(deq.tail - 1) and deq.mask]

proc popFirst*[T](deq: var Deque[T]): T {.inline.} =
  emptyCheck(deq)
  dec deq.len
  result = move deq.storage[deq.head]
  deq.head = (deq.head + 1) and deq.mask

proc popLast*[T](deq: var Deque[T]): T {.inline.} =
  emptyCheck(deq)
  dec deq.len
  deq.tail = (deq.tail - 1) and deq.mask
  result = move deq.storage[deq.tail]

proc clear*[T](deq: var Deque[T]) {.inline.} =
  for el in mitems(deq): destroy(el)
  deq.len = 0
  deq.tail = deq.head

proc `$`*[T](deq: Deque[T]): string =
  result = "["
  for x in deq:
    if result.len > 1: result.add(", ")
    result.addQuoted(x)
  result.add("]")
