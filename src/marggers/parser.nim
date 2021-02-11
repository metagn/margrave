import strutils
import ./shared

const noInlineHtml = defined(marggersNoInlineHtml)

when not noInlineHtml:
  import ./singlexml

const singleLineStaticBool = defined(marggersSingleLineStaticBool)

when singleLineStaticBool:
  type SingleLineBool* = static bool
else:
  type SingleLineBool* = bool
    ## The type of the argument `singleLine` in parse procs.
    ## When `marggersSingleLineStaticBool` is defined, this will be `static`.
    ## This could lead to slightly faster code, but a larger binary.

proc parseBracket*(image: bool, parser: MarggersParserVar, singleLine: SingleLineBool): MarggersElement

proc parseCurly*(parser: MarggersParserVar): NativeString =
  result = ""
  var opencurlys = 1
  var escaped = false
  for ch in parser.nextChars:
    if not escaped:
      case ch
      of '\\':
        escaped = true
      of '{':
        inc opencurlys
        result.add('{')
      of '}':
        dec opencurlys
        if opencurlys == 0:
          return
        else:
          result.add('}')
      else:
        result.add(ch)
    else:
      result.add(
        case ch
        of '>': NativeString"&gt;"
        of '<': NativeString"&lt;"
        of '&': NativeString"&amp;"
        of '\\', '}', '{': toNativeString(ch)
        else: NativeString"\\" & toNativeString(ch))
      escaped = false

proc parseAmpStr*(parser: MarggersParserVar): NativeString =
  let initialPos = parser.pos
  let firstChar = if initialPos < parser.str.len: parser.str[initialPos] else: ' '
  case firstChar
  of Letters:
    inc parser.pos, 2
    result = "&"
    for ch in parser.nextChars:
      result.add(ch)
      if ch == ';': break
      elif ch notin Letters:
        parser.pos = initialPos
        return "&amp;"
  of '#':
    inc parser.pos, 2
    result = "&"
    for ch in parser.nextChars:
      result.add(ch)
      if ch == ';': break
      elif ch notin Digits:
        parser.pos = initialPos
        return "&amp;"
  else:
    result = "&amp;"

proc parseCodeBlockStr*(parser: MarggersParserVar, delimChar: char): NativeString =
  result = NativeString""
  var delimLen = 3
  while parser.nextMatch(delimChar): inc delimLen
  while parser.nextMatch(Whitespace): discard
  for ch in parser.nextChars:
    if parser.nextMatch(delimChar, len = delimLen):
      dec parser.pos # idk?? helps newline?
      return
    else:
      result.add(
        case ch
        of '>': NativeString"&gt;"
        of '<': NativeString"&lt;"
        of '&': NativeString"&amp;"
        else: toNativeString ch
      )

proc parseCodeBlock*(parser: MarggersParserVar, delimChar: char): MarggersElement {.inline.} =
  result = newElem(pre, @[newStr(parseCodeBlockStr(parser, delimChar))])

type
  DelimFinishReason* = enum
    frDone
    frReachedEnd
    frFailed

