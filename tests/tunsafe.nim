import std/unittest

import cbuf/intern/unsafe

var p: ptr UncheckedArray[int]

template checkSeq(d) =
  check d[0] == 1
  check d[1] == 2
  check d[2] == 3
  check d[3] == 4

test "stealSeq":

  block:
    var data = @[1, 2, 3, 4]
    p = stealSeq(move data) # Box::into_raw

    checkSeq(p)
  checkSeq(p)

test "restoreSeq":

  let data = restoreSeq(4, p)
  checkSeq(data) # Box::from_raw
