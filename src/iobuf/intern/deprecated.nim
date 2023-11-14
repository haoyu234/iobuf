import std/macros

template getAddr*(val): untyped =
  when compiles(val.addr):
    val.addr
  else:
    val.unsafeAddr

macro `fix=destroy(var T)`*(body: untyped): untyped =
  when (NimMajor, NimMinor, NimPatch) >= (2, 0, 0):
    let t = body[3][1][1]
    if t.kind == nnkVarTy:
      body[3][1][1] = t[0]
  body

static:
  discard getProjectPath()
