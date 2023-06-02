import strutils, tables
import ./common, ./element, parser/[defs, utils]

when not marggersNoDefaultHtmlHandler:
  import ./singlexml

when marggersSingleLineStaticBool:
  type SingleLineBool = static bool
else:
  type SingleLineBool = bool

using
  parser: var MarggersParser
  options: static MarggersOptions

proc parseBracket*(parser; options; image: bool, singleLine: SingleLineBool): MarggersElement

proc parseCurly*(parser; options): NativeString =
  ## Parses a curly bracket element.
  ## 
  ## If `-d:marggersCurlyNoHtmlEscape` is defined, initial `!` characters
  ## are ignored and no HTML chars are escaped.
  result = ""
  when options.curlyNoHtmlEscape:
    discard parser.nextMatch('!')
  else:
    let noHtmlEscape = parser.nextMatch('!') or parser.options.curlyNoHtmlEscape
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
          when options.curlyNoHtmlEscape:
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

proc parseAmpStr*(parser; options): NativeString =
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

proc parseCodeBlockStr*(parser; options; delimChar: char): tuple[language, code: NativeString] =
  result = (NativeString"", NativeString"")
  var delimLen = 3
  while parser.nextMatch(delimChar): inc delimLen
  while parser.nextMatch(Whitespace): discard
  withOptions(parser, options, not options.codeBlockLanguageHandler.isNil):
    const LegalLanguage = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
    while (let ch = parser.get(); parser.nextMatch(LegalLanguage)):
      result.language.add(ch)
  do: discard
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

proc parseCodeBlock*(parser; options; delimChar: char): MarggersElement {.inline.} =
  let str = parseCodeBlockStr(parser, options, delimChar)
  result = newElem(pre, @[newStr(str.code)])
  withOptions(parser, options, not options.codeBlockLanguageHandler.isNil):
    if str.language.len != 0:
      options.codeBlockLanguageHandler(result, str.language)

type
  DelimFinishReason* = enum
    frDone
    frReachedEnd
    frFailed

proc parseDelimed*(parser; options; delim: string, singleLine: SingleLineBool): (DelimFinishReason, seq[MarggersElement]) =
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
      let initialPos = parser.pos

      when marggersDelimedUseSubstrs:
        var matchLen: int
        let maxIndexAfter3 = min(parser.pos + 3, parser.str.len - 1)
        var substrs: array[4, NativeString]
        for i in parser.pos..maxIndexAfter3:
          substrs[i - parser.pos] = parser.str[parser.pos..i]

        template check(s: string): bool =
          substrs[s.len - 1] == s and (matchLen = s.len; true)

        template nextMatch(parser: var MarggersParser, pat: string): bool =
          check(pat) and (parser.pos += matchLen; true)

      proc parseAux(tag: KnownTags, del: string, parser: var MarggersParser,
        acceptedReasons = {frDone}): DelimFinishReason =
        let currentPos = parser.pos
        let (finishReason, parsedElems) = parseDelimed(parser, options, del, singleLine)
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

      proc bracket(image: bool, parser: var MarggersParser): DelimFinishReason =
        let elem = parseBracket(parser, options, image, singleLine)
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
          let (finishReason, parsedElems) = parseDelimed(parser, options, "**", singleLine)
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
          let (finishReason, parsedElems) = parseDelimed(parser, options, "__", singleLine)
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
        when marggersSingleLineStaticBool:
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
      elif not singleLine and (parser.nextMatch("\r\n") or parser.nextMatch("\n")):
        dec parser.pos
        withOptions(parser, options, options.insertLineBreaks):
          add(newElem(br))
        do:
          add(ch)
      of "  \r\n", "  \n":
        dec parser.pos
        add(newElem(br))
      of "```":
        add(parseCodeBlock(parser, options, '`'))
      of "~~~":
        add(parseCodeBlock(parser, options, '~'))
      of "^(": parse(sup, ")")
      of "**": parse(strong, "**")
      of "__": parse(u, "__")
      of "~~": parse(s, "~~")
      of "![":
        let reason = bracket(image = true, parser)
        if reason in {frFailed, frReachedEnd}:
          return (reason, elems)
      of '{':
        add(parseCurly(parser, options))
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
        var
          change: bool
          pos: int
        withOptions(parser, options, not options.inlineHtmlHandler.isNil):
          (change, pos) = options.inlineHtmlHandler(parser.str, parser.pos)
        do:
          (change, pos) = when marggersNoDefaultHtmlHandler:
            (false, 0)
          else:
            parseXml($parser.str, parser.pos)
        if change:
          add(parser.str[parser.pos ..< pos])
          parser.pos = pos - 1
        else:
          add("&lt;")
      of '>':
        dec parser.pos
        add("&gt;")
      of '&':
        add(parseAmpStr(parser, options))
      of '\\':
        dec parser.pos
        escaped = true
      else:
        add(ch)
    else:
      add(ch)
      escaped = false
  result = (frReachedEnd, elems)

