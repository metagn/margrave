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
## therefore disable inline HTML, by passing `-d:marggersNoInlineHtml`.
## This switch is available on all backends. You can still embed HTML inside
## curly braces.

import marggers/[common, element, parser, parser/defs]

export MarggersElement, element.`$`, defs

proc parseMarggers*(parser: var MarggersParser,
  staticOptions: static MarggersOptions = defaultParserOptions): seq[MarggersElement] =
  ## Parses marggers with an already initialized parser.
  result = parseTopLevel(parser, staticOptions)

proc parseMarggers*(parser: ref MarggersParser,
  staticOptions: static MarggersOptions = defaultParserOptions): seq[MarggersElement] =
  ## Parses marggers with a reference to an already initialized parser.
  result = parseTopLevel(parser[], staticOptions)

proc parseMarggers*(text: sink NativeString,
  options: MarggersOptions = defaultParserOptions,
  staticOptions: static MarggersOptions = defaultParserOptions): seq[MarggersElement] =
  ## Parses a string of text in marggers and translates it to HTML line by line.
  ## Result is a sequence of MarggersElements, to simply generate HTML with no need for readability
  ## turn these all into strings with ``$`` and join them with "".
  var parser = initMarggersParser(text)
  parser.options = options
  result = parseMarggers(parser, staticOptions)

proc parseMarggers*(text: sink (string | cstring),
  options: MarggersOptions = defaultParserOptions,
  staticOptions: static MarggersOptions = defaultParserOptions): seq[MarggersElement] =
  ## Alias of parseMarggers that takes any string as the argument.
  result = parseMarggers(NativeString(text), options, staticOptions)

proc parseMarggers*(text: sink openarray[char],
  options: MarggersOptions = defaultParserOptions,
  staticOptions: static MarggersOptions = defaultParserOptions): seq[MarggersElement] =
  ## Alias of parseMarggers that takes openarray[char] as the argument.
  ## 
  ## Currently copies.
  result = parseMarggers(NativeString($text), options, staticOptions)

when isMainModule:
  import os, strutils
  case paramStr(1)
  of "parse": echo parseMarggers(paramStr(2)).join("\n")
  of "file": echo parseMarggers(readFile(paramStr(2))).join("\n")
  else: echo "unknown command: ", paramStr(1)
