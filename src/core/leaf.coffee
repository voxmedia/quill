_          = require('lodash')
dom        = require('../lib/dom')
Format     = require('./format')
LinkedList = require('../lib/linked-list')


class Leaf extends LinkedList.Node
  @DATA_KEY: 'leaf'

  @isLeafNode: (node) ->
    return dom(node).isTextNode() or !node.firstChild?

  constructor: (@node, formats) ->
    @formats = _.clone(formats)
    @text = dom(@node).text()
    @length = @text.length
    dom(@node).data(Leaf.DATA_KEY, this)

  deleteText: (offset, length) ->
    return unless length > 0
    @text = @text.slice(0, offset) + @text.slice(offset + length)
    @length = @text.length
    if dom.EMBED_TAGS[@node.tagName]?
      textNode = document.createTextNode(@text)
      dom(textNode).data(Leaf.DATA_KEY, this)
      @node = dom(@node).replace(textNode).get()
    else
      dom(@node).text(@text)

  insertText: (offset, text) ->
    @text = @text.slice(0, offset) + text + @text.slice(offset)
    if dom(@node).isTextNode()
      dom(@node).text(@text)
    else
      textNode = document.createTextNode(text)
      dom(textNode).data(Leaf.DATA_KEY, this)
      if @node.tagName == dom.DEFAULT_BREAK_TAG
        @node = dom(@node).replace(textNode).get()
      else
        @node.appendChild(textNode)
        @node = textNode
    @length = @text.length

  findAdjacentLeaves: (offset, formats = {}) ->
    leaves = [this]

    # Collect previous leaves + update offset from click-point
    prev = @prev;
    while prev?
      if prev.hasFormats(formats)
        offset += prev.length
        leaves = [prev].concat(leaves)
        prev = prev.prev
      else
        prev = null

    # Collect next leaves
    next = @next;
    while next?
      if next.hasFormats(formats)
        leaves = leaves.concat([next])
        next = next.next
      else
        next = null

    return [leaves, offset]

  hasFormats: (formats) ->
    return Object.keys(formats).every((formatKey) ->
      return @formats[formatKey] == formats[formatKey]
    )


module.exports = Leaf
