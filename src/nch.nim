# nch #

import
  tables,
  typetraits,
  sequtils,
  future,
  sdl2,
  sdl2/gfx,
  sdl2/image,
  sdl2/ttf,
  basic2d,
  random,
  math

{.experimental.}

### SYSTEM ###
const
  compsPerPage = 2

proc box*[T](x: T): ref T =
  new(result); result[] = x

type
  # memory manager container
  Page*[T] = object of RootObj
    contents*: array[0..compsPerPage, T]
    next: ptr Page[T]

  #TODO
  Node* = object of RootObj
    name*: string
    internalUniv*: Univ
    internalDestroying*: bool
  
  #TODO
  CompAllocBase* = ref object of RootObj
    vacancies: seq[int]

  # Comp allocator, stored in a Univ
  CompAlloc*[T] = ref object of CompAllocBase
    comps*: Page[T]
    newProc: proc (owner: Elem): T
    last: int
  
  # component, the smallest unit of functionality
  Comp* = object of Node
    active*: bool
    owner*: Elem

  # component reference, secretly just an index
  CompRef* = object of RootObj
    name: string
    index: int
    empty*: bool
  
  #TODO
  Event*[T: proc] = ref object of RootObj
    before*: seq[(T, CompRef)]
    on*: seq[(T, CompRef)]
    after*: seq[(T, CompRef)]

  # element, the smallest unit of organization
  Elem* = ref object of Node
    elems: OrderedTableRef[string, Elem]
    comps: OrderedTableRef[string, CompRef]
    pos: Vector2d
    scale: Vector2d
    rot: float

  # universe, top-level element
  Univ* = ref object of Elem
    compAllocs*: OrderedTableRef[string, CompAllocBase]

  # container for the entire engine
  Nch* = object of RootObj
    root*: ptr Univ

# singleton container for the entire engine
var nch* = Nch(root: nil)

proc nilCompRef*(): CompRef =
  CompRef(
    empty: true
  )

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
    before: newSeq[(T, CompRef)](),
    on: newSeq[(T, CompRef)](),
    after: newSeq[(T, CompRef)]()
  )

# gets whether or not this Node is destroying
proc destroying*[T: Node](node: T): bool =
  node.internalDestroying

# gets the Univ the given Elem is a part of
proc univ*[T: Elem](elem: T): Univ =
  if elem.internalUniv == nil:
    return cast[Univ](elem)
  elem.internalUniv

# gets the Univ the given Comp is a part of
proc univ*[T: Comp](comp: T): Univ =
  comp.internalUniv

# initialize an Elem
proc initElem[T: Elem](elem: var T, parent: Elem = nil) =
  if parent != nil:
    elem.internalUniv = parent.univ
  elem.internalDestroying = false
  elem.elems = newOrderedTable[string, Elem]()
  elem.elems[".."] = parent
  elem.comps = newOrderedTable[string, CompRef]()
  elem.pos = vector2d(0.0, 0.0)
  elem.scale = vector2d(1.0, 1.0)
  elem.rot = 0.0

# initialize a Univ
proc initUniv*(univ: var Univ, name: string) =
  univ = Univ(
    name: name,
    compAllocs: newOrderedTable[string, CompAllocBase]()
  )
  initElem(univ)
  univ.internalUniv = nil
  univ.internalDestroying = false
  if nch.root == nil:
    nch.root = addr univ

# add an Elem as a child of a given Elem
proc add*[T: Elem](parent: var T, name: string): Elem {.discardable.} =
  new(result)
  result.name = name
  initElem(result, cast[Elem](parent))
  parent.elems[name] = result

# initialize a Comp
proc initComp*[T: Comp](comp: var T, owner: Elem) =
  #echo owner.name
  comp.name = typedesc[T].name
  comp.active = true
  comp.owner = owner
  comp.internalUniv = owner.univ
  comp.internalDestroying = false

# create the first Page for the memory manager
proc newPage[T: Comp](): Page[T] =
  result = Page[T](
    next: nil
  )
  for i in result.contents.mitems:
    i.active = false

# create an additional Page for the memory manager
proc newPage[T: Comp](prev: ptr Page[T]): ptr Page[T] {.discardable.} =
  result = cast[ptr Page[T]](alloc(sizeof(Page[T])))
  result.next = nil
  prev.next = result
  for i in result.contents.mitems:
    i.active = false

# create a new CompAlloc for the memory manager
proc newCompAlloc[T: Comp](newProc: proc (owner: Elem): T) : CompAlloc[T] =
  result = CompAlloc[T](
    comps: newPage[T](),
    last: 0,
    newProc: newProc,
    vacancies: newSeq[int]()
  )

# register a Comp sub-type into a given Univ
proc register*[T](univ: Univ, newProc: proc (owner: Elem): T, regProc: proc (univ: Univ) = nil) =
  let name = typedesc[T].name
  if name in univ.compAllocs:
    echo "EXCEPTION: " & name & " already registered in this Univ"
    return
  univ.compAllocs[name] = newCompAlloc[T](newProc)
  if regProc != nil:
    regProc(univ)

