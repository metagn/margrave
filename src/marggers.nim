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
  MarggersElement* = ref object
    case isText*: bool
    of true:
      str*: NativeString
    else:
      tag*: NativeString
      attrs*: seq[(NativeString, NativeString)]
      content*: seq[MarggersElement]
  
  MarggersParser* = object
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int

proc newStr(s: NativeString): MarggersElement = MarggersElement(isText: true, str: s)
proc newElem(tag: NativeString, content: seq[MarggersElement] = @[]): MarggersElement =
  MarggersElement(isText: false, tag: tag, content: content)
proc paragraphIfText(elem: MarggersElement): MarggersElement =
  if elem.isText:
    MarggersElement(isText: false, tag: "p", content: @[elem])
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
    result.add(elem.tag)
    for (attrName, attrValue) in elem.attrs.items:
      result.add(' ')
      result.add(attrName)
      if attrValue.len != 0:
        result.add('=')
        result.addQuoted(attrValue)
    result.add('>')
    for cont in elem.content:
      result.add($cont)
    case $elem.tag
    of "br", "img", "input":
      discard
    else:
      result.add("</")
      result.add(elem.tag)
      result.add('>')

when defined(js) or defined(nimdoc):
  proc toCstring*(elem: MarggersElement): cstring =
    ## Outputs a marggers element as HTML as a cstring, but only in JS.
    if elem.isText:
      result = elem.str
    else:
      result.add('<')
      result.add(elem.tag)
      for (attrName, attrValue) in elem.attrs.items:
        result.add(' ')
        result.add(attrName)
        if attrValue.len != 0:
          result.add('=')
          result.addQuoted(cstring attrValue)
      result.add('>')
      for cont in elem.content:
        result.add(cont.toCstring())
      case $elem.tag
      of "br", "img", "input":
        discard
      else:
        result.add("</")
        result.add(elem.tag)
        result.add('>')

iterator nextChars(parser: var MarggersParser): char =
  while parser.pos < parser.str.len:
    yield parser.str[parser.pos]
    inc parser.pos

proc skipWhitespaceUntilNewline(parser: var MarggersParser): bool =
  result = true
  for ch in parser.nextChars:
    case ch
    of '\n':
      return
    of Whitespace - {'\n'}:
      discard
    else:
      return false

proc parseBracket(img: bool, parser: var MarggersParser, doubleNewLine: bool): MarggersElement

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

# todo: go through XML text and parse it as marggers

