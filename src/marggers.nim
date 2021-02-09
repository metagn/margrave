## Dialect of markdown.
## Does not work for JS with Nim version 1.2.x and earlier,
## unless `-d:marggersNoInlineHtml` is passed, which disables
## inline HTML at compile time.
## Note that this switch will save binary size on all
## backends, since an XML parser needs to be included for
## inline HTML.

import strutils

const noInlineHtml = defined(marggersNoInlineHtml)

when not noInlineHtml:
  import marggers/singlexml

when defined(js):
  type NativeString = cstring

  proc toCstring(y: char): cstring {.importc: "String.fromCharCode".}
  proc add(x: var cstring, y: char) =
    x.add(toCstring(y))
  proc `[]`(c: cstring, ind: Slice[int]): cstring =
    {.emit: [result, " = ", c, ".substring(", ind.a, ", ", ind.b + 1, ")"].}
  proc addQuoted(s: var cstring, x: cstring) =
    s.add("\"")
    for c in x:
      # Only ASCII chars are escaped to avoid butchering
      # multibyte UTF-8 characters.
      if c <= 127.char:
        var s2 = ""
        s2.addEscapedChar(c)
        s.add(s2)
      else:
        s.add c
    s.add("\"")
else:
  type NativeString = string

type
  KnownTags* = enum
    noTag,
    p, br,
    h1, h2, h3, h4, h5, h6,
    ul, ol, li, blockquote,
    sup, sub, em, strong, pre, code, u, s,
    img, input, a

  MarggersElement* = ref object
    case isText*: bool
    of true:
      str*: NativeString
    else:
      tag*: KnownTags
      attrs*: seq[(NativeString, NativeString)]
      content*: seq[MarggersElement]
  
  MarggersParser* = object
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int

proc newStr(s: NativeString): MarggersElement = MarggersElement(isText: true, str: s)
proc newElem(tag: KnownTags, content: seq[MarggersElement] = @[]): MarggersElement =
  MarggersElement(isText: false, tag: tag, content: content)
proc paragraphIfText(elem: MarggersElement): MarggersElement =
  if elem.isText:
    MarggersElement(isText: false, tag: p, content: @[elem])
  else:
    elem

template `[]`(elem: MarggersElement, i: int): MarggersElement =
  elem.content[i]

template `[]`(elem: MarggersElement, i: BackwardsIndex): MarggersElement =
  elem.content[i]

template `[]=`(elem: MarggersElement, i: int, el: MarggersElement) =
  elem.content[i] = el

template `[]=`(elem: MarggersElement, i: BackwardsIndex, el: MarggersElement) =
  elem.content[i] = el

template add(elem, cont: MarggersElement) =
  elem.content.add(cont)

template add(elem: MarggersElement, cont: seq[MarggersElement]) =
  elem.content.add(cont)

template add(elem: MarggersElement, str: NativeString) =
  elem.content.add(newStr(str))

proc `$`*(elem: MarggersElement): string =
  ## Outputs a marggers element as HTML.
  if elem.isText:
    result = $elem.str
  else:
    result.add('<')
    result.add($elem.tag)
    for (attrName, attrValue) in elem.attrs.items:
      result.add(' ')
      result.add(attrName)
      if attrValue.len != 0:
        result.add('=')
        result.addQuoted(attrValue)
    result.add('>')
    for cont in elem.content:
      result.add($cont)
    case elem.tag
    of br, img, input:
      discard
    else:
      result.add("</")
      result.add($elem.tag)
      result.add('>')

when defined(js) or defined(nimdoc):
  proc toCstring*(elem: MarggersElement): cstring =
    ## Outputs a marggers element as HTML as a cstring, but only in JS.
    if elem.isText:
      result = elem.str
    else:
      result.add('<')
      result.add(cstring($elem.tag))
      for (attrName, attrValue) in elem.attrs.items:
        result.add(' ')
        result.add(attrName)
        if attrValue.len != 0:
          result.add('=')
          result.addQuoted(cstring attrValue)
      result.add('>')
      for cont in elem.content:
        result.add(cont.toCstring())
      case elem.tag
      of br, img, input:
        discard
      else:
        result.add("</")
        result.add(cstring($elem.tag))
        result.add('>')

