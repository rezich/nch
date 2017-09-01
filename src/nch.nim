# nch #

import
  tables,
  typetraits,
  sequtils,
  future

import sdl2, sdl2/gfx, sdl2.image, sdl2.ttf, basic2d, random, math

{.experimental.}


### SYSTEM ###

const
  compsPerPage = 1024

proc box*[T](x: T): ref T =
  new(result); result[] = x

type
  Page*[T] = object of RootObj
    contents*: array[0..compsPerPage, T]
    next: ptr Page[T]
  
  Event*[T: proc] = ref object of RootObj
    subscriptions*: seq[T]

  Node* = object of RootObj
    name*: string
    internalUniv*: ref Univ
    internalDestroying: bool
    relatives: OrderedTableRef[string, ptr Node]
  
  CompAllocBase* = ref object of RootObj

  CompAlloc*[T] = ref object of CompAllocBase
    comps*: Page[T]
    newProc: proc (owner: Elem): T
    last: int
    vacancies: array[0..compsPerPage, T]

  Elem* = ref object of Node

  Univ* = ref object of Elem
    compAllocs*: OrderedTableRef[string, CompAllocBase]

  Comp* = object of Node

  Nch* = object of RootObj
    root*: ptr Univ

var nch* = Nch(root: nil)

proc subscribe*[T](event: Event[T], procedure: T) =
  event.subscriptions.add(procedure)

proc newEvent*[T](): Event[T] =
  Event[T](
    subscriptions: newSeq[T]()
  )

proc destroying*(node: ref Node): bool =
  node.internalDestroying
    
proc univ*(node: Node): ref Univ =
  return node.internalUniv

proc univ*(node: ref Node): ref Univ =
  if node.internalUniv == nil:
    return cast[ref Univ](box(node))
  return node.internalUniv

proc initElem[T: Elem](elem: var T, parent: Elem = nil) =
  if parent != nil:
    elem.internalUniv = parent.univ
  elem.internalDestroying = false
  elem.relatives = newOrderedTable[string, ptr Node]()
  elem.relatives[".."] = cast[ptr Node](addr(parent[]))

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

proc destroy*[T: Univ](node: var T) =
  node.internalDestroying = true
  #[
  if nch.root == addr node:
    nch.root = nil
    node = nil # ???
  ]#
  
proc add*[T: Elem](parent: var T, name: string): Elem {.discardable.} =
  new(result)
  result.name = name
  initElem(result, cast[Elem](parent))
  echo cast[ByteAddress](addr(result))
  parent.relatives[name] = cast[ptr Node](addr(result))

proc initComp*[T: Comp](comp: var T, owner: Elem) =
  comp.name = typedesc[T].name
  comp.relatives = newOrderedTable[string, ptr Node]()
  comp.internalUniv = owner.univ
  comp.internalDestroying = false

proc newCompAlloc[T: Comp](newProc: proc (owner: Elem): T) : CompAlloc[T] =
  result = CompAlloc[T](
    comps: Page[T](
      next: nil
    ),
    last: 0,
    newProc: newProc
  )

proc register*[T](univ: var Univ, newProc: proc (owner: Elem): T, regProc: proc (univ: var Univ) = nil) =
  let name = typedesc[T].name
  if name in univ.compAllocs:
    echo "EXCEPTION: " & name & " already registered in this Univ"
    return
  univ.compAllocs[name] = newCompAlloc[T](newProc)
  if (regProc != nil):
    regProc(univ)


proc allocComp[T: Comp](univ: var Univ): ptr T =
  let name = typedesc[T].name
  if name notin univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return
  # TODO: use empty spaces if available
  let compAlloc = cast[CompAlloc[T]](univ.compAllocs[name])
  #if (compAlloc.last mod compsPerPage)
  compAlloc.comps.contents[compAlloc.last] = compAlloc.newProc(univ)
  result = addr compAlloc.comps.contents[compAlloc.last]
  compAlloc.last += 1
  #return compAlloc.comps[compAlloc.comps.high]

proc attach*[T: Comp](owner: var Node): ptr T {.discardable.} =
  echo owner.name
  echo owner.univ.name
  result = allocComp[T](owner.univ)
  if typedesc[T].name == "Renderer":
    echo cast[ByteAddress](addr(result)[])
  result.relatives["<"] = addr(owner)
  owner.relatives[">" & result.name] = result

proc getComp*[T: Comp](node: var Node): ptr T =
  if typedesc[T].name notin node.univ.compAllocs:
    echo "EXCEPTION: Comp " & typedesc[T].name & " not registered w/ Univ"
    return nil
  let name = ">" & typedesc[T].name
  if name notin node.relatives:
    echo "EXCEPTION: Comp not found in Node"
    return nil
  return cast[ptr T](node.relatives[name])

proc getCompInternal*[T: Comp](node: ref Node): var T =
  let name = ">" & typedesc[T].name
  return cast[var T](node.relatives[name])

proc getElem*(node: Elem, search: string): Elem =
  let name = search
  if name notin node.relatives:
    echo "EXCEPTION: relative Elem not found"
    return nil
  return cast[Elem](node.relatives[name])

import nchpkg/sys.nim
export sys



### DEMO ###

type
  Input {.pure.} = enum none, left, right, action, restart, quit

  TestComp = object of Comp
    things: int

proc newTestComp(owner: Elem): TestComp =
  result = TestComp(things: 42)
  result.initComp(owner)
  
proc toInput*(key: Scancode): Input =
  case key
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_ESCAPE: Input.quit
  else: Input.none

### TESTS ###

when isMainModule:
  var app: Univ
  initUniv(app, "nch test app")

  var world = app.add("world")
  assert(world.relatives[".."].name == "nch test app")
  echo cast[ByteAddress](addr(world[]))
  for i in app.relatives.keys:
    echo i
  #echo app.relatives["world"].relatives[".."]
  #assert(app.relatives["world"].name == "world")
  
  assert(addr(app) == nch.root)

  register[TimestepMgr](app, newTimestepMgr)
  attach[TimestepMgr](app)
  register[TestComp](app, newTestComp)
  register[InputMgr[Input]](app, newInputMgr[Input], regInputMgr[Input])
  register[Renderer](app, newRenderer, regRenderer)

  
  attach[Renderer](app)
  attach[InputMgr[Input]](app)
  attach[TestComp](world)
  

  assert(world.relatives[">TestComp"] != nil)
  assert(app.relatives[">InputMgr[nch.Input]"] != nil)

  assert(getComp[InputMgr[Input]](app).getInput(Input.action) == InputState.up)

  assert(getComp[TestComp](world) != nil)
  assert(getComp[TimestepMgr](app) != nil)

  assert(app.getElem("world") != nil)

  getComp[InputMgr[Input]](app).setHandler(toInput)
  #echo repr getComp[InputMgr[Input]](app).handler

  # fake game loop time
  
  #getComp[InputMgr[Input]](app).initialize()
  getComp[Renderer](app).initialize()

  getComp[Renderer](app).ren.setDrawColor(255, 0, 0, 255)
  getComp[Renderer](app).ren.clear()
  getComp[Renderer](app).ren.present()

  echo cast[ByteAddress](addr(cast[CompAlloc[Renderer]](app.compAllocs[typedesc[Renderer].name]).comps.contents[0]))
  echo cast[ByteAddress](addr(getComp[Renderer](app)[]))
  echo cast[ByteAddress](addr(getCompInternal[Renderer](app)))

  getComp[TimestepMgr](app).initialize()

  getComp[Renderer](app).shutdown()
  
  #assert(app == nil)
