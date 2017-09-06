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
  compsPerPage = 2 #TODO: make per-Comp setting. this might require a lot of work

type
  # memory manager container
  Page*[T; N: static[int]] = object of RootObj
    contents*: array[0..N, T]
    next: ptr Page[T, N]

  #TODO
  Node* = object of RootObj
    name*: string
    internalUniv*: Univ
    internalDestroying*: bool
  
  #TODO
  CompAllocBase* = ref object of RootObj
    vacancies: seq[int]
    size: int

  # Comp allocator, stored in a Univ
  CompAlloc*[T] = ref object of CompAllocBase
    comps*: Page[T, compsPerPage]
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
    compPtr: ptr Comp
  
  #TODO
  Event*[T: proc] = ref object of RootObj
    before*: seq[(T, CompRef)]
    on*: seq[(T, CompRef)]
    after*: seq[(T, CompRef)]

  # element, the smallest unit of organization
  Elem* = ref object of Node
    elems: OrderedTableRef[string, Elem]
    comps: OrderedTableRef[string, CompRef]
    pos*: Vector2d
    scale*: Vector2d
    rot*: float
    parent*: Elem
    prev: Elem
    next: Elem
    last: Elem

  # universe, top-level element
  Univ* = ref object of Elem
    compAllocs*: OrderedTableRef[string, CompAllocBase]
    destroyingElems: seq[Elem]

  # container for the entire engine
  Nch* = object of RootObj
    root*: ptr Univ

# singleton container for the entire engine
var nch* = Nch(root: nil)

proc nilCompRef*(): CompRef =
  CompRef(
    empty: true
  )

proc getTransform*(elem: Elem): Matrix2d =
  result = rotate(elem.rot) & stretch(elem.scale.x, elem.scale.y) & move(elem.pos)
  var parent = elem.parent
  while parent != nil:
    result = parent.getTransform() & result
    parent = parent.parent

proc globalPos*(elem: Elem): Vector2d =
  result = elem.pos
  var parent = elem.parent
  while parent != nil:
    result = parent.pos + result
    parent = parent.parent

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
  elem.comps = newOrderedTable[string, CompRef]()
  elem.pos = vector2d(0.0, 0.0)
  elem.scale = vector2d(1.0, 1.0)
  elem.rot = 0.0
  elem.parent = parent
  elem.prev = nil
  elem.next = nil
  elem.last = nil

# initialize a Univ
proc initUniv*(univ: var Univ, name: string) =
  univ = Univ(
    name: name,
    compAllocs: newOrderedTable[string, CompAllocBase](),
    destroyingElems: @[]
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
  if name in parent.elems:
    if parent.elems[name].last == nil:
      result.prev = parent.elems[name]
      parent.elems[name].next = result
    else:
      result.prev = parent.elems[name].last
      parent.elems[name].last.next = result
    parent.elems[name].last = result
  else:
    parent.elems[name] = result

# initialize a Comp
proc initComp*[T: Comp](comp: var T, owner: Elem) =
  comp.name = typedesc[T].name
  comp.active = true
  comp.owner = owner
  comp.internalUniv = owner.univ
  comp.internalDestroying = false

# create the first Page for the memory manager
proc newPage[T: Comp](): Page[T, compsPerPage] =
  result = Page[T, compsPerPage](
    next: nil
  )
  for i in result.contents.mitems:
    i.active = false

# create an additional Page for the memory manager
proc newPage[T: Comp](prev: ptr Page[T, compsPerPage], compsPerPage: static[int]): ptr Page[T, compsPerPage] {.discardable.} =
  result = cast[ptr Page[T, compsPerPage]](alloc(sizeof(Page[T, compsPerPage])))
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
    vacancies: @[],
    size: sizeof(T)
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
      newPage[T](curPage, compsPerPage)
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
    index: index,
    compPtr: result
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
    nch.root = nilcd;
    node = nil # ???
  ]#

