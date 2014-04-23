_          = require('lodash')
DOM        = require('./dom')
Format     = require('./format')
Leaf       = require('./leaf')
Line       = require('./line')
LinkedList = require('./lib/linked-list')
Normalizer = require('./normalizer')
Utils      = require('./utils')
Tandem     = require('tandem-core')

# Note: Because Line uses @outerHTML as a heuristic to rebuild, we must be very careful to actually modify HTML when we modify it. Ex. Do not remove a <br> only to add another one back
# Maybe a better heuristic would also check leaf children are still in the dom


class Line extends LinkedList.Node
  @CLASS_NAME : 'line'
  @ID_PREFIX  : 'line-'

  constructor: (@doc, @node) ->
    @id = _.uniqueId(Line.ID_PREFIX)
    @node.id = @id
    DOM.addClass(@node, Line.CLASS_NAME)
    this.rebuild()
    super(@node)

  buildLeaves: (node, formats) ->
    _.each(DOM.getChildNodes(node), (node) =>
      node = Normalizer.normalizeNode(node)
      nodeFormats = _.clone(formats)
      # TODO: optimize
      _.each(@doc.formats, (format, name) ->
        # format.value() also checks match() but existing bug in tandem-core requires check anyways
        nodeFormats[name] = format.value(node) if format.match(node)
      )
      if Leaf.isLeafNode(node)
        @leaves.append(new Leaf(node, nodeFormats))
      else
        this.buildLeaves(node, nodeFormats)
    )

  deleteText: (offset, length) ->
    deleteLength = length
    [leaf, offset] = this.findLeafAt(offset)
    while leaf and deleteLength > 0
      nextLeaf = leaf.next
      if offset == 0 and leaf.length <= deleteLength
        DOM.removeNode(leaf.node)
        @leaves.remove(leaf)
      else
        leaf.deleteText(offset, deleteLength)
      deleteLength -= Math.min(leaf.length, deleteLength)
      leaf = nextLeaf
      offset = 0
    if length == @length - 1
      @node.appendChild(@node.ownerDocument.createElement(DOM.DEFAULT_BREAK_TAG))
      this.rebuild()
    else
      this.resetContent()

  findLeaf: (leafNode) ->
    curLeaf = @leaves.first
    while curLeaf?
      return curLeaf if curLeaf.node == leafNode
      curLeaf = curLeaf.next
    return null

  findLeafAt: (offset) ->
    # TODO exact same code as findLineAt
    return [@leaves.last, @leaves.last.length] if offset == @length - 1
    return [null, offset - @length] if offset >= @length
    leaf = @leaves.first
    while leaf?
      return [leaf, offset] if offset < leaf.length
      offset -= leaf.length
      leaf = leaf.next
    return [null, offset]   # Should never occur unless length calculation is off

  format: (name, value) ->
    format = @doc.formats[name]
    # TODO reassigning @node might be dangerous...
    if format.isType(Format.types.LINE)
      @node = format.add(@node, value)
    if value
      @formats[name] = value
    else
      delete @formats[name]

  formatText: (offset, length, name, value) ->
    [leaf, leafOffset] = this.findLeafAt(offset)
    format = @doc.formats[name]
    while leaf?
      nextLeaf = leaf.next
      # Make sure we need to change leaf format
      if (value and leaf.formats[name] != value) or (!value and leaf.formats[name]?)
        # Identify node to modify
        targetNode = leaf.node
        while !value and !format.match(targetNode)
          if targetNode.previousSibling?
            Utils.splitAncestors(targetNode, targetNode.parentNode.parentNode)
          targetNode = targetNode.parentNode
        # Isolate target node
        if leafOffset > 0
          [leftNode, targetNode] = Utils.splitNode(targetNode, leafOffset)
        if leaf.length > leafOffset + length  # leaf.length does not update even though we may have just split leaf.node
          [targetNode, rightNode] = Utils.splitNode(targetNode, length)
        format.add(targetNode, value)
      length -= leaf.length - leafOffset
      leafOffset = 0
      leaf = nextLeaf
    this.rebuild()

  insertText: (offset, text, formats = {}) ->
    [leaf, leafOffset] = this.findLeafAt(offset)
    # offset > 0 for multicursor
    if _.isEqual(leaf.formats, formats) and @length > 1 and offset > 0
      leaf.insertText(leafOffset, text)
      this.resetContent()
    else
      node = _.reduce(formats, (node, value, name) =>
        return @doc.formats[name].add(node, value)
      , @node.ownerDocument.createTextNode(text))
      node = DOM.wrap(@node.ownerDocument.createElement(DOM.DEFAULT_INLNE_TAG), node) if DOM.isTextNode(node)
      [prevNode, nextNode] = Utils.splitNode(leaf.node, leafOffset)
      refNode = Utils.splitAncestors(nextNode, @node)
      @node.insertBefore(node, refNode)
      this.rebuild()

  optimize: ->
    Normalizer.optimizeLine(@node)
    this.rebuild()

  rebuild: (force = false) ->
    return false if !force and @outerHTML? and @outerHTML == @node.outerHTML
    @node = Normalizer.normalizeNode(@node)
    @node.appendChild(@node.ownerDocument.createElement(DOM.DEFAULT_BREAK_TAG)) unless @node.firstChild?
    @leaves = new LinkedList()
    @formats = _.reduce(@doc.formats, (formats, format, name) =>
      formats[name] = format.value(@node) if format.isType(Format.types.LINE) and format.match(@node)
      return formats
    , {})
    this.buildLeaves(@node, {})
    # TODO does this belong here...
    if @leaves.length == 1 and @leaves.first.length == 0 and @leaves.first.node.tagName != DOM.DEFAULT_BREAK_TAG
      @leaves.first.node.appendChild(@node.ownerDocument.createElement(DOM.DEFAULT_BREAK_TAG))
      @leaves.first.node = @leaves.first.node.firstChild
    this.resetContent()
    return true

  resetContent: ->
    @outerHTML = @node.outerHTML
    @length = 1
    ops = _.map(@leaves.toArray(), (leaf) =>
      @length += leaf.length
      return new Tandem.InsertOp(leaf.text, leaf.formats)
    )
    ops.push(new Tandem.InsertOp('\n', @formats))
    @delta = new Tandem.Delta(0, @length, ops)


module.exports = Line