proc parseLink*(parser; options; failOnNewline: bool): tuple[finished: bool, link: Link] =
  # why is this 100 lines
  type State = enum waitingLink, recordingLink, waitingExtra, recordingTitle, waitingEnd
  var
    state: State
    delim: char
    escaped = false
    openparens = 1
    urlNum = -1
  template urlAdd(x) =
    if urlNum < 0:
      result.link.url.add(x)
    else:
      result.link.altUrls[urlNum].add(x)
  template finish(success = true) =
    result.finished = success
    return
  result.link.url = NativeString("")
  # skip first whitespace:
  while parser.nextMatch(Whitespace - {'\n'}): discard
  for ch in parser.nextChars:
    case state
    of waitingLink:
      case ch
      of Whitespace - {'\n'}: discard
      of '\n': finish(failOnNewline)
      else:
        dec parser.pos
        state = recordingLink
    of recordingLink:
      case ch
      of Whitespace - {'\n'}:
        # whitespace after link
        state = waitingExtra
      of '\n':
        finish(failOnNewline)
      of '(':
        inc openparens
        urlAdd('(')
      of ')':
        dec openparens
        if openparens == 0:
          finish()
        else:
          urlAdd(')')
      else: urlAdd(ch)
    of waitingExtra:
      case ch:
      of '"', '\'', '<':
        state = recordingTitle
        delim = if ch == '<': '>' else: ch
      of '|':
        state = waitingLink
        result.link.altUrls.add(NativeString(""))
        inc urlNum
      of ')':
        finish()
      of '\n':
        finish(failOnNewline)
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
          finish(failOnNewline)
        else:
          result.link.tip.add(ch)
      else:
        if ch notin {'\\', delim}:
          result.link.tip.add('\\')
        result.link.tip.add(ch)
        escaped = false
    of waitingEnd:
      case ch
      of ')':
        finish()
      of '\n':
        finish(failOnNewline)
      of Whitespace - {'\n'}: discard
      else:
        finish(false)
  result.finished = failOnNewline

proc parseReferenceName*(parser; options; failed: var bool): NativeString =
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

proc parseBracket*(parser; options; image: bool, singleLine: SingleLineBool): MarggersElement =
  let canBeSub = not image and not parser.prevWhitespace(offset = -1)
  let firstPos = parser.pos
  let (textWorked, textElems) = parseDelimed(parser, options, "]", singleLine)
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
      var (linkWorked, link) = parseLink(parser, options, failOnNewline = false)
      if linkWorked:
        if link.url.len == 0 and textElems.len == 1 and textElems[0].isText:
          link.url = strip(textElems[0].str)
        if image:
          result = MarggersElement(isText: false, tag: img)
          if secondPos - firstPos > 0:
            result.attrEscaped("alt", parser.str[firstPos..secondPos])
        else:
          result = MarggersElement(isText: false, tag: a)
          result.content = textElems
        if link.tip.len != 0:
          result.attrEscaped("title", link.tip)
        parser.setLink(options, result, link)
        return
      else:
        parser.pos = initialPos
    of '[':
      var refNameFailed = false
      var refName = parseReferenceName(parser, options, refNameFailed)
      if refNameFailed:
        parser.pos = initialPos
      else:
        if refName.len == 0: refName = parser.str[firstPos..secondPos]
        result = MarggersElement(isText: false)
        if image:
          result.tag = img
          if secondPos - firstPos > 0:
            result.attrEscaped("alt", parser.str[firstPos..secondPos])
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

