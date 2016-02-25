Quill  = require('../quill')
_      = Quill.require('lodash')
Delta  = Quill.require('delta')


class UndoManager
  @DEFAULTS:
    delay: 1000
    maxStack: 100
    userOnly: false

  @hotkeys:
    UNDO: { key: 'Z', metaKey: true }
    REDO: { key: 'Z', metaKey: true, shiftKey: true }

  constructor: (@quill, @options = {}) ->
    @lastRecorded = 0
    @ignoreChange = false
    this.clear()
    this.initListeners()

  initListeners: ->
    @quill.onModuleLoad('keyboard', (keyboard) =>
      keyboard.addHotkey(UndoManager.hotkeys.UNDO, =>
        @quill.editor.checkUpdate()
        this.undo()
        return false
      )
      redoKey = [UndoManager.hotkeys.REDO]
      if (navigator.platform.indexOf('Win') > -1)
        redoKey.push({ key: 'Y', metaKey: true })
      keyboard.addHotkey(redoKey, =>
        @quill.editor.checkUpdate()
        this.redo()
        return false
      )
    )
    @quill.on(@quill.constructor.events.TEXT_CHANGE, (delta, source) =>
      return if @ignoreChange
      if !@options.userOnly or source == Quill.sources.USER
        this.record(delta, @oldDelta)
      else
        this._transform(delta)
      @oldDelta = @quill.getContents()
    )

  clear: ->
    @stack =
      undo: []
      redo: []
    @oldDelta = @quill.getContents()

  record: (changeDelta, oldDelta) ->
    return unless changeDelta.ops.length > 0
    @stack.redo = []
    try
      undoDelta = @quill.getContents().diff(@oldDelta)
      timestamp = new Date().getTime()
      if @lastRecorded + @options.delay > timestamp and @stack.undo.length > 0
        change = @stack.undo.pop()
        undoDelta = new Delta().compose(undoDelta).compose(change.undo)
        changeDelta = new Delta().compose(change.redo).compose(changeDelta)
      else
        @lastRecorded = timestamp
      @stack.undo.push({
        redo: changeDelta
        undo: undoDelta
      })
      @stack.undo.unshift() if @stack.undo.length > @options.maxStack
    catch ignored
      console.warn('Could not record change... clearing undo stack.')
      this.clear()

  redo: ->
    this._change('redo', 'undo')

  undo: ->
    this._change('undo', 'redo')

  _change: (source, dest) ->
    if @stack[source].length > 0
      change = @stack[source].pop()
      @lastRecorded = 0
      @ignoreChange = true
      @quill.updateContents(change[source], Quill.sources.USER)
      @ignoreChange = false
      @oldDelta = @quill.getContents()
      @stack[dest].push(change)

  _transform: (delta) ->
    @oldDelta = delta.transform(@oldDelta, true)
    for change in @stack.undo
      change.undo = delta.transform(change.undo, true)
      change.redo = delta.transform(change.redo, true)
    for change in @stack.redo
      change.undo = delta.transform(change.undo, true)
      change.redo = delta.transform(change.redo, true)


Quill.registerModule('undo-manager', UndoManager)
module.exports = UndoManager
