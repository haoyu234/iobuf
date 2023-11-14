import std/unittest

import cbuf/slice2
import cbuf/intern/deprecated

{.experimental: "views".}

var data: array[4, byte] = [1, 2, 3, 4]
let slice = data.slice()

test "toOpenArray":

  proc acceptOpenArray(s: openArray[byte]) =
    check s.len == 4
    check s[0] == 1
    check s[1] == 2
    check s[2] == 3
    check s[3] == 4

  proc acceptUncheckedArray(s: ptr UncheckedArray[byte]) =
    check s[0] == 1
    check s[1] == 2
    check s[2] == 3
    check s[3] == 4

  acceptOpenArray(slice)
  acceptUncheckedArray(slice)

test "equals":

  check data == slice
  check slice == data

  proc equalsOpenArray(s: openArray[byte]) =
    check s == slice
    check slice == s

  equalsOpenArray(data)
  equalsOpenArray(slice)

test "sliceOp":

  for i in 0 ..< data.len:
    for j in 1 .. data.len - i + 1:
      check data[i..^j] == slice[i..^j]
      check slice[i..^j] == data[i..^j]

  for i in 0 ..< data.len:
    for j in i ..< data.len:
      check data[i..j] == slice[i..j]
      check slice[i..j] == data[i..j]

  check slice[0 .. 1] is Slice2[byte]

test "outOfBound":

  expect IndexDefect:
    discard slice[0..^0]

  expect IndexDefect:
    discard slice[1..4]

test "sliceAddr":

  let slice1 = slice[0 .. ^2]
  let slice2 = slice[1 .. ^1]

  check slice1[1].getAddr == slice2[0].getAddr
  check slice1.len == data.len - 1
  check slice2.len == data.len - 1
