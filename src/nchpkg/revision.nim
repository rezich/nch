import
  tables,
  typetraits,
  sequtils,
  future,
  sdl2,
  sdl2/gfx,
  basic2d,
  random,
  math

{.experimental.}

converter toPoint2d*(x: Vector2d): Point2d = point2d(x.x, x.y)
converter toPoint*(x: Vector2d): Point = point(x.x.cint, x.y.cint)
converter toPoint*(x: Point2d): Point = point(x.x.cint, x.y.cint)
converter toVector2d*(x: Point2d): Vector2d = vector2d(x.x, x.y)
converter toVector2d*(x: Point): Vector2d = vector2d(x.x.float, x.y.float)

type
  Node* = object of RootObj
    name*: string
    destroying: bool
  CompRegBase = object of RootObj
    perPage*: int
    vacancies: seq[int]
    last*: int
    pages*: seq[pointer]
    size*: uint
  CompReg[T] = object of CompRegBase
    onReg*: proc (elem: ptr Elem)
    onNew*: proc (owner: ptr Elem): T
  Comp* = object of Node
    active*: bool
    owner*: ptr Elem
    things*: int
  CompRef* = object of RootObj
    name: string
    index: int
    empty: bool
    compPtr: ptr Comp
    compReg: ptr CompRegBase
  Event[T: proc] = ref object of RootObj
    before*: seq[(T, CompRef)]
    on*: seq[(T, CompRef)]
    after*: seq[(T, CompRef)]
  Elem* = object of Node
    children: OrderedTableRef[string, ptr Elem]
    comps: OrderedTableRef[string, CompRef]
    pos*: Vector2d
    scale*: Vector2d
    rot*: float
    parent*: ptr Elem
    prev: ptr Elem
    next: ptr Elem
    last: ptr Elem
    compRegs*: OrderedTableRef[string, CompRegBase]
    destroyingElems: seq[ptr Elem]
  Nch* = object of RootObj
    root*: ptr Elem

var nch* = Nch(root: nil)

proc getRoot(elem: ptr Elem): ptr Elem =
  result = elem
  while result.parent != nil:
    result = elem.parent

proc ease*(x: var float, target: float, speed: float = 0.1, snap: float = 0.01) =
  x = x + (target - x) * speed
  if (abs(x - target)) <= snap:
    x = target

proc pluralize*(n: int, singular, plural: string): string =
  if n == 1:
    singular
  else:
    plural

proc nilCompRef*(): CompRef =
  CompRef(
    empty: true
  )

proc getTransform*(elem: ptr Elem): Matrix2d =
  result = stretch(elem.scale.x, elem.scale.y) & rotate(elem.rot) & move(elem.pos)
  var parent = elem.parent
  while parent != nil:
    result = parent.getTransform() & result
    parent = parent.parent

proc globalPos*(elem: ptr Elem): Vector2d =
  point2d(0, 0) & elem.getTransform

# subscribe a proc to an Event
proc before*[T](event: Event[T], procedure: T) =
  event.before.add((procedure, nilCompRef()))

# subscribe a proc to an Event
proc on*[T](event: Event[T], procedure: T) =
  event.on.add((procedure, nilCompRef()))

# subscribe a proc to an Event
proc after*[T](event: Event[T], procedure: T) =
  event.after.add((procedure, nilCompRef()))

# create a new Event
proc newEvent*[T](): Event[T] =
  Event[T](
    before: @[],
    on: @[],
    after: @[]
  )

# iterate through all procs in a subscription
iterator items*[T: proc](event: Event[T]): (T, CompRef) =
  for i in event.before:
    yield i
  for i in event.on:
    yield i
  for i in event.after:
    yield i

# get a named child Elem of a given Elem
proc getChild*(elem: ptr Elem, search: string): ptr Elem =
  #TODO: upgrade to parse `search`, allowing for hierarchical Elem tree traversal
  let name = search
  if name notin elem.children:
    echo "EXCEPTION: relative Elem not found"
    return nil
  cast[ptr Elem](elem.children[name])

