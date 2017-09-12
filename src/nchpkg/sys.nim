# nch #

import
  macros,
  tables,
  typetraits,
  sequtils,
  strutils,
  future,
  sdl2,
  sdl2/gfx,
  basic2d,
  random,
  math

import
  util

export
  util

{.experimental.}

type
  CompDef = tuple
    name: string
    onReg: proc (elem: Elem)
  
  CompReg* = ref object
    owner: Elem
    perPage*: int
    size: int
    vacancies: seq[int]
    pages*: seq[pointer]
    compDef: CompDef
    last: int
  
  CompRef* = tuple
    name: string
    index: int
    empty: bool
    compReg: CompReg
  
  Comp* = object of RootObj
    active: bool
    owner*: Elem
    destroying: bool

  Elem* = ref object
    destroying*: bool
    name*: string
    parent*: Elem
    children*: OrderedTableRef[string, Elem]
    comps: OrderedTableRef[string, CompRef]
    compRegs: OrderedTableRef[string, CompReg]
    destroyingElems: seq[Elem]
    pos*: Vector2d
    scale*: Vector2d
    rot*: float
    prev: Elem
    next: Elem
    last: Elem

  Event*[T: proc] = ref object
    before*: seq[(T, CompRef)]
    on*: seq[(T, CompRef)]
    after*: seq[(T, CompRef)]
  
  NchError = object of Exception

  Nch = ref object
    root: Elem
    compDefs: OrderedTableRef[string, CompDef]
    debug: bool

let nilCompRef*: CompRef = ("NIL COMP REF", -1, true, nil)

var nch* = Nch(root: nil, compDefs: newOrderedTable[string, CompDef](), debug: true)

template nchError*(message: string): untyped =
  newException(NchError, message)

proc `$`*(elem: Elem, indent: int = 0): string =
  result = "Elem \"" & elem.name & "\":\n  children:\n"
  for child in elem.children.values:
    result &= "    " & child.name & "\n" #TODO: siblings
  result &= "  comps:\n"
  for comp in elem.comps.values:
    result &= "    " & comp.name & "\n"
  if elem.compRegs != nil:
    result &= "  compRegs:\n"
    for compReg in elem.compRegs.keys:
      result &= "    " & compReg & "\n"

proc getInstance[T: Comp](compReg: CompReg, index: int): ptr T =
  cast[ptr T](cast[uint](compReg.pages[index div compReg.perPage]) + (index mod compReg.perPage).uint * compReg.size.uint)

proc getGenericInstance(compReg: CompReg, index: int): ptr Comp =
  cast[ptr Comp](cast[uint](compReg.pages[index div compReg.perPage]) + (index mod compReg.perPage).uint * compReg.size.uint)

proc define*(t: typedesc, onReg: proc (elem: Elem) = nil) =
  if t.name in nch.compDefs:
    raise nchError(t.name & " is already defined")
  if nch.debug:
    echo("DEFINE\t" & t.name)
  nch.compDefs[t.name] = (
    name: t.name,
    onReg: onReg
  )

proc addPage*(compReg: CompReg) =
  if nch.debug:
    echo("ADDPAGE\t" & compReg.owner.name & "->" & compReg.compDef.name & "#" & $compReg.pages.len)
  var mem = allocShared0(compReg.size * compReg.perPage)
  compReg.pages.add(mem)
  #[for i in 0..compReg.perPage:
    cast[ptr Comp](cast[uint](mem) + (compReg.size * i).uint)[] = Comp()]#

proc newCompReg(owner: Elem, perPage: int, size: int, compDef: CompDef): CompReg =
  new(result)
  result.pages = @[]
  result.vacancies = @[]
  result.owner = owner
  result.perPage = perPage
  result.size = size
  result.compDef = compDef
  result.last = -1
  result.addPage()

proc reg*[T: Comp](elem: Elem, perPage: int) =
  if elem.compRegs == nil:
    elem.compRegs = newOrderedTable[string, CompReg]()
  let name = typedesc[T].name
  if name notin nch.compDefs:
    raise nchError(name & " not defined")
  if name in elem.compRegs:
    raise nchError(name & " already registered in " & elem.name)
  let compDef = nch.compDefs[name]
  if nch.debug:
    echo("REGISTR\t" & elem.name & "->" & name & " (" & $sizeof(T) & "*" & $perPage & "=" & $(sizeof(T) * perPage) & ")")
  elem.compRegs[name] = newCompReg(elem, perPage, sizeof(T), compDef)
  if compDef.onReg != nil:
    compDef.onReg(elem)

proc elem*(name: string): Elem {.inline.} =
  new(result)
  result.name = name
  result.children = newOrderedTable[string, Elem]()
  result.comps = newOrderedTable[string, CompRef]()
  result.pos = vector2d(0, 0)
  result.scale = vector2d(1, 1)
  result.rot = 0
  if nch.root == nil:
    result.destroyingElems = @[]
    nch.root = result

method setup(comp: var Comp) {.base.} =
  discard

proc getRoot*(elem: Elem): Elem =
  result = elem
  while result.parent != nil:
    result = result.parent

# add child Elem to parent Elem
proc add*(parent, child: Elem): Elem {.discardable.} =
  # if parent already has child with same name, add child as a sibling of the existing child
  if child.name in parent.children:
    if parent.children[child.name].last == nil:
      child.prev = parent.children[child.name]
      parent.children[child.name].next = child
    else:
      child.prev = parent.children[child.name].last
      parent.children[child.name].last.next = child
    parent.children[child.name].last = child
  else:
    parent.children[child.name] = child
  child.parent = parent
  child

