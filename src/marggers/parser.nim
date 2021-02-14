import strutils, tables
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
  ## Parses a curly bracket element.
  ## 
  ## If `-d:marggersCurlyNoHtmlEscape` is defined, initial `!` characters
  ## are ignored and no HTML chars are escaped.
  result = ""
  const noHtmlEscapeConst = defined(marggersCurlyNoHtmlEscape)
  when noHtmlEscapeConst:
    discard parser.nextMatch('!')
  else:
    let noHtmlEscape = parser.nextMatch('!')
  var
    opencurlys = 1
    escaped = false
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
        result.add(
          when noHtmlEscapeConst:
            ch
          else:
            if noHtmlEscape:
              toNativeString(ch)
            else:
              escapeHtmlChar(ch))
    else:
      result.add(
        case ch
        of '>', '<', '&': escapeHtmlChar(ch)
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

proc parseCodeBlockStr*(parser: MarggersParserVar, delimChar: char): tuple[language, code: NativeString] =
  result = (NativeString"", NativeString"")
  var delimLen = 3
  while parser.nextMatch(delimChar): inc delimLen
  while parser.nextMatch(Whitespace): discard
  if not parser.codeBlockLanguageHandler.isNil:
    const LegalLanguage = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
    while (let ch = parser.get(); parser.nextMatch(LegalLanguage)):
      result.language.add(ch)
  for ch in parser.nextChars:
    if parser.nextMatch(delimChar, len = delimLen):
      dec parser.pos # idk?? helps newline?
      return
    else:
      result.code.add(
        case ch
        of '>': NativeString"&gt;"
        of '<': NativeString"&lt;"
        of '&': NativeString"&amp;"
        else: toNativeString ch
      )

proc parseCodeBlock*(parser: MarggersParserVar, delimChar: char): MarggersElement {.inline.} =
  let str = parseCodeBlockStr(parser, delimChar)
  result = newElem(pre, @[newStr(str.code)])
  if not parser.codeBlockLanguageHandler.isNil and str.language.len != 0:
    parser.codeBlockLanguageHandler(str.language, result)

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

      proc parseAux(tag: KnownTags, del: string, parser: MarggersParserVar,
        acceptedReasons = {frDone}): DelimFinishReason =
        let currentPos = parser.pos
        let (finishReason, parsedElems) = parseDelimed(parser, del, singleLine)
        if finishReason in acceptedReasons:
          add(newElem(tag, parsedElems))
          result = frDone
        else:
          add(parser.str[initialPos ..< currentPos])
          add(parsedElems)
          result = finishReason

      template parse(tag: KnownTags, del: string, acceptedReasons = {frDone}) =
        let reason = parseAux(tag, del, parser, acceptedReasons)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)

      proc bracket(image: bool, parser: MarggersParserVar): DelimFinishReason =
        let elem = parseBracket(image, parser, singleLine)
        if elem.tag == noTag:
          add(if image: NativeString"![" else: NativeString"[")
          add(elem.content)
          #result = frFailed
        else:
          add(elem)
        result = frDone

      case delim
      # custom delim behavior goes here
      of "": discard
      of "*":
        # logic for ** greediness goes here
        # try to parse **, if it fails then return this element
        if parser.nextMatch("**"):
          let (finishReason, parsedElems) = parseDelimed(parser, "**", singleLine)
          if finishReason == frDone:
            add(newElem(strong, parsedElems))
            #inc parser.pos
            continue
          else:
            parser.pos = initialPos
            if not parser.surroundedWhitespace():
              return (frDone, elems)
            else:
              add('*')
              continue
        elif not parser.surroundedWhitespace() and parser.nextMatch("*"):
          dec parser.pos
          return (frDone, elems)
      of "_":
        # logic for __ greediness goes here
        # try to parse __, if it fails then return this element
        if parser.nextMatch("__"):
          let (finishReason, parsedElems) = parseDelimed(parser, "__", singleLine)
          if finishReason == frDone:
            add(newElem(u, parsedElems))
            #inc parser.pos
            continue
          else:
            parser.pos = initialPos
            if parser.onlyNextWhitespace():
              return (frDone, elems)
            else:
              add('_')
              continue
        elif parser.onlyNextWhitespace() and parser.nextMatch("_"):
          dec parser.pos
          return (frDone, elems)
      of " ":
        if ch in Whitespace:
          dec parser.pos
          return (frDone, elems)
      else:
        if parser.nextMatch(delim):
          dec parser.pos
          return (frDone, elems)

      matchNext parser:
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
      elif parser.noAdjacentWhitespace() and parser.nextMatch('^'):
        parse(sup, " ", {frDone, frReachedEnd})
      elif not parser.surroundedWhitespace() and parser.nextMatch('*'):
        parse(em, "*")
      elif parser.onlyPrevWhitespace() and parser.nextMatch('_'):
        parse(em, "_")
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

