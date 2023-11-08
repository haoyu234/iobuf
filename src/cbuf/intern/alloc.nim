when defined(zephyr) and not defined(zephyrUseLibcMalloc):
  when not declared(c_malloc):
    proc c_malloc*(size: csize_t): pointer {.
      importc: "k_malloc", header: "<kernel.h>".}

  when not declared(c_calloc):
    proc c_calloc*(nmemb, size: csize_t): pointer {.
      importc: "k_calloc", header: "<kernel.h>".}

  when not declared(c_free):
    proc c_free*(p: pointer) {.
      importc: "k_free", header: "<kernel.h>".}

  when not declared(c_realloc):
    proc c_realloc*(p: pointer, newsize: csize_t): pointer =
      # Zephyr's kernel malloc doesn't support realloc
      result = c_malloc(newSize)
      # match the ansi c behavior
      if not result.isNil():
        copyMem(result, p, newSize)
        c_free(p)
else:
  when not declared(c_malloc):
    proc c_malloc*(size: csize_t): pointer {.
      importc: "malloc", header: "<stdlib.h>".}

  when not declared(c_calloc):
    proc c_calloc*(nmemb, size: csize_t): pointer {.
      importc: "calloc", header: "<stdlib.h>".}

  when not declared(c_free):
    proc c_free*(p: pointer) {.
      importc: "free", header: "<stdlib.h>".}

  when not declared(c_realloc):
    proc c_realloc*(p: pointer, newsize: csize_t): pointer {.
      importc: "realloc", header: "<stdlib.h>".}
