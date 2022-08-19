const
  marggersNoDefaultHtmlHandler* {.booldefine.} = false
    ## Define this to disable inline HTML at compile time completely,
    ## to circumvent the standard library XML parser dependency.
    ## This is overriden by `MarggersParser.inlineHtmlHandler`.
  marggersCurlyNoHtmlEscape* {.booldefine.} = false
    ## The default compile time value of `MarggersOptions.curlyNoHtmlEscape`.
  marggersSingleLineStaticBool* {.booldefine.} = false
    ## Possible minor optimization. Not guaranteed to be faster.
  marggersDelimedUseSubstrs* {.booldefine.} = false
    ## Possible minor optimization. Not guaranteed to be faster.

when defined(js) and not defined(nimdoc):
  type NativeString* = cstring

  func toCstring*(y: char): cstring {.importc: "String.fromCharCode".}
  func add*(x: var cstring, y: char) =
    x.add(toCstring(y))
  func add*(x: var cstring, y: static char) =
    x.add(static(cstring($y)))
  func `&`*(x, y: cstring): cstring {.importjs: "(# + #)".}
  func subs(c: cstring, a, b: int): cstring {.importjs: "#.substring(@)".}
  func `[]`*(c: cstring, ind: Slice[int]): cstring =
    c.subs(ind.a, ind.b + 1)
  func `[]`*(c: cstring, ind: HSlice[int, BackwardsIndex]): cstring =
    c.subs(ind.a, c.len - ind.b.int + 1)
  func `[]`*(c: cstring, ind: HSlice[BackwardsIndex, BackwardsIndex]): cstring =
    c.subs(c.len - ind.a.int, c.len - ind.b.int + 1)
  
  func strip*(s: cstring): cstring {.importjs: "#.trim()".}

  template toNativeString*(x: char): NativeString = toCstring(x)
else:
  type NativeString* = string
    ## Most convenient string type to use for each backend.
    ## `cstring` on JS.

  template toNativeString*(x: char): NativeString = $x

template toNativeString*(x: string | cstring): NativeString = NativeString(x)

template moveCompat*(x: untyped): untyped =
  ## Compatibility replacement for `move`
  when not declared(move) or (defined(js) and (NimMajor, NimMinor, NimPatch) <= (1, 4, 2)):
    # bugged for JS, fixed for 1.4.4 in https://github.com/nim-lang/Nim/pull/16979
    x
  else:
    move(x)

when not defined(nimscript): # breaks nimscript for some reason
  func contains*[I](arr: static array[I, string], x: string): bool {.inline.} =
    ## More efficient version of `contains` for static arrays of strings
    ## using `case`
    case x
    of arr: result = true
    else: result = false