proc parseLink*(parser: MarggersParserVar, failOnNewline: bool): tuple[finished: bool, url, tip: string] =
  # why is this 100 lines
  type State = enum
    recordingLink
    waitingTitle
    recordingTitle
    waitingEnd
  var
    state: State
    delim: char
    escaped = false
    openparens = 1
  # skip first whitespace:
  while parser.nextMatch(Whitespace - {'\n'}): discard
  for ch in parser.nextChars:
    case state
    of recordingLink:
      case ch
      of Whitespace - {'\n'}:
        # whitespace after link
        state = waitingTitle
      of '\n':
        result.finished = failOnNewline
        return
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
    of waitingTitle:
      case ch:
      of '"', '\'', '<':
        state = recordingTitle
        delim = if ch == '<': '>' else: ch
      of ')':
        result.finished = true
        return
      of '\n':
        result.finished = failOnNewline
        return
      of Whitespace - {'\n'}: discard
      else:
        dec parser.pos
        state = recordingTitle
        delim = ')'
    of recordingTitle:
      if not escaped:
        if ch == '\\':
          escaped = true
        elif ch == delim:
          if delim == ')':
            dec parser.pos
          state = waitingEnd
        elif ch == '\n':
          result.finished = failOnNewline
          return
        else:
          result.tip.add(ch)
      else:
        if ch notin {'\\', delim}:
          result.tip.add('\\')
        result.tip.add(ch)
        escaped = false
    of waitingEnd:
      case ch
      of ')':
        result.finished = true
        return
      of '\n':
        result.finished = failOnNewline
        return
      of Whitespace - {'\n'}: discard
      else:
        result.finished = false
        return
  result.finished = failOnNewline

proc parseReferenceName*(parser: MarggersParserVar, failed: var bool): NativeString =
  ## Does not reset position after failing.
  result = ""
  var
    openbracks = 1
    escaped = false
  for ch in parser.nextChars:
    if not escaped:
      case ch
      of '\\':
        escaped = true
      of '[':
        inc openbracks
        result.add('[')
      of ']':
        dec openbracks
        if openbracks == 0:
          return
        else:
          result.add(']')
      of '\n':
        failed = true
        return
      else:
        result.add(escapeHtmlChar(ch))
    else:
      result.add(
        case ch
        of '\\', '[', ']': toNativeString(ch)
        else: NativeString"\\" & escapeHtmlChar(ch))
      escaped = false
  failed = true

proc parseBracket*(image: bool, parser: MarggersParserVar, singleLine: SingleLineBool): MarggersElement =
  let canBeSub = not image and not parser.prevWhitespace(offset = -1)
  let firstPos = parser.pos
  let (textWorked, textElems) = parseDelimed(parser, "]", singleLine)
  inc parser.pos
  let secondPos = parser.pos - 2
  if textWorked != frDone:
    return newElem(noTag, textElems)
  let checkMark =
    if not image and textElems.len == 1 and textElems[0].isText and textElems[0].str.len == 1:
      case textElems[0].str[0]
      of ' ': 1u8
      of 'x': 2u8
      else: 0u8
    else: 0u8
  if parser.pos < parser.str.len:
    let initialPos = parser.pos
    parser.matchNext():
    of '(':
      let (linkWorked, link, tip) = parseLink(parser, failOnNewline = false)
      if linkWorked:
        result = MarggersElement(isText: false)
        if image:
          result.tag = img
          result.setLink(link)
          if secondPos - firstPos > 0:
            result.attr("alt", parser.str[firstPos..secondPos])
        else:
          result.tag = a
          result.content = textElems
          result.setLink(
            if link.len == 0 and textElems.len == 1 and textElems[0].isText:
              moveCompat(textElems[0].str)
            else:
              link)
        if tip.len != 0:
          result.attr("title", tip)
        return
      else:
        parser.pos = initialPos
    of '[':
      var refNameFailed = false
      var refName = parseReferenceName(parser, refNameFailed)
      if refNameFailed:
        parser.pos = initialPos
      else:
        if refName.len == 0: refName = parser.str[firstPos..secondPos]
        result = MarggersElement(isText: false)
        if image:
          result.tag = img
          if secondPos - firstPos > 0:
            result.attr("alt", parser.str[firstPos..secondPos])
        else:
          result.tag = a
          result.content = textElems
        parser.linkReferrers.mgetOrPut(refName, @[]).add(result)
        return
    else:
      dec parser.pos
  if image:
    # this could be used like a directive tag
    result = newElem(noTag, textElems)
  elif checkMark == 0:
    result = newElem(if canBeSub: sub else: (dec parser.pos; noTag), textElems)
  else:
    result = newElem(input)
    result.attr("type", "checkbox")
    result.attr("disabled", "")
    if checkMark == 2:
      result.attr("checked", "")

proc parseInline*(parser: MarggersParserVar, singleLine: SingleLineBool): seq[MarggersElement] {.inline.} =
  let (finishReason, elems) = parseDelimed(parser, "", singleLine)
  assert finishReason != frFailed
  result = elems