proc getUpCompReg*[T: Comp](elem: ptr Elem): ptr CompReg[T] =
  let name = typedesc[T].name
  var parent = elem.parent
  while parent != nil:
    if name in parent.compRegs:
      return cast[ptr CompReg[T]](addr(parent.compRegs[name]))
    parent = parent.parent
  echo "EXCEPTION: " & name & " isn't registered up the hierarchy of " & elem.name
  return nil

proc getUpElem*(elem: ptr Elem): Elem =
  discard

proc getInstance[T: Comp](compReg: CompReg[T], index: int): ptr T =
  cast[ptr T](cast[uint](compReg.pages[index div compReg.perPage]) + compReg.size * (index mod compReg.perPage).uint)

proc getCompReg[T: Comp](elem: ptr Elem): ptr CompReg[T] =
  let name = typedesc[T].name
  if name notin elem.compRegs:
    echo "EXCEPTION: " & name & " isn't registered in " & elem.name
    nil
  else:
    cast[ptr CompReg[T]](addr(elem.compRegs[name]))

proc addPage[T: Comp](compReg: ptr CompReg[T]) =
  compReg.pages.add(alloc(sizeof(pointer) + sizeof(T) * compReg.perPage))
  var page = compReg.pages[compReg.pages.high]
  for i in 0..compReg.perPage:
    cast[ptr T](cast[uint](page) + compReg.size.uint * i.uint)[] = T(active: false)

proc register*[T: Comp](elem: ptr Elem, compReg: CompReg[T]) =
  let name = typedesc[T].name
  if elem.compRegs == nil:
    elem.compRegs = newOrderedTable[string, CompRegBase]()
  if name in elem.compRegs:
    echo "EXCEPTION: " & name & " is already registered in " & elem.name
    return
  elem.compRegs[name] = compReg
  elem.compRegs[name].vacancies = @[]
  elem.compRegs[name].last = -1
  elem.compRegs[name].pages = @[]
  var newCompReg = cast[ptr CompReg[T]](addr(elem.compRegs[name]))
  if compReg.onNew != nil:
    newCompReg.onNew = compReg.onNew
  if compReg.onReg != nil:
    newCompReg.onReg = compReg.onReg

  addPage[T](cast[ptr CompReg[T]](addr(elem.compRegs[name])))

  if newCompReg.onReg != nil:
    newCompReg.onReg(elem)


proc allocComp[T: Comp](compReg: ptr CompReg[T], owner: ptr Elem): (ptr T, int) =
  let name = typedesc[T].name
  var index: int
  if compReg.vacancies.len > 0:
    index = compReg.vacancies.pop
  else:
    inc compReg.last
    index = compReg.last
  let subIndex = index mod compReg.perPage
  let page = index div compReg.perPage
  echo "allocating " & name & "#" & $index
  echo "  (page " & $page & ", index " & $subIndex & ")"
  while page > compReg.pages.high:
    echo "    (adding new page)"
    addPage[T](compReg)
  let instance = getInstance[T](compReg, index)
  if compReg.onNew != nil:
    instance[] = compReg.onNew(owner)
  instance.name = name
  instance.owner = owner
  instance.active = true
  instance.destroying = false
  (instance, index)

proc attach*[T: Comp](owner: ptr Elem): ptr T {.discardable.} =
  let name = typedesc[T].name
  var index: int
  let upCompReg = getUpCompReg[T](owner)
  if upCompReg == nil:
    echo "EXCEPTION: " & name & " isn't registered up the hierarchy of " & owner.name
  (result, index) = allocComp[T](upCompReg, owner)
  owner.comps[name] = CompRef(
    name: name,
    index: index,
    compPtr: result,
    compReg: upCompReg
  )

proc initElem(elem: ptr Elem, parent: ptr Elem = nil) =
  elem.destroying = false
  elem.children = newOrderedTable[string, ptr Elem]()
  elem.comps = newOrderedTable[string, CompRef]()
  elem.pos = vector2d(0.0, 0.0)
  elem.scale = vector2d(1.0, 1.0)
  elem.rot = 0.0
  elem.parent = parent
  elem.prev = nil
  elem.next = nil
  elem.last = nil
  elem.compRegs = nil
  elem.destroyingElems = nil

proc makeRoot*(name: string): ptr Elem =
  result = cast[ptr Elem](alloc(sizeof(Elem)))
  result.name = name
  initElem(result)
  result.destroyingElems = @[]

