## Dialect of markdown.
## Does not work for JS with Nim version 1.2.x and earlier,
## unless `-d:marggersNoInlineHtml` is passed, which disables
## inline HTML at compile time.
## Note that this switch will save binary size on all
## backends, since an XML parser needs to be included for
## inline HTML.

import marggers/[parser, shared]

export shared

proc parseMarggers*(text: NativeString): seq[MarggersElement] =
  ## Parses a string of text in marggers and translates it to HTML line by line.
  ## Result is a sequence of MarggersElements, to simply generate HTML with no need for readability
  ## turn these all into strings with ``$`` and join them with "".
  result = parseTopLevel(text)

proc parseMarggers*(text: string | cstring): seq[MarggersElement] =
  ## Alias of parseMarggers that takes any string as the argument.
  result = parseMarggers(NativeString(text))

proc parseMarggers*(text: openarray[char]): seq[MarggersElement] =
  ## Alias of parseMarggers that takes openarray[char] as the argument.
  result = parseMarggers(NativeString($text))

when isMainModule:
  import os, strutils
  echo parseMarggers(readFile(paramStr(1))).join("\n")