proc parseDelimed(parser: var MarggersParser, Delim: string, doubleNewLine: bool = true): (bool, seq[MarggersElement]) =
  var escaped = false
  var elems: seq[MarggersElement]
  elems.add(newStr(""))
  for ch in parser.nextChars:
    assert elems[^1].isText
    if not escaped:
      var matchLen: int
      let maxIndexAfter3 = min(parser.pos + 3, parser.str.len - 1)
      var substrs: array[4, NativeString]
      for i in parser.pos..maxIndexAfter3:
        substrs[i - parser.pos] = parser.str[parser.pos..i]

      template check(s: static[string]): bool =
        when s.len == 0:
          false
        else:
          substrs[s.len - 1] == s and (matchLen = s.len; true)

      template check(s: string): bool =
        s.len != 0 and substrs[s.len - 1] == s and (matchLen = s.len; true)

      proc parse(parser: var MarggersParser, tag: NativeString, del: string, dnl: bool): bool =
        let (finished, parsedElems) = parseDelimed(parser, del, dnl)
        if finished:
          elems.add(newElem(tag, parsedElems))
          elems.add(newStr(""))
          result = false
        else:
          elems[^1].str.add(substrs[matchLen - 1])
          elems.add(parsedElems)
          elems.add(newStr(""))
          result = true

      template parse(tag: NativeString, del: string) =
        parser.pos += matchLen
        if parse(parser, tag, del, doubleNewLine):
          return (true, elems)

      proc bracket(image: bool, parser: var MarggersParser, dnl: bool): bool =
        let elem = parseBracket(image, parser, dnl)
        if elem.tag == "":
          elems[^1].str.add(if image: "![" else: "[")
          elems.add(elem.content)
          result = true
        else:
          elems.add(elem)
          elems.add(newStr(""))
          result = false

      if (doubleNewLine and (check("\r\n\r\n") or check("\n\n"))) or
         (not doubleNewLine and (check("\r\n") or check("\n"))):
        #[when]#if Delim.len == 0:
          parser.pos += matchLen - 1
        return (Delim.len == 0, elems)
      elif check(Delim):
        parser.pos += Delim.len - 1
        return (true, elems)
      elif check("  \r\n") or check("  \n"):
        parser.pos += matchLen
        elems.add(newElem("br"))
        elems.add(newStr(""))
      elif check("^("): parse("sup", ")")
      elif check("**"): parse("strong", "**")
      elif check("__"): parse("u", "__")
      elif check("~~"): parse("s", "~~")
      elif check("!["):
        parser.pos += 2
        if bracket(image = true, parser, doubleNewLine):
          return (true, elems)
      else:
        matchLen = 1
        let actualPos = parser.pos
        case ch
        of '{':
          inc parser.pos
          elems.add(parseCurly(parser))
        of '[':
          inc parser.pos
          if bracket(image = false, parser, doubleNewLine):
            return (true, elems)
        of '`': parse("code", "`")
        of '*': parse("em", "*")
        of '_': parse("em", "_")
        of '<':
          let (change, pos) =
            when noInlineHtml:
              (false, 0)
            else:
              parseXml($parser.str, actualPos)
          if change:
            elems[^1].str.add(parser.str[actualPos ..< actualPos + pos])
            parser.pos += pos - 1
          else:
            elems[^1].str.add("&lt;")
        of '>':
          elems[^1].str.add("&gt;")
        of '&':
          block ampBlock:
            let firstChar = if actualPos > parser.str.len: ' ' else: parser.str[actualPos + 1]
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
                  parser.pos = actualPos
                  elems[^1].str.add("&amp;")
                  break ampBlock
              elems[^1].str.add(parser.str[actualPos..parser.pos])
            elif firstChar == '#':
              inc parser.pos, 2
              for ch in parser.nextChars:
                case ch
                of Digits:
                  discard
                of ';':
                  break
                else:
                  parser.pos = actualPos
                  elems[^1].str.add("&amp;")
                  break ampBlock
              elems[^1].str.add(parser.str[actualPos..parser.pos])
            else:
              elems[^1].str.add("&amp;")
        of '\\':
          escaped = true
        else:
          elems[^1].str.add(ch)
    else:
      elems[^1].str.add(ch)
      escaped = false
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