proc parseInline*(parser; options; singleLine: SingleLineBool): seq[MarggersElement] {.inline.} =
  let (finishReason, elems) = parseDelimed(parser, options, "", singleLine)
  assert finishReason != frFailed
  result = elems

template parseSingleLine*(parser; options): seq[MarggersElement] =
  parseInline(parser, options, singleLine = true)

template parseLine*(parser; options): seq[MarggersElement] =
  parseInline(parser, options, singleLine = false)

const
  SpecialLineTags* = {ul, ol, blockquote}
  IdStarts* = {'(', '[', '{', ':'}
  LegalId* = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
  InlineWhitespace* = Whitespace - {'\r', '\n'}

proc parseId*(parser; startChar: char): NativeString =
  let idDelim =
    case startChar
    of '(': ')'
    of '[': ']'
    of '{': '}'
    else: '\0'
  result = NativeString""
  while (let ch = parser.get(); parser.nextMatch(LegalId)): result.add(ch)
  discard parser.nextMatch(idDelim)

proc parseTopLevel*(parser; options): seq[MarggersElement] =
  var lastEmptyLine = false
  for firstCh in parser.nextChars:
    var context: MarggersElement
    block:
      var i = 0
      while i < parser.contextStack.len:
        let c = parser.contextStack[i]
        case c.tag
        of ul:
          if parser.nextMatch({'*', '-', '+'}):
            while parser.nextMatch(InlineWhitespace): discard
          else: break
        of ol:
          let originalPos = parser.pos
          while parser.nextMatch(Digits): discard
          if parser.nextMatch('.'):
            while parser.nextMatch(InlineWhitespace): discard
          else:
            parser.pos = originalPos
            break
        of blockquote:
          if parser.nextMatch('>'):
            while parser.nextMatch(InlineWhitespace): discard
          else: break
        else: discard # unreachable
        context = c
        inc i
      parser.contextStack.setLen(i)

    template addElement(elem: MarggersElement): untyped =
      let el = elem
      if not context.isNil:
        context.add(el)
      else:
        result.add(el)
    
    template addContext(elem: MarggersElement): untyped =
      let el = elem
      addElement(el)
      parser.contextStack.add(el)
      context = el
    
    proc addLine(
      parser: var MarggersParser;
      options: static MarggersOptions;
      context: MarggersElement;
      result: var seq[MarggersElement];
      lastEmptyLine: bool;
      rawLine: static bool = false) {.nimcall.} =
      template rawOrNot(t, els): untyped =
        when rawLine:
          els
        else:
          newElem(t, els)
      if not context.isNil:
        case context.tag
        of ol, ul:
          context.add rawOrNot(li, parseSingleLine(parser, options))
        of blockquote:
          let c = parseSingleLine(parser, options)
          if not lastEmptyLine and context.content.len != 0 and
            (let last = context[^1]; not last.isText and last.tag == p):
            addNewline(parser, options, last)
            last.add(c)
          else:
            context.add rawOrNot(p, c)
        else: discard # unreachable
      else:
        result.add rawOrNot(p, parseLine(parser, options))
    
    template addLine(rawLine: static bool = false) =
      bind options
      addLine(parser, options, context, result, lastEmptyLine, rawLine)

    case parser.get()
    of '\r', '\n':
      discard parser.nextMatch("\r\n") or parser.nextMatch("\n")
      dec parser.pos
      lastEmptyLine = true
      continue
    of InlineWhitespace:
      let last =
        if not context.isNil and context.content.len != 0:
          context[^1]
        elif result.len != 0:
          result[^1]
        else: nil
      if not last.isNil and not last.isText and
        last.tag in SpecialLineTags and
        (let last2 = last[^1]; last2.content.len != 0):
        addNewline(parser, options, last2)
        last2.add(parseLine(parser, options))
      else:
        addLine()
    of '#':
      if context.isNil or context.tag in {blockquote, p}:
        while not context.isNil and context.tag == p:
          let last = parser.contextStack.len - 1
          context = parser.contextStack[last]
          parser.contextStack.setLen(last)
          if last == 0: break
        var level = 1
        while level < 6 and parser.peekMatch('#', offset = level): inc level
        parser.pos += level
        let header = newElem(KnownTags(static(h1.int - 1) + level))
        parser.matchNext:
        of '|': style header, "text-align:center"
        of '<': style header, "text-align:left"
        of '>': style header, "text-align:right"
        if (let ch = parser.get(); parser.nextMatch(IdStarts)):
          header.attr("id", parser.parseId(ch))
        header.add(parseSingleLine(parser, options))
        addElement(header)
      else:
        addLine()
    of '*', '-', '+':
      if parser.nextMatch(InlineWhitespace, offset = 1):
        addContext newElem(ul)
        addLine()
      elif parser.nextMatch(IdStarts, offset = 1):
        let list = newElem(ul)
        var item = newElem(li)
        item.attr("id", parser.parseId(parser.get(-1)))
        item.content = parseSingleLine(parser, options)
        list.add(item)
        addContext(list)
      else:
        addLine()
    of Digits:
      let originalPos = parser.pos
      inc parser.pos
      while parser.nextMatch(Digits): discard
      if parser.nextMatch('.'):
        let list = newElem(ol)
        var item = newElem(li)
        if (let ch = parser.get(); parser.nextMatch(IdStarts)):
          item.attr("id", parser.parseId(ch))
        item.add(parseSingleLine(parser, options))
        list.add(item)
        addContext(list)
      else:
        parser.pos = originalPos
        addLine()
    of '>':
      let quote = newElem(blockquote)
      inc parser.pos
      if (let ch = parser.get(); parser.nextMatch(IdStarts)):
        quote.attr("id", parser.parseId(ch))
      addContext(quote)
      addLine()
    of '[':
      # reference link
      let initialPos = parser.pos
      inc parser.pos
      var refNameFailed = false
      let refName = parseReferenceName(parser, options, refNameFailed)
      if not refNameFailed and (inc parser.pos; parser.nextMatch(':')) and
        (let (correct, link) = parseLink(parser, options, failOnNewline = true);
          correct): # smooth
        for el in parser.linkReferrers.getOrDefault(refName, @[]):
          if link.tip.len != 0:
            el.attrEscaped("title", link.tip)
          parser.setLink(options, el, link)
      else:
        parser.pos = initialPos
        addLine()
    of '|':
      withOptions(parser, options, options.disableTextAlignExtension):
        addLine()
      do:
        if not context.isNil:
          addLine()
        else:
          var align: string
          parser.matchNext:
          of '<': align = "text-align:left"
          of '>': align = "text-align:right"
          else: align = "text-align:center"
          let el = newElem(p, parseLine(parser, options))
          style el, align
          result.add(el)
    elif parser.nextMatch("```"):
      addElement(parseCodeBlock(parser, options, '`'))
    elif parser.nextMatch("~~~"):
      addElement(parseCodeBlock(parser, options, '~'))
    elif parser.peekMatch("{!"):
      addLine(rawLine = true)
    else:
      addLine()
    
    lastEmptyLine = false

when isMainModule:
  import ../marggers
  discard parseMarggers("# hello")
