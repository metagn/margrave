## Dialect of Markdown.
## 
## Example
## =======
## 
## .. include:: ../examples/ref.mrg
##    :literal:
## 
## turns into HTML:
## 
## .. include:: ../examples/ref.html
##    :literal:
## 
## Inline HTML note
## ****************
## 
## **Note**: Nim's XML parser used for inline HTML uses `StringStream` from
## the `streams` module which does not work in JS for Nim version 1.2.x and
## earlier. To work around this, you can disable use of the XML parser,
## therefore disable inline HTML, by passing `-d:margraveNoInlineHtml`.
## This switch is available on all backends. You can still embed HTML inside
## curly braces.

import margrave/[common, element, parser, parser/defs]

export MargraveElement, element.`$`, defs

proc parseMargrave*(parser: var MargraveParser,
  staticOptions: static MargraveOptions = defaultParserOptions): seq[MargraveElement] =
  ## Parses margrave with an already initialized parser.
  result = parseTopLevel(parser, staticOptions)

proc parseMargrave*(parser: ref MargraveParser,
  staticOptions: static MargraveOptions = defaultParserOptions): seq[MargraveElement] =
  ## Parses margrave with a reference to an already initialized parser.
  result = parseTopLevel(parser[], staticOptions)

proc parseMargrave*(text: sink NativeString,
  options: MargraveOptions = defaultParserOptions,
  staticOptions: static MargraveOptions = defaultParserOptions): seq[MargraveElement] =
  ## Parses a string of text in margrave and translates it to HTML line by line.
  ## Result is a sequence of MargraveElements, to simply generate HTML with no need for readability
  ## turn these all into strings with ``$`` and join them with "".
  var parser = initMargraveParser(text)
  parser.options = options
  result = parseMargrave(parser, staticOptions)

proc parseMargrave*(text: sink (string | cstring),
  options: MargraveOptions = defaultParserOptions,
  staticOptions: static MargraveOptions = defaultParserOptions): seq[MargraveElement] =
  ## Alias of parseMargrave that takes any string as the argument.
  result = parseMargrave(NativeString(text), options, staticOptions)

proc parseMargrave*(text: sink openarray[char],
  options: MargraveOptions = defaultParserOptions,
  staticOptions: static MargraveOptions = defaultParserOptions): seq[MargraveElement] =
  ## Alias of parseMargrave that takes openarray[char] as the argument.
  ## 
  ## Currently copies.
  result = parseMargrave(NativeString($text), options, staticOptions)

when isMainModule:
  import os, strutils
  case paramStr(1)
  of "parse": echo parseMargrave(paramStr(2)).join("\n")
  of "file": echo parseMargrave(readFile(paramStr(2))).join("\n")
  else: echo "unknown command: ", paramStr(1)
