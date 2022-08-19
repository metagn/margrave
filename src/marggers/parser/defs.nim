import ".."/[common, element], tables

type
  MarggersOptions* {.byref.} = object
    curlyNoHtmlEscape*: bool
      ## Define this to disable HTML escaping inside curly brackets
      ## (normally only formatting is disabled).
      ## 
      ## Compile time option overrides runtime option when `true`.
    inlineHtmlHandler*: proc (str: NativeString, i: int): (bool, int) {.nimcall.}
      ## Should parse a single HTML element starting at `i` in `str`,
      ## returning `(true, pos)` if an HTML element has been correctly parsed
      ## and `pos` is the immediate index after it or `(false, _)` if it has
      ## not been correctly parsed.
      ## 
      ## Compile time option overrides runtime option when not nil.
      ## 
      ## See `singlexml.parseXml <singlexml.html#parseXml,string,int>`_.
    codeBlockLanguageHandler*: proc (codeBlock: MarggersElement, language: NativeString) {.nimcall.}
      ## Callback to use when a code block has a language attached.
      ## `codeBlock` is modifiable.
      ## 
      ## If nil, any language name will be passed directly to the code block.
      ## 
      ## Compile time option overrides runtime option when not nil.
    setLinkHandler*: proc (element: MarggersElement, link: NativeString) {.nimcall.}
      ## Handles when an element gets a link. `element` is modifiable.
      ## 
      ## Covers []() and ![]() syntax. If nil, `setLinkDefault` is called.
      ## 
      ## Compile time option overrides runtime option when not nil.
  
  MarggersParser* {.byref.} = object
    ## A parser object.
    options*: MarggersOptions
      ## Runtime options for the parser.
      ## Overriden by compile time options.
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int
    topLevelLast*: MarggersElement
      ## Last element parsed at top level.
      ## 
      ## Nil if the last element is complete, i.e. 2 newlines were parsed.
    linkReferrers*: Table[NativeString, seq[MarggersElement]]
      ## Table of link references to elements that use the reference.
      ## During parsing, when a reference link is found, it will modify
      ## elements that use the reference and add them the link.
      ## After parsing is done, if there are elements left in this table,
      ## then some references were left unset.

const defaultParserOptions* = MarggersOptions(curlyNoHtmlEscape: marggersCurlyNoHtmlEscape)

func initMarggersParser*(text: sink NativeString): MarggersParser {.inline.} =
  MarggersParser(str: text, pos: 0)
