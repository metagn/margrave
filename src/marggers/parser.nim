import strutils
import ./shared

const noInlineHtml = defined(marggersNoInlineHtml)

when not noInlineHtml:
  import ./singlexml

proc parseBracket*(image: bool, parser: var MarggersParser, doubleNewLine: bool): MarggersElement

proc parseCurly*(parser: var MarggersParser): MarggersElement =
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
      result.str.add(
        case ch
        of '>': "&gt;"
        of '<': "&lt;"
        of '&': "&amp;"
        of '\\', '}', '{': $ch
        else: '\\' & ch)
      escaped = false

proc parseCodeBlock*(parser: var MarggersParser): MarggersElement =
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

type DelimFinishReason* = enum
  frDone
  frReachedEnd
  frFailed

proc parseDelimed*(parser: var MarggersParser, delim: string, doubleNewLine: bool = true): (DelimFinishReason, seq[MarggersElement]) =
  var escaped = false
  var elems: seq[MarggersElement]
  elems.add(newStr(""))
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

        template nextMatch(parser: var MarggersParser, pat: string): bool =
          check(pat) and (parser.pos += matchLen; true)

      proc parseAux(tag: KnownTags, del: string, parser: var MarggersParser#[
        elems: var seq[MarggersElement], doubleNewLine: bool, initial: int]#): DelimFinishReason =
        let currentPos = parser.pos
        let (finishReason, parsedElems) = parseDelimed(parser, del, doubleNewLine)
        if finishReason == frDone:
          elems.add(newElem(tag, parsedElems))
          result = frDone
        else:
          elems[^1].str.add(parser.str[initialPos ..< currentPos])
          elems.add(parsedElems)
          result = finishReason
        elems.add(newStr(""))

      template parse(tag: KnownTags, del: string) =
        let reason = parseAux(tag, del, parser, #[, elems, doubleNewLine, initialPos]#)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)

      proc bracket(image: bool, parser: var MarggersParser): DelimFinishReason =
        let elem = parseBracket(image, parser, doubleNewLine)
        if elem.tag == noTag:
          elems[^1].str.add(if image: "![" else: "[")
          elems.add(elem.content)
          result = frFailed
        else:
          elems.add(elem)
          elems.add(newStr(""))
          result = frDone

      matchNext parser:
      elif delim.len != 0 and parser.nextMatch(delim):
        # greedy ^
        dec parser.pos
        return (frDone, elems)
      elif (doubleNewLine and (parser.nextMatch("\r\n\r\n") or parser.nextMatch("\n\n"))) or
         (not doubleNewLine and (parser.nextMatch("\r\n") or parser.nextMatch("\n"))):
        if not doubleNewLine and delim.len == 0:
          dec parser.pos
        else:
          parser.pos = initialPos # why do this
        return ((if delim.len == 0: frReachedEnd else: frDone), elems)
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
        let reason = bracket(image = true, parser)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)
      of '{':
        elems.add(parseCurly(parser))
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
  result = (frReachedEnd, elems)

proc parseLink*(parser: var MarggersParser): tuple[finished: bool, url, tip: string] =
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

proc parseBracket*(image: bool, parser: var MarggersParser, doubleNewLine: bool): MarggersElement =
  let firstPos = parser.pos
  let (titleWorked, titleElems) = parseDelimed(parser, "]", doubleNewLine)
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

proc parseInline*(parser: var MarggersParser, doubleNewLine: bool = true): seq[MarggersElement] =
  let (finishReason, elems) = parseDelimed(parser, "", doubleNewLine)
  assert finishReason != frFailed
  result = elems

proc parseTopLevel*(text: NativeString): seq[MarggersElement] =
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