proc parseDelimed*(parser: MarggersParserVar, delim: string, singleLine: SingleLineBool): (DelimFinishReason, seq[MarggersElement]) =
  # DelimParser
  var
    escaped = false
    lastStr = newStr("")
    elems = @[lastStr]
  
  template refreshStr() =
    lastStr = newStr("")
    elems.add(lastStr)
  
  template add(s: string | cstring | char) =
    lastStr.str.add(s)
  
  template add(elem: MarggersElement) =
    elems.add(elem)
    refreshStr()
  
  template add(newElems: seq[MarggersElement]) =
    elems.add(newElems)
    refreshStr()
  
  for ch in parser.nextChars:
    assert elems[^1].isText
    if not escaped:
      const useSubstrs = defined(marggersDelimedUseSubstrs)
      let initialPos = parser.pos

      when useSubstrs:
        var matchLen: int
        let maxIndexAfter3 = min(parser.pos + 3, parser.str.len - 1)
        var substrs: array[4, NativeString]
        for i in parser.pos..maxIndexAfter3:
          substrs[i - parser.pos] = parser.str[parser.pos..i]

        template check(s: string): bool =
          substrs[s.len - 1] == s and (matchLen = s.len; true)

        template nextMatch(parser: MarggersParserVar, pat: string): bool =
          check(pat) and (parser.pos += matchLen; true)

      proc parseAux(tag: KnownTags, del: string, parser: MarggersParserVar#[
        elems: var seq[MarggersElement], singleLine: SingleLineBool, initial: int]#): DelimFinishReason =
        let currentPos = parser.pos
        let (finishReason, parsedElems) = parseDelimed(parser, del, singleLine)
        if finishReason == frDone:
          add(newElem(tag, parsedElems))
          result = frDone
        else:
          add(parser.str[initialPos ..< currentPos])
          add(parsedElems)
          result = finishReason

      template parse(tag: KnownTags, del: string) =
        let reason = parseAux(tag, del, parser, #[, elems, singleLine, initialPos]#)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)

      proc bracket(image: bool, parser: MarggersParserVar): DelimFinishReason =
        let elem = parseBracket(image, parser, singleLine)
        if elem.tag == noTag:
          add(if image: NativeString"![" else: NativeString"[")
          add(elem.content)
          result = frFailed
        else:
          add(elem)
          result = frDone

      matchNext parser:
      elif delim.len != 0 and parser.nextMatch(delim):
        # greedy ^
        dec parser.pos
        return (frDone, elems)
      elif (
        when singleLineStaticBool:
          when singleLine: parser.nextMatch("\r\n") or parser.nextMatch("\n")
          else: parser.nextMatch("\r\n\r\n") or parser.nextMatch("\n\n")
        else:
          (singleLine and (parser.nextMatch("\r\n") or parser.nextMatch("\n"))) or
          (not singleLine and (parser.nextMatch("\r\n\r\n") or parser.nextMatch("\n\n")))
      ):
        if singleLine and delim.len == 0:
          dec parser.pos
        else:
          parser.pos = initialPos # why do this
        return ((if delim.len == 0: frReachedEnd else: frDone), elems)
      of "  \r\n", "  \n":
        add(newElem(br))
      of "```":
        add(parseCodeBlock(parser, '`'))
      of "~~~":
        add(parseCodeBlock(parser, '~'))
      of "^(": parse(sup, ")")
      of "**": parse(strong, "**")
      of "__": parse(u, "__")
      of "~~": parse(s, "~~")
      of "![":
        let reason = bracket(image = true, parser)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)
      of '{':
        add(parseCurly(parser))
      of '[':
        let reason = bracket(image = false, parser)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)
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
          add(parser.str[parser.pos ..< parser.pos + pos])
          parser.pos += pos - 1
        else:
          add("&lt;")
      of '>':
        add("&gt;")
        continue
      of '&':
        add(parseAmpStr(parser))
      of '\\':
        dec parser.pos
        escaped = true
      else:
        add(ch)
    else:
      add(ch)
      escaped = false
  result = (frReachedEnd, elems)

proc parseLink*(parser: MarggersParserVar): tuple[finished: bool, url, tip: string] =
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

proc parseBracket*(image: bool, parser: MarggersParserVar, singleLine: SingleLineBool): MarggersElement =
  let firstPos = parser.pos
  let (titleWorked, titleElems) = parseDelimed(parser, "]", singleLine)
  inc parser.pos
  let secondPos = parser.pos - 2
  if titleWorked != frDone:
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

proc parseInline*(parser: MarggersParserVar, singleLine: SingleLineBool): seq[MarggersElement] {.inline.} =
  let (finishReason, elems) = parseDelimed(parser, "", singleLine)
  assert finishReason != frFailed
  result = elems

template parseSingleLine*(parser: MarggersParserVar): seq[MarggersElement] =
  parseInline(parser, singleLine = true)

template parseLine*(parser: MarggersParserVar): seq[MarggersElement] =
  parseInline(parser, singleLine = false)