# add child Elem to parent Elem
proc add*(parent: Elem, childName: string): Elem {.discardable.} =
  parent.add(elem(childName))

# mark Elem for destruction
proc destroy*(elem: Elem) =
  if elem.destroying == true:
    return
  elem.destroying = true
  if nch.debug:
    echo("DESTROY\t" & elem.name)

  # destroy all children
  for child in elem.children.values:
    child.destroy()
  
  # destroy all Comps
  for compRef in elem.comps.values:
    var comp = getGenericInstance(compRef.compReg, compRef.index)
    comp.destroying = true

  # tell root to bury me on next cleanup
  elem.getRoot.destroyingElems.add(elem)

  # handle siblings
  if elem.prev != nil:
    if elem.next == nil: # this is the last sibling
      elem.prev.next = nil
      elem.parent.children[elem.name].last = elem.prev
    else:
      elem.prev.next = elem.next
      elem.next.prev = elem.prev
  else:
    if elem.next != nil: # this is the first sibling
      elem.next.last = elem.last
      elem.parent.children[elem.name] = elem.next
      elem.next.prev = nil

proc bury*(elem: Elem) =
  for compRef in elem.comps.values:
    var comp = getGenericInstance(compRef.compReg, compRef.index)
    comp.active = false
    comp.owner = nil
    compRef.compReg.vacancies.add(compRef.index)
  if elem.compRegs != nil:
    for compReg in elem.compRegs.values:
      discard #TODO
  elem.comps.clear()
  
proc cleanup*(elem: Elem) =
  for elem in elem.destroyingElems:
    elem.bury
  elem.destroyingElems = @[]

proc getUpCompReg*[T: Comp](elem: Elem): ptr CompReg =
  let name = typedesc[T].name
  var parent = elem.parent
  if elem == nch.root:
    parent = elem
  while parent != nil:
    if parent.compRegs != nil and name in parent.compRegs:
      return cast[ptr CompReg](addr(parent.compRegs[name]))
    parent = parent.parent
  raise nchError(name & " isn't registered up the hierarchy of " & elem.name)

proc attach*[T: Comp](elem: Elem, comp: T): ptr T {.discardable.} =
  let name = typedesc[T].name
  if name notin nch.compDefs:
    raise nchError(name & " not defined")
  if name in elem.comps:
    raise nchError(name & " already attached to " & elem.name)
  var compReg = getUpCompReg[T](elem)
  
  inc compReg.last
  var index = compReg.last

  if compReg.vacancies.len > 0:
    index = compReg.vacancies.pop
  
  while index div compReg.perPage > compReg.pages.high:
    compReg.addPage()
  
  if nch.debug:
    echo("ATTACH\t" & elem.name & "->(" & compReg.owner.name & "->" & name & "#" & $(index div compReg.perPage) & "," & $(index mod compReg.perPage) & ")")
  let inst = getInstance[T](compReg, index)
  inst[] = comp
  inst.owner = elem
  inst.active = true
  inst.destroying = false
  elem.comps[name] = (name: name, index: index, empty: false, compReg: compReg[])
  inst.setup()
  inst


proc getTransform*(elem: Elem): Matrix2d =
  result = stretch(elem.scale.x, elem.scale.y) & rotate(elem.rot) & move(elem.pos)
  var parent = elem.parent
  while parent != nil:
    result = parent.getTransform() & result
    parent = parent.parent

proc globalPos*(elem: Elem): Vector2d =
  point2d(0, 0) & elem.getTransform

# subscribe a proc to an Event
proc before*[T](event: Event[T], procedure: T) =
  event.before.add((procedure, nilCompRef))

# subscribe a proc to an Event
proc on*[T](event: Event[T], procedure: T) =
  event.on.add((procedure, nilCompRef))

# subscribe a proc to an Event
proc after*[T](event: Event[T], procedure: T) =
  event.after.add((procedure, nilCompRef))

# create a new Event
proc newEvent*[T](): Event[T] =
  Event[T](
    before: @[],
    on: @[],
    after: @[]
  )

proc getComp*[T: Comp](owner: Elem): ptr T =
  let name = typedesc[T].name
  let upCompReg = getUpCompReg[T](owner)
  if upCompReg == nil:
    raise nchError(name & " isn't registered up the hierarchy of " & owner.name)
  if name notin owner.comps:
    raise nchError(name & " isn't attached to " & owner.name)
  return getInstance[T](upCompReg[], owner.comps[name].index)

proc getUpComp*[T: Comp](elem: Elem): ptr T =
  #TODO: cache!
  let name = typedesc[T].name
  var parent = elem
  while parent != nil and result == nil:
    if name in parent.comps:
      return cast[ptr T](getComp[T](parent))
    else:
      parent = parent.parent
  if result == nil:
    raise nchError(name & " not found up the hierarchy of " & elem.name)

# iterate through all procs in a subscription
iterator items*[T: proc](event: Event[T]): (T, CompRef) =
  for i in event.before:
    yield i
  for i in event.on:
    yield i
  for i in event.after:
    yield i

iterator mitems*[T: Comp](elem: Elem): ptr T =
  let name = typedesc[T].name
  if name notin elem.compRegs:
    raise nchError(name & " isn't registered in " & elem.name)
  var compReg = elem.compRegs[name]
  if compReg.last > -1:
    for i in 0..compReg.last:
      let instance = getInstance[T](compReg, i)
      if instance.active and not instance.destroying:
        yield instance

iterator siblings*(elem: var Elem): Elem =
  var e = elem
  yield e
  while e.next != nil:
    yield e.next
    e = e.next
