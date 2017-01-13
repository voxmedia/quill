_   = require('lodash')
dom = require('../lib/dom')


camelize = (str) ->
  str = str.replace(/(?:^|[-_])(\w)/g, (i, c) ->
    return if c then c.toUpperCase() else ''
  )
  return str.charAt(0).toLowerCase() + str.slice(1)


class Normalizer
  @ALIASES: {
    'STRONG' : 'B'
    'EM'     : 'I'
    'DEL'    : 'S'
    'STRIKE' : 'S'
  }

  @ATTRIBUTES: {
    'color': 'color'
    'face' : 'fontFamily'
    'size' : 'fontSize'
  }

  constructor: ->
    @whitelist =
      styles: {}
      tags: {}
    @whitelist.tags[dom.DEFAULT_BREAK_TAG] = true
    @whitelist.tags[dom.DEFAULT_BLOCK_TAG] = true
    @whitelist.tags[dom.DEFAULT_INLINE_TAG] = true

  addFormat: (config) ->
    @whitelist.tags[config.tag] = true if config.tag?
    @whitelist.tags[config.parentTag] = true if config.parentTag?
    @whitelist.styles[config.style] = true if config.style?

  normalizeLine: (lineNode) ->
    lineNode = Normalizer.wrapInline(lineNode)
    lineNode = Normalizer.handleBreaks(lineNode)
    if lineNode.tagName == 'LI'
      Normalizer.flattenList(lineNode)
    lineNode = Normalizer.pullBlocks(lineNode)
    lineNode = this.normalizeNode(lineNode)
    Normalizer.unwrapText(lineNode)
    lineNode = lineNode.firstChild if lineNode? and dom.WRAPPER_TAGS[lineNode.tagName]?
    return lineNode

  normalizeNode: (node) ->
    return node if dom(node).isTextNode()
    _.each(Normalizer.ATTRIBUTES, (style, attribute) ->
      if node.hasAttribute(attribute)
        value = node.getAttribute(attribute)
        value = dom.convertFontSize(value) if attribute == 'size'
        node.style[style] = value
        node.removeAttribute(attribute)
    )
    if !dom.BLOCK_TAGS[node.tagName]
      # Turn inline fontWeight styling into <b> tags
      if node.style.fontWeight == 'bold' or node.style.fontWeight > 500
        node.style.fontWeight = null
        dom(node).wrap(document.createElement('b'))
        node = node.parentNode
      # Turn inline fontStyle styling into <i> tags
      if node.style.fontStyle == 'italic'
        node.style.fontStyle = null
        dom(node).wrap(document.createElement('i'))
        node = node.parentNode
      # Turn inline textDecoration styling into <s> tags
      if node.style.textDecoration == 'line-through'
        node.style.textDecoration = null
        dom(node).wrap(document.createElement('s'))
        node = node.parentNode
      # Turn inline textDecoration styling into <u> tags
      if node.style.textDecoration == 'underline'
        node.style.textDecoration = null
        dom(node).wrap(document.createElement('u'))
        node = node.parentNode
    this.whitelistStyles(node)
    return this.whitelistTags(node)

  whitelistStyles: (node) ->
    original = dom(node).styles()
    styles = _.omit(original, (value, key) =>
      return !@whitelist.styles[camelize(key)]?
    )
    if Object.keys(styles).length < Object.keys(original).length
      if Object.keys(styles).length > 0
        dom(node).styles(styles, true)
      else
        node.removeAttribute('style')

  whitelistTags: (node) ->
    return node unless dom(node).isElement()
    if Normalizer.ALIASES[node.tagName]?
      node = dom(node).switchTag(Normalizer.ALIASES[node.tagName]).get()
    else if !@whitelist.tags[node.tagName]?
      if dom.BLOCK_TAGS[node.tagName]?
        node = dom(node).switchTag(dom.DEFAULT_BLOCK_TAG).get()
      else if !node.hasAttributes() and node.firstChild?
        node = dom(node).unwrap()
      else
        node = dom(node).switchTag(dom.DEFAULT_INLINE_TAG).get()
    return node

  @flattenList: (listNode) ->
    ref = listNode.nextSibling
    innerItems = _.map(listNode.querySelectorAll('li'))
    innerItems.forEach((item) ->
      listNode.parentNode.insertBefore(item, ref)
      ref = item.nextSibling
    )
    innerLists = _.map(listNode.querySelectorAll(Object.keys(dom.LIST_TAGS).join(',')))
    innerLists.forEach((list) ->
      dom(list).remove()
    )

  @mergeAdjacentLists: (listNode) ->
    if listNode.nextSibling?.tagName == listNode.tagName
      dom(listNode).merge(listNode.nextSibling)

  # Make sure descendant break tags are not causing multiple lines to be rendered
  @handleBreaks: (lineNode) ->
    breaks = _.map(lineNode.querySelectorAll(dom.DEFAULT_BREAK_TAG))
    _.each(breaks, (br) =>
      if br.nextSibling?
        dom(br.nextSibling).splitBefore(lineNode.parentNode)
    )
    return lineNode

  # Removes unnecessary tags but does not modify line contents
  @optimizeLine: (lineNode) ->
    lineNode.normalize()
    lineNodeLength = dom(lineNode).length()
    if lineNode.tagName == 'LI'
      Normalizer.mergeAdjacentLists(lineNode.parentNode)
    nodes = dom(lineNode).descendants()
    while nodes.length > 0
      node = nodes.pop()
      continue unless node?.parentNode?
      continue if dom.EMBED_TAGS[node.tagName]?

      if node.tagName == dom.DEFAULT_BREAK_TAG
        # Remove unneeded BRs
        dom(node).remove() unless lineNodeLength == 0
        continue

      if dom(node).length() == 0
        nodes.push(node.nextSibling)
        dom(node).unwrap()
        continue

      # If node is an only child, and parent is not the lineNode,
      # normalize nesting order
      if node.parentNode != lineNode and !node.previousSibling? and !node.nextSibling?
        node = @optimizeNesting(node, lineNode)
        # check next sibling again in case it is similar enough to merge
        if node.nextSibling?
          nodes.push(node.nextSibling)

      # Merge similar nodes
      if node.previousSibling? and node.tagName == node.previousSibling.tagName
        if _.isEqual(dom(node).attributes(), dom(node.previousSibling).attributes())
          nodes.push(node.firstChild)
          dom(node.previousSibling).merge(node)

  # If a <span>, move attributes as high in the tree as possible and unwrap,
  # otherwise, alphabetize nesting order of tag names (prefer <a> to be outer-most)
  @optimizeNesting: (node, root) ->
    if node.tagName == dom.DEFAULT_INLINE_TAG
      # find all parents with only one child, up to the root
      parents = []
      next = node.parentNode
      while next != root and next.firstChild == next.lastChild
        parents.push(next)
        next = next.parentNode
      # choose the parent with the earliest tag name, alphabetically
      target = _.sortBy(parents, 'tagName')[0]
      # Move attributes to the target, and unwrap
      for name, value of dom(node).attributes()
        if name == 'class' && target.hasAttribute('class')
          value = [target.getAttribute('class'), value].join(' ')
        target.setAttribute(name, value)
      dom(node).unwrap()
      return target
    else if node.parentNode.tagName > node.tagName
      # Order tag nesting alphabetically (parent->child : A->Z)
      dom(node).moveChildren(node.parentNode)
      dom(node.parentNode).wrap(node)
      return node
    else
      return node

  # Make sure descendants are all inline elements
  @pullBlocks: (lineNode) ->
    curNode = lineNode.firstChild
    while curNode?
      if dom.BLOCK_TAGS[curNode.tagName]? and curNode.tagName != 'LI'
        dom(curNode).isolate(lineNode.parentNode)
        if !dom.WRAPPER_TAGS[curNode.tagName]? or !curNode.firstChild
          dom(curNode).unwrap()
          Normalizer.pullBlocks(lineNode)
        else
          dom(curNode.parentNode).unwrap()
          lineNode = curNode unless lineNode.parentNode?    # May have just unwrapped lineNode
        break
      curNode = curNode.nextSibling
    return lineNode

  @stripComments: (html) ->
    return html.replace(/<!--[\s\S]*?-->/g, '')

  @stripWhitespace: (html) ->
    html = html.trim()
    # Replace all newline characters
    html = html.replace(/(\r?\n|\r)+/g, ' ')
    # Collapse whitespace between tags, requires &nbsp; for legitmate spaces
    html = html.replace(/\>\s+\</g, '> <')
    return html

  @stripStyleTags: (html) ->
    return html.replace(/<style.*?<\/style>/g, '')

  # Wrap inline nodes with block tags
  @wrapInline: (lineNode) ->
    return lineNode if dom.BLOCK_TAGS[lineNode.tagName]?
    blockNode = document.createElement(dom.DEFAULT_BLOCK_TAG)
    lineNode.parentNode.insertBefore(blockNode, lineNode)
    while lineNode? and !dom.BLOCK_TAGS[lineNode.tagName]?
      nextNode = lineNode.nextSibling
      blockNode.appendChild(lineNode)
      lineNode = nextNode
    return blockNode

  @unwrapText: (lineNode) ->
    spans = _.map(lineNode.querySelectorAll(dom.DEFAULT_INLINE_TAG))
    _.each(spans, (span) ->
      dom(span).unwrap() if (!span.hasAttributes())
    )


module.exports = Normalizer