template get(parser: MarggersParser, offset: int = 0): char =
  parser.str[parser.pos + offset]

template get(parser: MarggersParser, offset: int = 0, len: int): NativeString =
  parser.str[parser.pos + offset ..< parser.pos + offset + len]

iterator nextChars(parser: var MarggersParser): char =
  while parser.pos < parser.str.len:
    yield parser.get()
    inc parser.pos

proc peekMatch(parser: var MarggersParser, pat: set[char], offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len and parser.get(offset) in pat

proc peekMatch(parser: var MarggersParser, pat: char, offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len and parser.get(offset) == pat

proc peekMatch(parser: var MarggersParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.pos + offset + pat.len <= parser.str.len and parser.get(offset, pat.len) == pat

proc nextMatch(parser: var MarggersParser, pat: set[char], offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

proc nextMatch(parser: var MarggersParser, pat: char, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

proc nextMatch(parser: var MarggersParser, pat: string, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + pat.len

proc skipWhitespaceUntilNewline(parser: var MarggersParser): bool =
  var i = 0
  while parser.pos + i < parser.str.len:
    let ch = parser.get(offset = i)
    case ch
    of '\n':
      parser.pos += i
      return true
    of Whitespace - {'\n'}:
      discard
    else:
      return false
    inc i

import macros

macro matchNext(parser: var MarggersParser, branches: varargs[untyped]) {.used.} =
  result = newTree(nnkIfStmt)
  for b in branches:
    case b.kind
    of nnkOfBranch:
      var cond: NimNode = newCall(ident"nextMatch", parser, b[0])
      let h = b.len - 1
      for i in 1 ..< h:
        cond = infix(cond, "or", newCall(ident"nextMatch", parser, b[i]))
      result.add(newTree(nnkElifBranch, cond, b[h]))
    of nnkElifBranch, nnkElse:
      result.add(b)
    else:
      error("invalid branch for matchNext", b)

proc parseBracket(image: bool, parser: var MarggersParser, doubleNewLine: bool): MarggersElement

proc parseCurly(parser: var MarggersParser): MarggersElement =
  result = newStr("")
  var opencurlys = 1
  var escaped = false
  for ch in parser.nextChars:
    if not escaped:
      case ch
      of '\\':
        escaped = true
      of '{':
        inc opencurlys
        result.str.add('{')
      of '}':
        dec opencurlys
        if opencurlys == 0:
          return
        else:
          result.str.add('}')
      else:
        result.str.add(ch)
    else:
      if ch notin {'\\', '}', '{'}:
        result.str.add('\\')
      result.str.add(ch)
      escaped = false

proc parseCodeBlock(parser: var MarggersParser): MarggersElement =
  result = newElem(pre, @[newStr("")])
  while parser.nextMatch(Whitespace): discard
  for ch in parser.nextChars:
    if parser.nextMatch("```"):
      dec parser.pos # idk?? helps newline?
      return
    else:
      result[^1].str.add(
        case ch
        of '>': "&gt;"
        of '<': "&lt;"
        of '&': "&amp;"
        else: $ch
      )

proc parseDelimed(parser: var MarggersParser, delim: string, doubleNewLine: bool = true): (bool, seq[MarggersElement]) =
  var escaped = false
  var elems: seq[MarggersElement]
  elems.add(newStr(""))
  for ch in parser.nextChars:
    assert elems[^1].isText
    if not escaped:
      const useSubstrs = false
      let initialPos = parser.pos

      when useSubstrs:
        var matchLen: int
        let maxIndexAfter3 = min(parser.pos + 3, parser.str.len - 1)
        var substrs: array[4, NativeString]
        for i in parser.pos..maxIndexAfter3:
          substrs[i - parser.pos] = parser.str[parser.pos..i]

        template check(s: string): bool =
          substrs[s.len - 1] == s and (matchLen = s.len; true)

        template nextMatch(parser: var MarggersParser, pat: string): bool =
          check(pat) and (parser.pos += matchLen; true)

      proc parseAux(tag: KnownTags, del: string, parser: var MarggersParser#[
        elems: var seq[MarggersElement], doubleNewLine: bool, initial: int]#): bool =
        let currentPos = parser.pos
        let (finished, parsedElems) = parseDelimed(parser, del, doubleNewLine)
        if finished:
          elems.add(newElem(tag, parsedElems))
          result = false
        else:
          elems[^1].str.add(parser.str[initialPos ..< currentPos])
          elems.add(parsedElems)
          result = true
        elems.add(newStr(""))

      template parse(tag: KnownTags, del: string) =
        if parseAux(tag, del, parser, #[, elems, doubleNewLine, initialPos]#):
          return (true, elems)

      proc bracket(image: bool, parser: var MarggersParser): bool =
        let elem = parseBracket(image, parser, doubleNewLine)
        if elem.tag == noTag:
          elems[^1].str.add(if image: "![" else: "[")
          elems.add(elem.content)
          result = true
        else:
          elems.add(elem)
          elems.add(newStr(""))
          result = false

      matchNext parser:
      elif delim.len != 0 and parser.nextMatch(delim):
        # greedy ^
        dec parser.pos
        return (true, elems)
      elif (doubleNewLine and (parser.nextMatch("\r\n\r\n") or parser.nextMatch("\n\n"))) or
         (not doubleNewLine and (parser.nextMatch("\r\n") or parser.nextMatch("\n"))):
        if not doubleNewLine and delim.len == 0:
          dec parser.pos
        else:
          parser.pos = initialPos # why do this
        return (delim.len == 0, elems)
      of "  \r\n", "  \n":
        elems.add(newElem(br))
        elems.add(newStr(""))
      of "```":
        elems.add(parseCodeBlock(parser))
        elems.add(newStr(""))
      of "^(": parse(sup, ")")
      of "**": parse(strong, "**")
      of "__": parse(u, "__")
      of "~~": parse(s, "~~")
      of "![":
        if bracket(image = true, parser):
          return (true, elems)
      of '{':
        elems.add(parseCurly(parser))
      of '[':
        if bracket(image = false, parser):
          return (true, elems)
      of '`': parse(code, "`")
      of '*': parse(em, "*")
      of '_': parse(em, "_")
      of '<':
        dec parser.pos
        let (change, pos) =
          when noInlineHtml:
            (false, 0)
          else:
            parseXml($parser.str, parser.pos)
        if change:
          elems[^1].str.add(parser.str[parser.pos ..< parser.pos + pos])
          parser.pos += pos - 1
        else:
          elems[^1].str.add("&lt;")
      of '>':
        dec parser.pos
        elems[^1].str.add("&gt;")
      of '&':
        dec parser.pos
        block ampBlock:
          let firstChar = if parser.pos > parser.str.len: ' ' else: parser.str[parser.pos + 1]
          inc parser.pos
          if firstChar in Letters:
            inc parser.pos, 2
            for ch in parser.nextChars:
              case ch
              of Letters:
                discard
              of ';':
                break
              else:
                parser.pos = initialPos
                elems[^1].str.add("&amp;")
                break ampBlock
            elems[^1].str.add(parser.str[initialPos .. parser.pos])
          elif firstChar == '#':
            inc parser.pos, 2
            for ch in parser.nextChars:
              case ch
              of Digits:
                discard
              of ';':
                break
              else:
                parser.pos = initialPos
                elems[^1].str.add("&amp;")
                break ampBlock
            elems[^1].str.add(parser.str[initialPos .. parser.pos])
          else:
            elems[^1].str.add("&amp;")
      of '\\':
        dec parser.pos
        escaped = true
      else:
        elems[^1].str.add(ch)
    else:
      elems[^1].str.add(ch)
      escaped = false
    if not elems[^1].isText:
      elems.add(newStr(""))
  result = (false, elems)

proc parseLink(parser: var MarggersParser): tuple[finished: bool, url, tip: string] =
  var state: range[0..3] = 0
  var
    delim: char
    escaped = false
    openparens = 1
  for ch in parser.nextChars:
    case state
    of 0:
      case ch
      of Whitespace:
        state = 1
      of '(':
        inc openparens
        result.url.add('(')
      of ')':
        dec openparens
        if openparens == 0:
          result.finished = true
          return
        else:
          result.url.add(')')
      else: result.url.add(ch)
    of 1:
      if ch notin Whitespace:
        if ch in {'"', '\'', '<'}:
          state = 2
          delim = if ch == '<': '>' else: ch
        elif ch == ')':
          result.finished = true
          return
    of 2:
      if not escaped:
        if ch == '\\':
          escaped = true
        elif ch == delim:
          state = 3
        else:
          result.tip.add(ch)
      else:
        if ch notin {'\\', delim}:
          result.tip.add('\\')
        result.tip.add(ch)
        escaped = false
    of 3:
      if ch == ')':
        result.finished = true
        return
  result.finished = false

proc parseBracket(image: bool, parser: var MarggersParser, doubleNewLine: bool): MarggersElement =
  let firstPos = parser.pos
  let (titleWorked, titleElems) = parseDelimed(parser, "]", doubleNewLine)
  inc parser.pos
  let secondPos = parser.pos - 2
  if not titleWorked:
    return newElem(noTag, titleElems)
  let checkMark =
    if not image and titleElems.len == 1 and titleElems[0].isText and titleElems[0].str.len == 1:
      case titleElems[0].str[0]
      of ' ': 1
      of 'x': 2
      else: 0
    else: 0
  if parser.pos < parser.str.len:
    if parser.get() == '(':
      let oldPos = parser.pos
      inc parser.pos
      let (linkWorked, link, tip) = parseLink(parser)
      if linkWorked:
        let elem = MarggersElement(isText: false)
        if image:
          elem.tag = img
          elem.attrs.add((NativeString"src", NativeString link))
          if secondPos - firstPos > 0:
            elem.attrs.add((NativeString"alt", parser.str[firstPos..secondPos]))
        else:
          elem.tag = a
          elem.content = titleElems
          elem.attrs.add((NativeString"href",
            if link.len == 0 and titleElems.len == 1 and titleElems[0].isText:
              move(titleElems[0].str)
            else:
              NativeString link))
        if tip.len != 0:
          elem.attrs.add((NativeString"title", NativeString tip))
        return elem
      else:
        parser.pos = oldPos
    else:
      dec parser.pos
  if image:
    result = newElem(noTag, titleElems)
  elif checkMark == 0:
    result = newElem(sub, titleElems)
  else:
    let elem = newElem(input)
    elem.attrs.add((NativeString"type", NativeString"checkbox"))
    elem.attrs.add((NativeString"disabled", NativeString""))
    if checkMark == 2:
      elem.attrs.add((NativeString"checked", NativeString""))
    result = elem

proc parseInline(parser: var MarggersParser, doubleNewLine: bool = true): seq[MarggersElement] =
  parseDelimed(parser, "", doubleNewLine)[1]

proc parseMarggers*(text: NativeString): seq[MarggersElement] =
  ## Parses a string of text in marggers and translates it to HTML line by line.
  ## Result is a sequence of MarggersElements, to simply generate HTML with no need for readability
  ## turn these all into strings with ``$`` and join them with "".
  var lastLineWasEmpty = true
  var lastElement: MarggersElement
  var parser = MarggersParser(str: text, pos: 0)
  template add(elem: MarggersElement) =
    result.add(elem)
    lastElement = nil
  for firstCh in parser.nextChars:
    if firstCh in {'\r', '\n'}:
      lastLineWasEmpty = true
      if not lastElement.isNil:
        add(paragraphIfText(lastElement))
    elif not lastElement.isNil:
      assert not lastElement.isText
      case lastElement.tag
      of ul:
        if parser.nextMatch(Whitespace, offset = 1):
          let item = newElem(li)
          item.content = parseInline(parser, doubleNewLine = false)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseInline(parser, doubleNewLine = false))
      of ol:
        var i = 0
        while parser.peekMatch(Digits, offset = i): inc i
        if parser.pos + i + 1 < parser.str.len and parser.peekMatch('.', offset = i):
          parser.pos += i + 1
          let item = newElem(li)
          item.content = parseInline(parser, doubleNewLine = false)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseInline(parser, doubleNewLine = false))
      of blockquote:
        if firstCh == '>': inc parser.pos
        let rem = skipWhitespaceUntilNewline(parser)
        if rem:
          if firstCh == '>':
            lastElement[^1] = lastElement[^1].paragraphIfText
            lastElement.add("\n")
            if text[parser.pos - 1] == ' ' and text[parser.pos - 2] == ' ':
              lastElement.add(newElem(br))
          else:
            lastElement[^1] = lastElement[^1].paragraphIfText
            result.add(lastElement)
            if text[parser.pos - 1] == ' ' and text[parser.pos - 2] == ' ':
              result.add(newElem(br))
        elif lastElement[^1].isText:
          lastElement.add("\n")
          lastElement.add(newElem(p, parseInline(parser, doubleNewLine = false)))
        elif firstCh == ' ':
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseInline(parser, doubleNewLine = false))
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseInline(parser, doubleNewLine = false))
      else:
        add(paragraphIfText(lastElement))
        dec parser.pos
    else:
      case firstCh
      of ' ':
        if result.len != 0 and not result[^1].isText and
           result[^1].tag in {ol, ul, blockquote} and
           result[^1].content.len != 0:
          result[^1][^1].add("\n ")
          result[^1][^1].add(parseInline(parser, doubleNewLine = true))
        else:
          lastElement = newElem(p, parseInline(parser, doubleNewLine = false))
      of '#':
        var level = 1
        while level < 6 and parser.peekMatch('#', offset = level): inc level
        parser.pos += level
        lastElement = newElem(KnownTags(static(h1.int - 1) + level))
        const IdStarts = {'(', '[', '{', '<', ':'}
        if parser.nextMatch(IdStarts):
          const LegalId = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
          var id = NativeString""
          while (let ch = parser.get(); parser.nextMatch(LegalId)): id.add(ch)
          inc parser.pos
          lastElement.attrs.add((NativeString"id", id))
        lastElement.add(parseInline(parser, doubleNewLine = false))
      of '*', '-', '+':
        if parser.nextMatch(Whitespace, offset = 1):
          lastElement = newElem(ul)
          let item = newElem(li)
          item.add(parseInline(parser, doubleNewLine = false))
          lastElement.add(item)
        else:
          lastElement = newElem(p, parseInline(parser, doubleNewLine = true))
      of Digits:
        let originalPos = parser.pos
        inc parser.pos
        while parser.nextMatch(Digits): discard
        if parser.nextMatch('.'):
          lastElement = newElem(ol)
          let item = newElem(li)
          item.add(parseInline(parser, doubleNewLine = false))
          lastElement.add(item)
        else:
          parser.pos = originalPos
          lastElement = newElem(p, parseInline(parser, doubleNewLine = true))
      of '>':
        lastElement = newElem(blockquote)
        inc parser.pos
        lastElement.add(newElem(p, parseInline(parser, doubleNewLine = false)))
      elif parser.nextMatch("```"):
        add(parseCodeBlock(parser))
      else:
        lastElement = newElem(p, parseInline(parser, doubleNewLine = true))
  if not lastElement.isNil:
    result.add(lastElement)

proc parseMarggers*(text: string | cstring): seq[MarggersElement] =
  ## Alias of parseMarggers that converts other strings to the native string type.
  result = parseMarggers(NativeString(text))

proc parseMarggers*(text: openarray[char]): seq[MarggersElement] =
  ## Alias of parseMarggers that converts openarray[char] to use.
  result = parseMarggers(NativeString($text))

when isMainModule:
  import os, strutils
  echo parseMarggers(readFile(paramStr(1))).join("\n")