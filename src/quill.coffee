_             = require('lodash')
Delta         = require('rich-text').Delta
EventEmitter2 = require('eventemitter2')
dom           = require('./lib/dom')
Document      = require('./core/document')
Editor        = require('./core/editor')
Format        = require('./core/format')
Normalizer    = require('./core/normalizer')
Range         = require('./lib/range')


class Quill extends EventEmitter2
  @version: '0.20.1'
  @editors: []
  @modules: []

  @DEFAULTS:
    formats: Object.keys(Format.FORMATS)
    modules:
      'keyboard': true
      'paste-manager': true
      'undo-manager': true
    pollInterval: 100
    readOnly: false

  @events:
    FORMAT_INIT      : 'format-init'
    MODULE_INIT      : 'module-init'
    POST_EVENT       : 'post-event'
    PRE_EVENT        : 'pre-event'
    SELECTION_CHANGE : 'selection-change'
    TEXT_CHANGE      : 'text-change'

  @sources: Editor.sources

  @registerModule: (name, module) ->
    console.warn("Overwriting #{name} module") if Quill.modules[name]?
    Quill.modules[name] = module

  @require: (name) ->
    switch name
      when 'lodash'     then return _
      when 'delta'      then return Delta
      when 'format'     then return Format
      when 'normalizer' then return Normalizer
      when 'dom'        then return dom
      when 'document'   then return Document
      when 'range'      then return Range
      else return null


  constructor: (@container, options = {}) ->
    @container = document.querySelector(@container) if _.isString(@container)
    throw new Error('Invalid Quill container') unless @container?
    moduleOptions = _.defaults(options.modules or {}, Quill.DEFAULTS.modules)
    html = @container.innerHTML
    @container.innerHTML = ''
    dom(@container).addClass('ql-container')
    @options = _.defaults(options, Quill.DEFAULTS)
    @options.modules = moduleOptions
    @options.id = @id = "ql-editor-#{Quill.editors.length + 1}"
    @modules = {}
    @root = this.addContainer('ql-editor')
    @editor = new Editor(@root, this, @options)
    Quill.editors.push(this)
    this.setHTML(html, Quill.sources.SILENT)
    _.each(@options.modules, (option, name) =>
      this.addModule(name, option)
    )

  destroy: ->
    html = this.getHTML()
    _.each(@modules, (module, name) ->
      module.destroy() if _.isFunction(module.destroy)
    )
    @editor.destroy()
    this.removeAllListeners()
    Quill.editors.splice(_.indexOf(Quill.editors, this), 1)
    @container.innerHTML = html

  addContainer: (className, before = false) ->
    refNode = if before then @root else null
    container = document.createElement('div')
    dom(container).addClass(className)
    @container.insertBefore(container, refNode)
    return container

  addFormat: (name, config) ->
    @editor.doc.addFormat(name, config)
    this.emit(Quill.events.FORMAT_INIT, name)

  addModule: (name, options) ->
    moduleClass = Quill.modules[name]
    throw new Error("Cannot load #{name} module. Are you sure you registered it?") unless moduleClass?
    options = {} if options == true   # Allow for addModule('module', true)
    @modules[name] = new moduleClass(this, options)
    this.emit(Quill.events.MODULE_INIT, name, @modules[name])
    return @modules[name]

  addStyles: (css) ->
    style = document.createElement('style')
    style.type = 'text/css'
    style.appendChild(document.createTextNode(css))
    document.head.appendChild(style)

  deleteText: (index, length, source = Quill.sources.API) ->
    [index, length, formats, source] = this._buildParams(index, length, {}, source)
    return unless length > 0
    delta = new Delta().retain(index).delete(length)
    @editor.applyDelta(delta, source)

  emit: (eventName, args...) ->
    super(Quill.events.PRE_EVENT, eventName, args...)
    super(eventName, args...)
    super(Quill.events.POST_EVENT, eventName, args...)

  focus: ->
    @editor.focus()

  formatLine: (index, length, name, value, source) ->
    [index, length, formats, source] = this._buildParams(index, length, name, value, source)
    # use the inclusive option only when a range is selected
    [line, offset] = @editor.doc.findLineAt(index + length, length > 0)
    length += (line.length - offset) if line?
    this.formatText(index, length, formats, source)

  formatText: (index, length, name, value, source) ->
    [index, length, formats, source] = this._buildParams(index, length, name, value, source)
    formats = _.reduce(formats, (formats, value, name) =>
      format = @editor.doc.formats[name]
      # TODO warn if no format
      formats[name] = null unless value and value != format.config.default     # false will be composed and kept in attributes
      return formats
    , formats)
    delta = new Delta().retain(index).retain(length, formats)
    @editor.applyDelta(delta, source)

  getBounds: (index) ->
    return @editor.getBounds(index)

  getContents: (index = 0, length = this.getLength() - index) ->
    if _.isObject(index)
      length = index.length
      index = index.index
    return @editor.delta.slice(index, index + length)

  getHTML: ->
    @editor.doc.getHTML()

  getLength: ->
    return @editor.length

  getModule: (name) ->
    return @modules[name]

  getSelection: (opts = {}) ->
    @editor.checkUpdate()   # Make sure we access getRange with editor in consistent state
    return @editor.selection.getRange(opts)

  getText: (index = 0, length = undefined) ->
    return _.map(this.getContents(index, length).ops, (op) ->
      return if _.isString(op.insert) then op.insert else dom.EMBED_TEXT
    ).join('')

  insertEmbed: (index, type, url, formats, source) ->
    if _.isObject(type)
      embed = type
      formats = url
      source = formats
    else
      embed = {}
      embed[type] = url
    [index, length, formats, source] = this._buildParams(index, 0, formats, source)
    delta = new Delta().retain(index).insert(embed, formats)
    @editor.applyDelta(delta, source)

  insertText: (index, text, name, value, source) ->
    [index, length, formats, source] = this._buildParams(index, 0, name, value, source)
    return unless text.length > 0
    delta = new Delta().retain(index).insert(text, formats)
    @editor.applyDelta(delta, source)

  onModuleLoad: (name, callback) ->
    if (@modules[name]) then return callback(@modules[name])
    this.on(Quill.events.MODULE_INIT, (moduleName, module) ->
      callback(module) if moduleName == name
    )

  prepareFormat: (name, value, source = Quill.sources.API) ->
    format = @editor.doc.formats[name]
    return unless format?     # TODO warn
    range = this.getSelection()
    return unless range?.isCollapsed()
    if format.isType(Format.types.LINE)
      this.formatLine(range, name, value, source)
    else
      format.prepare(value)

  setContents: (delta, source = Quill.sources.API) ->
    if Array.isArray(delta)
      delta = new Delta(delta.slice())
    else
      delta = new Delta(delta.ops.slice())
    # Retain trailing newline unless inserting one
    lastOp = _.last(delta.slice(delta.length() - 1).ops)
    delta.delete(this.getLength() - 1)
    if lastOp? and _.isString(lastOp.insert) and _.last(lastOp.insert) == '\n'
      delta.delete(1)
    this.updateContents(delta, source)

  setHTML: (html, source = Quill.sources.API) ->
    html = "<#{dom.DEFAULT_BLOCK_TAG}><#{dom.DEFAULT_BREAK_TAG}></#{dom.DEFAULT_BLOCK_TAG}>" unless html.trim()
    @editor.doc.setHTML(html)
    @editor.checkUpdate(source)

  setSelection: (index, length = 0, source = Quill.sources.API) ->
    if _.isNumber(index) and _.isNumber(length)
      range = new Range(index, index + length)
    else
      range = index
      source = length or source
    @editor.selection.setRange(range, source)

  setText: (text, source = Quill.sources.API) ->
    delta = new Delta().insert(text)
    this.setContents(delta, source)

  updateContents: (delta, source = Quill.sources.API) ->
    delta = { ops: delta } if Array.isArray(delta)
    @editor.applyDelta(delta, source)

  # fn(Number index, Number length, String name, String value, String source)
  # fn(Number index, Number length, Object formats, String source)
  # fn(Object range, String name, String value, String source)
  # fn(Object range, Object formats, String source)
  _buildParams: (params...) ->
    if _.isObject(params[0])
      params.splice(0, 1, params[0].index, params[0].length)
    if _.isString(params[2])
      formats = {}
      formats[params[2]] = params[3]
      params.splice(2, 2, formats)
    params[3] ?= Quill.sources.API
    return params

module.exports = Quill