template parseSingleLine*(parser: MarggersParserVar): seq[MarggersElement] =
  parseInline(parser, singleLine = true)

template parseLine*(parser: MarggersParserVar): seq[MarggersElement] =
  parseInline(parser, singleLine = false)

const
  SpecialLineTags* = {ul, ol, blockquote}
  IdStarts* = {'(', '[', '{', ':'}
  LegalId* = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
  InlineWhitespace* = Whitespace - {'\r', '\n'}

proc parseId*(parser: MarggersParserVar, startChar: char): NativeString =
  let idDelim =
    case startChar
    of '(': ')'
    of '[': ']'
    of '{': '}'
    else: '\0'
  result = NativeString""
  while (let ch = parser.get(); parser.nextMatch(LegalId)): result.add(ch)
  discard parser.nextMatch(idDelim)

proc parseTopLevel*(parser: MarggersParserVar): seq[MarggersElement] =
  var lastElement: MarggersElement
  # todo: move ^ to parser so top level can be individually parsed
  template add(elem: MarggersElement) =
    result.add(elem)
    lastElement = nil
  for firstCh in parser.nextChars:
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
        elif parser.nextMatch(IdStarts, offset = 1):
          var item = newElem(li)
          item.attr("id", parser.parseId(parser.get(-1)))
          item.content = parseSingleLine(parser)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseSingleLine(parser))
      of ol:
        var i = 0
        while parser.peekMatch(Digits, offset = i): inc i
        if parser.nextMatch('.', offset = i):
          let item = newElem(li)
          if (let ch = parser.get(); parser.nextMatch(IdStarts)):
            item.attr("id", parser.parseId(ch))
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
            if parser.peekPrevMatch("  "):
              lastElement.add(newElem(br))
          else:
            lastElement[^1] = lastElement[^1].paragraphIfText
            result.add(lastElement)
            if parser.peekPrevMatch("  "):
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
      of {low(KnownTags)..high(KnownTags)} - SpecialLineTags:
        add(paragraphIfText(lastElement))
        dec parser.pos
    else:
      case firstCh
      of InlineWhitespace:
        if result.len != 0 and not result[^1].isText and
           result[^1].tag in SpecialLineTags and
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
        parser.matchNext:
        of '|': style lastElement, "text-align:center"
        of '<': style lastElement, "text-align:left"
        of '>': style lastElement, "text-align:right"
        if (let ch = parser.get(); parser.nextMatch(IdStarts)):
          lastElement.attr("id", parser.parseId(ch))
        lastElement.add(parseSingleLine(parser))
      of '*', '-', '+':
        if parser.nextMatch(Whitespace, offset = 1):
          lastElement = newElem(ul)
          let item = newElem(li)
          item.add(parseSingleLine(parser))
          lastElement.add(item)
        elif parser.nextMatch(IdStarts, offset = 1):
          lastElement = newElem(ul)
          var item = newElem(li)
          item.attr("id", parser.parseId(parser.get(-1)))
          item.content = parseSingleLine(parser)
          lastElement.add(item)
        else:
          lastElement = newElem(p, parseLine(parser))
      of Digits:
        let originalPos = parser.pos
        inc parser.pos
        while parser.nextMatch(Digits): discard
        if parser.nextMatch('.'):
          lastElement = newElem(ol)
          var item = newElem(li)
          if (let ch = parser.get(); parser.nextMatch(IdStarts)):
            item.attr("id", parser.parseId(ch))
          item.add(parseSingleLine(parser))
          lastElement.add(item)
        else:
          parser.pos = originalPos
          lastElement = newElem(p, parseLine(parser))
      of '>':
        lastElement = newElem(blockquote)
        inc parser.pos
        if (let ch = parser.get(); parser.nextMatch(IdStarts)):
          lastElement.attr("id", parser.parseId(ch))
        lastElement.add(newElem(p, parseSingleLine(parser)))
      of '[':
        # reference link
        let initialPos = parser.pos
        inc parser.pos
        var refNameFailed = false
        let refName = parseReferenceName(parser, refNameFailed)
        if not refNameFailed and (inc parser.pos; parser.nextMatch(':')) and
          (let (correct, link, tip) = parseLink(parser, failOnNewline = true);
            correct): # smooth
          for el in parser.linkReferrers.getOrDefault(refName, @[]):
            el.setLink(link)
            if tip.len != 0:
              el.attr("title", tip)
        else:
          parser.pos = initialPos
          lastElement = newElem(p, parseLine(parser))
      elif parser.nextMatch("```"):
        add(parseCodeBlock(parser, '`'))
      elif parser.nextMatch("~~~"):
        add(parseCodeBlock(parser, '~'))
      else:
        lastElement = newElem(p, parseLine(parser))
  if not lastElement.isNil:
    result.add(lastElement)