const InlineWhitespace* = Whitespace - {'\r', '\n'}

func newMarggersParser*(text: NativeString): MarggersParser {.inline.} =
  MarggersParser(str: text, pos: 0)

proc parseTopLevel*(parser: MarggersParserVar): seq[MarggersElement] =
  var lastElement: MarggersElement
  template add(elem: MarggersElement) =
    result.add(elem)
    lastElement = nil
  for firstCh in parser.nextChars:
    const specialLineTags = {ul, ol, blockquote}
    if firstCh in {'\r', '\n'}:
      if not lastElement.isNil:
        add(paragraphIfText(lastElement))
    elif not lastElement.isNil:
      assert not lastElement.isText
      case lastElement.tag
      of ul:
        if parser.nextMatch(Whitespace, offset = 1):
          let item = newElem(li)
          item.content = parseSingleLine(parser)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseSingleLine(parser))
      of ol:
        var i = 0
        while parser.peekMatch(Digits, offset = i): inc i
        if parser.pos + i + 1 < parser.str.len and parser.peekMatch('.', offset = i):
          parser.pos += i + 1
          let item = newElem(li)
          item.content = parseSingleLine(parser)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseSingleLine(parser))
      of blockquote:
        if firstCh == '>': inc parser.pos
        proc skipWhitespaceUntilNewline(parser: MarggersParserVar): bool =
          var i = 0
          while parser.pos + i < parser.str.len:
            let ch = parser.get(offset = i)
            case ch
            of '\n':
              parser.pos += i
              return true
            of '\r', InlineWhitespace:
              discard
            else:
              return false
            inc i
        let rem = skipWhitespaceUntilNewline(parser)
        if rem:
          if firstCh == '>':
            lastElement[^1] = lastElement[^1].paragraphIfText
            lastElement.add("\n")
            if parser.peekMatch("  ", offset = -2):
              lastElement.add(newElem(br))
          else:
            lastElement[^1] = lastElement[^1].paragraphIfText
            result.add(lastElement)
            if parser.peekMatch("  ", offset = -2):
              result.add(newElem(br))
        elif lastElement[^1].isText:
          lastElement.add("\n")
          lastElement.add(newElem(p, parseSingleLine(parser)))
        elif firstCh in InlineWhitespace:
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseSingleLine(parser))
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseSingleLine(parser))
      of {low(KnownTags)..high(KnownTags)} - specialLineTags:
        add(paragraphIfText(lastElement))
        dec parser.pos
    else:
      case firstCh
      of InlineWhitespace:
        if result.len != 0 and not result[^1].isText and
           result[^1].tag in specialLineTags and
           result[^1].content.len != 0:
          result[^1][^1].add("\n ")
          result[^1][^1].add(parseLine(parser))
        else:
          lastElement = newElem(p, parseSingleLine(parser))
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
        lastElement.add(parseSingleLine(parser))
      of '*', '-', '+':
        if parser.nextMatch(Whitespace, offset = 1):
          lastElement = newElem(ul)
          let item = newElem(li)
          item.add(parseSingleLine(parser))
          lastElement.add(item)
        else:
          lastElement = newElem(p, parseLine(parser))
      of Digits:
        let originalPos = parser.pos
        inc parser.pos
        while parser.nextMatch(Digits): discard
        if parser.nextMatch('.'):
          lastElement = newElem(ol)
          let item = newElem(li)
          item.add(parseSingleLine(parser))
          lastElement.add(item)
        else:
          parser.pos = originalPos
          lastElement = newElem(p, parseLine(parser))
      of '>':
        lastElement = newElem(blockquote)
        inc parser.pos
        lastElement.add(newElem(p, parseSingleLine(parser)))
      elif parser.nextMatch("```"):
        add(parseCodeBlock(parser, '`'))
      elif parser.nextMatch("~~~"):
        add(parseCodeBlock(parser, '~'))
      else:
        lastElement = newElem(p, parseLine(parser))
  if not lastElement.isNil:
    result.add(lastElement)
