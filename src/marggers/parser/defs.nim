import ".."/[common, element], tables

type
  Link* = object
    url*: NativeString
    tip*: NativeString
    altUrls*: seq[NativeString]

  MarggersOptions* {.byref.} = object
    curlyNoHtmlEscape*: bool
      ## Define this to disable HTML escaping inside curly brackets
      ## (normally only formatting is disabled).
      ## 
      ## `true` value at compile time overrides runtime value.
    insertLineBreaks*: bool
      ## Inserts <br> on newlines.
      ## 
      ## `true` value at compile time overrides runtime value.
    inlineHtmlHandler*: proc (str: NativeString, i: int): (bool, int) {.nimcall, gcsafe.}
      ## Should parse a single HTML element starting at `i` in `str`,
      ## returning `(true, pos)` if an HTML element has been correctly parsed
      ## and `pos` is the immediate index after it or `(false, _)` if it has
      ## not been correctly parsed.
      ## 
      ## Not nil value at compile time overrides runtime value.
      ## 
      ## See `singlexml.parseXml <singlexml.html#parseXml,string,int>`_.
    codeBlockLanguageHandler*: proc (codeBlock: MarggersElement, language: NativeString) {.nimcall, gcsafe.}
      ## Callback to use when a code block has a language attached.
      ## `codeBlock` is modifiable.
      ## 
      ## If nil, any language name will be passed directly to the code block.
      ## 
      ## Not nil value at compile time overrides runtime value.
    setLinkHandler*: proc (element: MarggersElement, link: Link) {.nimcall, gcsafe.}
      ## Handles when an element gets a link. `element` is modifiable.
      ## 
      ## Covers []() and ![]() syntax. If nil, `setLinkDefault` is called.
      ## 
      ## Not nil value at compile time overrides runtime value.
    disableTextAlignExtension*: bool
      ## Disables non-standard text align extension for paragraphs.
      ## 
      ## `true` value at compile time overrides runtime value.
  
  MarggersParser* {.byref.} = object
    ## A parser object.
    options*: MarggersOptions
      ## Runtime options for the parser.
      ## Overriden by compile time options.
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int
    contextStack*: seq[MarggersElement]
      ## Stack of current top level contexts,
      ## like lists or blockquotes.
    linkReferrers*: Table[NativeString, seq[MarggersElement]]
      ## Table of link references to elements that use the reference.
      ## During parsing, when a reference link is found, it will modify
      ## elements that use the reference and add them the link.
      ## After parsing is done, if there are elements left in this table,
      ## then some references were left unset.

const defaultParserOptions* = MarggersOptions(curlyNoHtmlEscape: marggersCurlyNoHtmlEscape)

func initMarggersParser*(text: sink NativeString): MarggersParser {.inline.} =
  MarggersParser(str: text, pos: 0)