# destroy a given Elem
proc destroy*[T: Elem](elem: T) =
  #TODO: make sure all of this works!!
  elem.internalDestroying = true
  elem.univ.destroyingElems.add(elem)
  if elem.prev != nil:
    if elem.next == nil: # this is the last elem in the sequence
      elem.prev.next = nil
      elem.parent.elems[elem.name].last = elem.prev
    else:
      elem.prev.next = elem.next
      elem.next.prev = elem.prev
  else:
    if elem.next != nil: # this is the first elem in the seq
      elem.next.last = elem.last
      elem.parent.elems[elem.name] = elem.next
      elem.next.prev = nil
  for child in elem.elems.mvalues:
    child.destroy()

# "finish off" a given Elem. do this e.g. at the end of a frame
proc bury*[T: Elem](elem: var T) =
  for i in elem.comps.pairs:
    var key: string
    var val: CompRef
    (key, val) = i
    #TODO: bury Comps
    elem.univ.compAllocs[key].vacancies.add(val.index) # add a vacancy to the memory manager
    val.compPtr.owner = nil
    val.compPtr.active = false
  elem = nil

# destroy a given instance of a Comp sub-type
proc destroy*[T: Comp](comp: ptr T) =
  comp.active = false
  comp.internalDestroying = true

proc cleanup*(univ: Univ) =
  for elem in univ.destroyingElems.mitems:
    bury(elem)
  univ.destroyingElems = @[]

iterator mitems*(elem: var Elem): Elem =
  var e = elem
  yield e
  while e.next != nil:
    yield e.next
    e = e.next

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
import nchpkg/vgfx



### DEMO ###
type
  # input definitions for InputMgr
  Input {.pure.} = enum none, up, down, left, right, action, restart, quit
  
  PlayerController = object of Comp
    font: VecFont

proc newPlayerController*(owner: Elem): PlayerController =
  result = PlayerController(
    font: vecFont("sys")
  )

proc tick(player: ptr PlayerController, dt: float) =
  let inputMgr = getComp[InputMgr[Input]](player.univ)
  let owner = player.owner
  let speed = 4.0
  if inputMgr.getInput(Input.up) == InputState.down:
    owner.pos.y += speed
  if inputMgr.getInput(Input.down) == InputState.down:
    owner.pos.y -= speed
  if inputMgr.getInput(Input.left) == InputState.down:
    owner.pos.x -= speed
  if inputMgr.getInput(Input.right) == InputState.down:
    owner.pos.x += speed
  if inputMgr.getInput(Input.action) == InputState.pressed:
    owner.destroy()

proc playerController_draw*(univ: Univ, ren: ptr Renderer) =
  for comp in mitems[PlayerController](univ):
    #ren.drawChar(comp.owner.pos, '@', comp.font, vector2d(200, 200))
    ren.drawString(comp.owner.pos, "NCH", comp.font, vector2d(72, 72), vector2d(15, 15), TextAlign.center, 0.75)
  discard

proc playerController_tick*(univ: Univ, dt: float) =
  for comp in mitems[PlayerController](univ):
    comp.tick(dt)

proc regPlayerController*(univ: Univ) =
  on(getComp[TimestepMgr](univ).evTick, playerController_tick)
  on(getComp[Renderer](univ).evDraw, playerController_draw)

# convert input scancodes into an Input
proc toInput*(key: Scancode): Input =
  case key
  of SDL_SCANCODE_UP: Input.up
  of SDL_SCANCODE_DOWN: Input.down
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_ESCAPE: Input.quit
  of SDL_SCANCODE_RETURN: Input.action
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
  attach[Renderer](app).initialize(320, 240)
  attach[InputMgr[Input]](app).initialize(toInput)
  register[PlayerController](app, newPlayerController, regPlayerController)

  register[VecText](app, newVecText, regVecText)

  var p1 = world.add("player")
  attach[PlayerController](p1)
  p1.pos = vector2d(0, 0)

  var p2 = world.add("player")
  attach[VecText](p2).initialize("experimental interactive", TextAlign.right, vector2d(8, 7), vector2d(2.5, 5))
  p2.pos = vector2d(154, 46)

  var p3 = p1.add("player")
  attach[VecText](p3).initialize("multimedia framework", TextAlign.left, vector2d(9, 7), vector2d(4, 5))
  p3.pos = vector2d(-154, -46)

  getComp[TimestepMgr](app).initialize()