proc add*(parent: var ptr Elem, name: string): ptr Elem {.discardable.} =
  result = cast[ptr Elem](alloc(sizeof(Elem)))
  result.name = name
  initElem(result, parent)
  if name in parent.children:
    if parent.children[name].last == nil:
      result.prev = parent.children[name]
      parent.children[name].next = result
    else:
      result.prev = parent.children[name].last
      parent.children[name].last.next = result
    parent.children[name].last = result
  else:
    parent.children[name] = result

proc getComp*[T: Comp](owner: ptr Elem): ptr T =
  let name = typedesc[T].name
  let upCompReg = getUpCompReg[T](owner)
  if upCompReg == nil:
    echo "EXCEPTION: " & name & " isn't registered up the hierarchy of " & owner.name
    return nil
  if name notin owner.comps:
    echo "EXCEPTION: " & name & " isn't attached to " & owner.name
    return nil
  return getInstance[T](upCompReg, owner.comps[name].index)

proc getUpComp*[T: Comp](elem: ptr Elem): ptr T =
  #TODO: cache!
  result = nil
  let name = typedesc[T].name
  var parent = elem.parent
  while parent != nil and result == nil:
    if name in parent.comps:
      result = cast[ptr T](getComp[T](parent))
    else:
      parent = parent.parent
  if result == nil:
    echo "EXCEPTION: " & name & "not found up the hierarchy of " & elem.name

proc destroy*(elem: ptr Elem) =
  #TODO: make sure all of this works!!
  elem.destroying = true
  for child in elem.children.mvalues:
    child.destroy()
  elem.getRoot.destroyingElems.add(elem)
  for compRef in elem.comps.values:
    var comp = cast[ptr Comp](cast[uint](compRef.compReg.pages[compRef.index div compRef.compReg.perPage]) + compRef.compReg.size * (compRef.index mod compRef.compReg.perPage).uint)
    comp.destroying = true
  if elem.prev != nil:
    if elem.next == nil: # this is the last elem in the sequence
      elem.prev.next = nil
      elem.parent.children[elem.name].last = elem.prev
    else:
      elem.prev.next = elem.next
      elem.next.prev = elem.prev
  else:
    if elem.next != nil: # this is the first elem in the seq
      elem.next.last = elem.last
      elem.parent.children[elem.name] = elem.next
      elem.next.prev = nil

proc bury*(elem: ptr Elem) =
  for compRef in elem.comps.values:
    var comp = cast[ptr Comp](cast[uint](compRef.compReg.pages[compRef.index div compRef.compReg.perPage]) + compRef.compReg.size * (compRef.index mod compRef.compReg.perPage).uint)
    comp.active = false
    comp.owner = nil
    compRef.compReg.vacancies.add(compRef.index)
  elem.comps.clear()
  dealloc(elem)

proc cleanup*(elem: ptr Elem) =
  for elem in elem.destroyingElems:
    bury(elem)
  elem.destroyingElems = @[]

iterator mitems*[T: Comp](elem: ptr Elem): ptr T =
  let name = typedesc[T].name
  if name notin elem.compRegs:
    echo "EXCEPTION: " & name & " isn't registered in " & elem.name
  var compReg = cast[ptr CompReg[T]](addr elem.compRegs[name])
  if compReg.last > -1:
    for i in 0..compReg.last:
      let instance = getInstance[T](compReg, i)
      if instance.active and not instance.destroying:
        yield instance

iterator siblings*(elem: var ptr Elem): ptr Elem =
  var e = elem
  yield e
  while e.next != nil:
    yield e.next
    e = e.next

type MyComp* = object of Comp
  moreThings: int

var app = makeRoot("nch test app")
var world = app.add("world")
register[MyComp](app, CompReg[MyComp](
  perPage: 2,
  onReg: proc (elem: ptr Elem) =
    echo "onReg!"
  ,
  onNew: proc (owner: ptr Elem): MyComp =
    echo "onNew!"
    MyComp(moreThings: 87)
))

attach[MyComp](world)

for i in mitems[MyComp](app):
  echo i.owner.name

echo getComp[MyComp](world).moreThings

world.destroy()

app.cleanup()