proc parseBracket(img: bool, parser: var MarggersParser, doubleNewLine: bool): MarggersElement =
  var firstTi = parser.pos
  let (titleWorked, titleElems) = parseDelimed(parser, "]", doubleNewLine)
  inc parser.pos
  var secondTi = parser.pos - 2
  if not titleWorked:
    return newElem("", titleElems)
  let checkMark =
    if not img and titleElems.len == 1 and titleElems[0].isText and titleElems[0].str.len == 1:
      case titleElems[0].str[0]
      of ' ': 1
      of 'x': 2
      else: 0
    else: 0
  if parser.pos < parser.str.len:
    if parser.str[parser.pos] == '(':
      let oldPos = parser.pos
      inc parser.pos
      let (linkWorked, link, tip) = parseLink(parser)
      if linkWorked:
        let elem = MarggersElement(isText: false)
        if img:
          elem.tag = "img"
          elem.attrs.add((NativeString"src", NativeString link))
          if secondTi - firstTi > 0:
            elem.attrs.add((NativeString"alt", parser.str[firstTi..secondTi]))
        else:
          elem.tag = "a"
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
  if img:
    result = newElem("", titleElems)
  elif checkMark == 0:
    result = newElem("sub", titleElems)
  else:
    let elem = newElem("input")
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
  for firstCh in parser.nextChars:
    if firstCh in {'\r', '\n'}:
      lastLineWasEmpty = true
      if not lastElement.isNil:
        result.add(paragraphIfText(lastElement))
        lastElement = nil
    elif not lastElement.isNil:
      assert not lastElement.isText
      case $lastElement.tag
      of "ul":
        if parser.pos + 1 < parser.str.len and text[parser.pos + 1] in Whitespace:
          inc parser.pos, 2
          let item = newElem("li")
          item.content = parseInline(parser, doubleNewLine = false)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseInline(parser, false))
      of "ol":
        var i = 0
        while i < text.len:
          if text[parser.pos + i] in Digits:
            inc i
          else: break
        if text.len > parser.pos + i + 1 and text[parser.pos + i] == '.':
          parser.pos += i + 1
          let item = newElem("li")
          item.content = parseInline(parser, doubleNewLine = false)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseInline(parser, false))
      of "blockquote":
        if firstCh == '>': inc parser.pos
        let rem = skipWhitespaceUntilNewline(parser)
        if rem:
          if firstCh == '>':
            lastElement[^1] = lastElement[^1].paragraphIfText
            lastElement.add("\n")
            if text[parser.pos - 1] == ' ' and text[parser.pos - 2] == ' ':
              lastElement.add(newElem("br"))
          else:
            lastElement[^1] = lastElement[^1].paragraphIfText
            result.add(lastElement)
            if text[parser.pos - 1] == ' ' and text[parser.pos - 2] == ' ':
              result.add(newElem("br"))
        elif lastElement[^1].isText:
          lastElement.add("\n")
          lastElement.add(newElem("p", parseInline(parser, doubleNewLine = false)))
        elif firstCh == ' ':
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseInline(parser, false))
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseInline(parser, doubleNewLine = false))
      else:
        result.add(paragraphIfText(lastElement))
        lastElement = nil
        dec parser.pos
    else:
      case firstCh
      of ' ':
        if result.len != 0 and not result[^1].isText and
           result[^1].tag in [NativeString"ol", NativeString"ul", NativeString"blockquote"] and
           result[^1].content.len != 0:
          result[^1][^1].add("\n ")
          result[^1][^1].add(parseInline(parser))
        else:
          lastElement = newElem("p", parseInline(parser, false))
      of '#':
        var level = 1
        while level < 7:
          if text[parser.pos + level] == '#':
            inc level
          else:
            break
        parser.pos += level
        lastElement = newElem('h' & char('0'.byte + level.byte))
        case parser.str[parser.pos]
        of '(', '[', '{', '<', ':':
          const idLegalCharacters = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
          var id = NativeString""
          while (inc parser.pos; parser.pos < parser.str.len) and parser.str[parser.pos] in idLegalCharacters:
            id.add(parser.str[parser.pos])
          inc parser.pos
          lastElement.attrs.add((NativeString"id", id))
        else: discard
        lastElement.add(parseInline(parser, doubleNewLine = false))
      of '*', '-', '+':
        if parser.pos + 1 < parser.str.len and parser.str[parser.pos + 1] in Whitespace:
          inc parser.pos, 2
          lastElement = newElem("ul")
          let item = newElem("li")
          item.add(parseInline(parser, doubleNewLine = false))
          lastElement.add(item)
        else:
          lastElement = newElem("p", parseInline(parser))
      of Digits:
        var i = 1
        while parser.pos + i < parser.str.len:
          if parser.str[parser.pos + i] in Digits:
            inc i
          else: break
        if parser.str.len > parser.pos + i + 1 and parser.str[parser.pos + i] == '.':
          inc parser.pos, i + 1
          lastElement = newElem("ol")
          let item = newElem("li")
          item.add(parseInline(parser, doubleNewLine = false))
          lastElement.add(item)
        else:
          lastElement = newElem("p", parseInline(parser))
      of '>':
        lastElement = newElem("blockquote")
        inc parser.pos
        lastElement.add(newElem("p", parseInline(parser, doubleNewLine = false)))
      of '`':
        if parser.pos + 2 < parser.str.len and parser.str[parser.pos + 1] == '`' and parser.str[parser.pos + 2] == '`':
          lastElement = newElem("pre", @[newStr("")])
          inc parser.pos, 3
          while parser.pos < parser.str.len and parser.str[parser.pos] in Whitespace:
            inc parser.pos
          for ch in parser.nextChars:
            if parser.pos + 3 < parser.str.len and ch == '`' and parser.str[parser.pos+1] == '`' and
                 parser.str[parser.pos + 2] == '`' and (parser.str[parser.pos+3] == '\n' or (
                   parser.str[parser.pos+3] == '\r' and parser.pos + 4 < parser.str.len and
                   parser.str[parser.pos+4] == '\n')):
              result.add(lastElement)
              lastElement = nil
              inc parser.pos, 3 + ord(parser.str[parser.pos+3] == '\r')
              break
            else:
              lastElement[^1].str.add(
                case ch
                of '>': "&gt;"
                of '<': "&lt;"
                of '&': "&amp;"
                else: $ch
              )
        else:
          lastElement = newElem("p", parseInline(parser))
      else:
        lastElement = newElem("p", parseInline(parser))
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