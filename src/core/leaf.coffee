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
    this.rebuild()

  deleteText: (offset, length) ->
    return unless length > 0
    @text = @text.slice(0, offset) + @text.slice(offset + length)
    if dom.EMBED_TAGS[@node.tagName]?
      textNode = document.createTextNode(@text)
      @node = dom(@node).replace(textNode)
    else
      dom(@node).text(@text)
    this.rebuild()

  insertText: (offset, text) ->
    @text = @text.slice(0, offset) + text + @text.slice(offset)
    if dom(@node).isTextNode()
      dom(@node).text(@text)
    else
      textNode = document.createTextNode(text)
      if @node.tagName == dom.DEFAULT_BREAK_TAG
        @node = dom(@node).replace(textNode)
      else
        @node.appendChild(textNode)
        @node = textNode
    this.rebuild()

  rebuild: ->
    @length = @text.length
    dom(@node).data(Leaf.DATA_KEY, this)
    return true

module.exports = Leaf
