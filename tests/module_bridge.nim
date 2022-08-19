when (compiles do: import nimbleutils/bridge):
  # nimscript support
  import nimbleutils/bridge
  export bridge
else:
  import unittest
  export unittest
  template runTests*(body) = body
  iterator files*(dir: string): tuple[noDir, withDir: string] =
    for (kind, file) in walkDir(dir, relative = true):
      if kind == pcFile:
        yield (file, dir / file)
  template read*(path: string): string = readFile(path)
  template write*(path, data: string) = writeFile(path, data)

from strutils import strip, Whitespace
import marggers, marggers/common
export NativeString

template becomesImpl =
  var i = 0
  for elem in parseMarggers(marggers, options):
    let el = strip($elem, chars = Whitespace)
    while html[i] in Whitespace: inc i
    if i + el.len <= html.len and html[i ..< i + el.len] == NativeString(el):
      i += el.len
    else:
      checkpoint("got element: " & $elem)
      checkpoint("expected element: " & $html[i .. ^1])
      return false
  result = true

proc becomes*(marggers: var MarggersParser, html: NativeString, options: static MarggersOptions = defaultParserOptions): bool =
  becomesImpl()

proc becomes*(marggers: NativeString, html: NativeString, options: static MarggersOptions = defaultParserOptions): bool =
  becomesImpl()
