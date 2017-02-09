Quill         = require('../quill')
EventEmitter2 = require('eventemitter2').EventEmitter2
_             = Quill.require('lodash')
dom           = Quill.require('dom')
Range         = Quill.require('range')


class MultiCursor extends EventEmitter2
  @DEFAULTS:
    template:
     '<span class="cursor-flag"></span>
      <span class="cursor-caret"></span>
      <div class="cursor-highlights"></div>'
    timeout: 2500

  @events:
    CURSOR_ADDED: 'cursor-addded'
    CURSOR_MOVED: 'cursor-moved'
    CURSOR_REMOVED: 'cursor-removed'

  constructor: (@quill, options = {}) ->
    @options = _.defaults(options, MultiCursor.DEFAULTS)
    @cursors = {}
    @container = @quill.addContainer('ql-multi-cursor', true)
    @quill.on(@quill.constructor.events.TEXT_CHANGE, _.bind(this._applyDelta, this))
    window.addEventListener('resize', _.throttle(_.bind(this.update, this), 200))

  clearCursors: ->
    _.each(Object.keys(@cursors), _.bind(this.removeCursor, this))
    @cursors = {}

  moveCursor: (userId, range) ->
    cursor = @cursors[userId]
    return unless cursor?
    cursor.range = new Range(range.start, range.end)
    dom(cursor.elem).removeClass('hidden')
    clearTimeout(cursor.timer)
    cursor.timer = setTimeout( =>
      dom(cursor.elem).addClass('hidden')
      cursor.timer = null
    , @options.timeout)
    this._updateCursor(cursor)
    return cursor

  removeCursor: (userId) ->
    cursor = @cursors[userId]
    this.emit(MultiCursor.events.CURSOR_REMOVED, cursor)
    cursor.elem.parentNode.removeChild(cursor.elem) if cursor?
    delete @cursors[userId]

  setCursor: (userId, range, name, color) ->
    unless @cursors[userId]?
      @cursors[userId] = cursor = {
        userId: userId
        range: new Range(range.start, range.end)
        color: color
        elem: this._buildCursor(name, color)
      }
      this.emit(MultiCursor.events.CURSOR_ADDED, cursor)
    _.defer( =>
      this.moveCursor(userId, range)
    )
    return @cursors[userId]

  shiftCursors: (index, length, authorId = null) ->
    _.each(@cursors, (cursor, id) =>
      return unless cursor
      cursor.range.shift(index, length)
      if cursor.userId == authorId
        this.moveCursor(authorId, cursor.range)
    )

  update: ->
    _.each(@cursors, (cursor, id) =>
      return unless cursor?
      this._updateCursor(cursor)
      return true
    )

  _applyDelta: (delta) ->
    index = 0
    _.each(delta.ops, (op) =>
      length = 0
      if op.insert?
        length = op.insert.length or 1
        this.shiftCursors(index, length, op.attributes?['author'])
      else if op.delete?
        this.shiftCursors(index, -1*op.delete, null)
      else if op.retain?
        this.shiftCursors(index, 0, null)
        length = op.retain
      index += length
    )
    this.update()

  _buildCursor: (name, color) ->
    cursor = document.createElement('div')
    dom(cursor).addClass('cursor')
    cursor.innerHTML = @options.template
    flag = cursor.querySelector('.cursor-flag')
    dom(flag).text(name)
    caret = cursor.querySelector('.cursor-caret')
    caret.style.backgroundColor = flag.style.backgroundColor = color
    @container.appendChild(cursor)
    return cursor

  _buildHighlight: (bounds, color) =>
    containerBounds = @quill.container.getBoundingClientRect()
    span = document.createElement('span')
    span.classList.add('cursor-highlight')
    span.style.left = (bounds.left - containerBounds.left) + 'px'
    span.style.top = (bounds.top - containerBounds.top) + 'px'
    span.style.width = bounds.width + 'px'
    span.style.height = bounds.height + 'px'
    span.style.backgroundColor = color
    return span

  _updateCursor: (cursor) ->
    endBounds = @quill.getBounds(cursor.range.end)
    return this.removeCursor(cursor.userId) unless endBounds?

    elem = cursor.elem

    # position the caret at the end
    caret = elem.querySelector('.cursor-caret')
    caret.style.top = (endBounds.top + @quill.container.scrollTop) + 'px'
    caret.style.left = endBounds.left + 'px'
    caret.style.height = endBounds.height + 'px'

    # position the flag at the end
    flag = elem.querySelector('.cursor-flag')
    flag.style.top = (endBounds.top + @quill.container.scrollTop - flag.offsetHeight) + 'px'
    flag.style.left = endBounds.left + 'px'

    # flip flag to left side of caret if not enough space
    if endBounds.left > flag.offsetWidth - caret.offsetWidth and flag.offsetWidth > @quill.root.offsetWidth - endBounds.left
      flag.classList.add('left')
      flag.style.left = (endBounds.left - flag.offsetWidth + caret.offsetWidth) + 'px'

    # build the highlight boxes for each selected line
    highlights = elem.querySelector('.cursor-highlights')
    highlights.innerHTML = ''
    if cursor.range.start != cursor.range.end
      eachClientRect(@quill, cursor.range, (bounds) =>
        highlights.appendChild this._buildHighlight(bounds, cursor.color)
      )

    # emit move event
    this.emit(MultiCursor.events.CURSOR_MOVED, cursor)

# For each line in the range, create a native range on which to call getClientRects()
# Creating a single range doesn't seem to highlight embeds correctly
eachClientRect = (quill, range, callback) ->
  sel = quill.editor.selection
  index = range.start
  quill.getText(range).split('\n').forEach((line) ->
    [startNode, startOffset] = sel._indexToPosition(index)
    [endNode, endOffset] = sel._indexToPosition(index + line.length)
    nativeRange = document.createRange()
    nativeRange.setStart(startNode, startOffset)
    nativeRange.setEnd(endNode, endOffset)
    _.each(nativeRange.getClientRects(), callback)
    index += line.length + 1
  )

Quill.registerModule('multi-cursor', MultiCursor)
module.exports = MultiCursor
