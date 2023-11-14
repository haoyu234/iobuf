import std/unittest

import iobuf/slice2
import iobuf/intern/chunk

test "leftSpace":

  let chunk = newChunk(DEFAULT_CHUNK_SIZE)

  check chunk.leftSpace == DEFAULT_CHUNK_SIZE
  check cast[uint](chunk.leftAddr) + DEFAULT_CHUNK_SIZE == cast[uint](
      chunk.rightAddr)
  check cast[uint](chunk.writeAddr) + DEFAULT_CHUNK_SIZE == cast[uint](
      chunk.rightAddr)
  check not chunk.isFull

  chunk.extendLen(DEFAULT_CHUNK_SIZE - 1)

  check chunk.leftSpace == 1
  check cast[uint](chunk.leftAddr) + DEFAULT_CHUNK_SIZE == cast[uint](
      chunk.rightAddr)
  check cast[uint](chunk.writeAddr) + 1 == cast[uint](chunk.rightAddr)
  check not chunk.isFull

  chunk.extendLen(1)
  check chunk.leftSpace == 0
  check cast[uint](chunk.leftAddr) + DEFAULT_CHUNK_SIZE == cast[uint](
      chunk.rightAddr)
  check chunk.writeAddr == chunk.rightAddr
  check chunk.isFull

test "newChunk":

  let chunk1 = newChunk(DEFAULT_CHUNK_SIZE)
  discard chunk1

  var data = @[byte(1), 2, 3, 4]
  let data2 = data
  let oldLen = data.len
  let chunk2 = newChunk(move data)

  check chunk2.len == oldLen
  check data2.slice() == chunk2.toOpenArray().slice()