# allocate a new Comp inside a given Univ
proc allocComp[T: Comp](univ: Univ, owner: Elem): (ptr T, int) =
  let name = typedesc[T].name
  if name notin univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return
  
  let compAlloc = cast[CompAlloc[T]](univ.compAllocs[name])
  var index: int
  if compAlloc.vacancies.len > 0: # use a vacant Comp if there is one
    index = compAlloc.vacancies.pop
  else:
    index = compAlloc.last
    inc compAlloc.last
  
  let realIndex = index
  var curPage = addr compAlloc.comps
  while index >= compsPerPage: # skip ahead to the necessary Page, given the index
    index = index - compsPerPage
    if curPage.next == nil:
      newPage[T](curPage)
    curPage = curPage.next
  curPage.contents[index] = compAlloc.newProc(owner)
  result = (cast[ptr T](addr(curPage.contents[index])), realIndex)
  
# create a new instance of a Comp sub-type and attach it to an Elem
proc attach*[T: Comp](owner: Elem): ptr T {.discardable.} =
  #TODO: figure out a way to check if owner already has the same Comp
  var index : int
  (result, index) = allocComp[T](owner.univ, owner)
  result.initComp(owner)
  owner.comps[result.name] = CompRef(
    name: result.name,
    index: index
  )

# create a new instance of a Comp sub-type and attach it to a Univ
proc attach*[T: Comp](owner: Univ) : ptr T {.discardable.} =
  attach[T](cast[Elem](owner))

# get the instance of a Comp sub-type attached to a given Elem
proc getComp*[T: Comp](owner: Elem): ptr T =
  let name = typedesc[T].name
  if name notin owner.univ.compAllocs:
    echo "EXCEPTION: Comp " & name & " not registered w/ Univ"
    return nil
  if name notin owner.comps:
    echo "EXCEPTION: Comp " & name & " not found in Node"
    return nil
  var compAlloc = cast[CompAlloc[T]](owner.univ.compAllocs[name])
  var curPage = addr compAlloc.comps
  var index = owner.comps[name].index
  while index >= compsPerPage: # skip ahead to the given Page, given the index
    index = index - compsPerPage
    curPage = curPage.next
  addr curPage.contents[index]

# get the instance of a Comp sub-type attached to a given Univ
proc getComp*[T: Comp](owner: Univ): ptr T =
  getComp[T](cast[Elem](owner))

# get a named child Elem of a given Elem
proc getElem*(node: Elem, search: string): Elem =
  #TODO: upgrade to parse `search`, allowing for hierarchical Elem tree traversal
  let name = search
  if name notin node.elems:
    echo "EXCEPTION: relative Elem not found"
    return nil
  cast[Elem](node.elems[name])

# destroy a given Univ
proc destroy*[T: Univ](node: var T) =
  node.internalDestroying = true
  #[
  if nch.root == addr node:
    nch.root = nil
    node = nil # ???
  ]#

# destroy a given Elem
proc destroy*[T: Elem](elem: T) =
  elem.internalDestroying = true

# "finish off" a given Elem. do this e.g. at the end of a frame
proc bury*[T: Elem](elem: var T) =
  for i in elem.comps.pairs:
    var key: string
    var val: CompRef
    (key, val) = i
    
    elem.univ.compAllocs[key].vacancies.add(val.index) # add a vacancy to the memory manager
  elem = nil

# destroy a given instance of a Comp sub-type
proc destroy*[T: Comp](comp: ptr T) =
  comp.active = false
  comp.internalDestroying = true

# "finish off" a given instance of a Comp sub-type. do this e.g. at the end of a frame
proc bury[T: Comp](comp: var ptr T) =
  #TODO: onDestroy?
  discard

# iterate through all active instances of a given Comp sub-type in a given Univ
iterator mitems*[T: Comp](univ: Univ): ptr T =
  var curPage = addr cast[CompAlloc[T]](univ.compAllocs[typedesc[T].name]).comps
  while curPage != nil:
    for i in curPage.contents.mitems:
      if i.active: # skip inactive Comps
        yield addr i
    curPage = curPage.next

# iterate through all procs in a subscription
iterator items*[T: proc](event: Event[T]): (T, CompRef) =
  for i in event.before:
    yield i
  for i in event.on:
    yield i
  for i in event.after:
    yield i

import nchpkg/sys
export sys





### DEMO ###
type
  # input definitions for InputMgr
  Input {.pure.} = enum none, left, right, action, restart, quit

  # sample Comp
  TestComp = object of Comp
    things: int

# create a new TestComp instance
proc newTestComp*(owner: Elem): TestComp =
  result = TestComp(things: 42)
  result.initComp(owner)

# convert input scancodes into an Input
proc toInput*(key: Scancode): Input =
  case key
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_ESCAPE: Input.quit
  else: Input.none

# tests
when isMainModule:
  var app: Univ
  initUniv(app, "nch test app")
  var world = app.add("world")

  register[TimestepMgr](app, newTimestepMgr)
  attach[TimestepMgr](app)

  register[InputMgr[Input]](app, newInputMgr[Input], regInputMgr[Input])
  register[Renderer](app, newRenderer, regRenderer)
  attach[Renderer](app).initialize()
  register[TestComp](app, newTestComp)

  register[VecTri](app, newVecTri, regVecTri)

  attach[InputMgr[Input]](app).initialize(toInput)

  #attach[TestComp](world)

  attach[VecTri](app)

  var p1 = world.add("player1")
  attach[VecTri](p1)

  getComp[TimestepMgr](app).initialize()
