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

  findMatchingSiblings: (formats = {}) ->
    prevLeaves = []
    nextLeaves = []

    prev = @prev
    while prev?
      if prev.hasFormats(formats)
        prevLeaves.push(prev)
        prev = prev.prev
      else
        prev = null

    next = @next
    while next?
      if next.hasFormats(formats)
        nextLeaves.push(next)
        next = next.next
      else
        next = null

    return [prevLeaves, nextLeaves]

  hasFormats: (formats) ->
    leafHasFormats = true
    for formatKey of formats
      if @formats[formatKey] != formats[formatKey]
        leafHasFormats = false

    return leafHasFormats


module.exports = Leaf
