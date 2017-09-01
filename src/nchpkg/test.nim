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
    internalUniv*: Univ
    internalDestroying: bool
  
  CompAllocBase* = ref object of RootObj

  CompAlloc*[T] = ref object of CompAllocBase
    comps*: Page[T]
    newProc: proc (owner: Elem): T
    last: int
    vacancies: array[0..compsPerPage, T]
  
  Comp* = object of Node
    active: bool
    owner: Elem

  CompRef* = object of RootObj
    name: string
    index: int

  Elem* = ref object of Node
    elems: OrderedTableRef[string, Elem]
    comps: OrderedTableRef[string, CompRef]

  Univ* = ref object of Elem
    compAllocs*: OrderedTableRef[string, CompAllocBase]

  Nch* = object of RootObj
    root*: ptr Univ

var nch* = Nch(root: nil)

proc subscribe*[T](event: Event[T], procedure: T) =
  event.subscriptions.add(procedure)

proc newEvent*[T](): Event[T] =
  Event[T](
    subscriptions: newSeq[T]()
  )

proc destroying*(node: Node): bool =
  node.internalDestroying
    
proc univ*[T: Elem](elem: T): Univ =
  if elem.internalUniv == nil:
    return cast[Univ](elem)
  elem.internalUniv

proc initElem[T: Elem](elem: var T, parent: Elem = nil) =
  if parent != nil:
    elem.internalUniv = parent.univ
  elem.internalDestroying = false
  elem.elems = newOrderedTable[string, Elem]()
  elem.elems[".."] = parent
  elem.comps = newOrderedTable[string, CompRef]()

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

proc add*[T: Elem](parent: var T, name: string): Elem {.discardable.} =
  new(result)
  result.name = name
  initElem(result, cast[Elem](parent))
  parent.elems[name] = result

proc initComp*[T: Comp](comp: var T, owner: Elem) =
  comp.name = typedesc[T].name
  comp.active = true
  comp.owner = owner
  comp.internalUniv = owner.univ
  comp.internalDestroying = false

proc newPage[T: Comp](prev: ptr Page[T] = nil): Page[T] =
  result = Page[T](
    next: nil
  )
  if prev != nil:
    prev.next = addr(result)
  for i in result.contents.mitems:
    i.active = false

proc newCompAlloc[T: Comp](newProc: proc (owner: Elem): T) : CompAlloc[T] =
  result = CompAlloc[T](
    comps: newPage[T](),
    last: 0,
    newProc: newProc
  )

proc register*[T](univ: Univ, newProc: proc (owner: Elem): T, regProc: proc (univ: Univ) = nil) =
  let name = typedesc[T].name
  if name in univ.compAllocs:
    echo "EXCEPTION: " & name & " already registered in this Univ"
    return
  univ.compAllocs[name] = newCompAlloc[T](newProc)
  if (regProc != nil):
    regProc(univ)


proc allocComp[T: Comp](univ: Univ): (ptr T, int) =
  let name = typedesc[T].name
  if name notin univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return
  # TODO: use empty spaces if available
  let compAlloc = cast[CompAlloc[T]](univ.compAllocs[name])
  #if (compAlloc.last mod compsPerPage)
  var index = compAlloc.last
  compAlloc.comps.contents[index] = compAlloc.newProc(univ)
  result = (addr compAlloc.comps.contents[compAlloc.last], index)
  compAlloc.last += 1

proc attach*[T: Comp](owner: Elem): ptr T {.discardable.} =
  var index : int
  (result, index) = allocComp[T](owner.univ)
  result.owner = owner
  owner.comps[result.name] = CompRef(
    name: result.name,
    index: index
  )

proc attach*[T: Comp](owner: Univ) : ptr T {.discardable.} =
  attach[T](cast[Elem](owner))

proc getComp*[T: Comp](owner: Elem): ptr T =
  let name = typedesc[T].name
  if name notin owner.univ.compAllocs:
    echo "EXCEPTION: Comp " & name & " not registered w/ Univ"
    return nil
  if name notin owner.comps:
    echo "EXCEPTION: Comp " & name & " not found in Node"
    return nil
  var compAlloc = cast[CompAlloc[T]](owner.univ.compAllocs[name])
  return cast[ptr T](addr(compAlloc.comps.contents[owner.comps[name].index])) #TODO: paging!

proc getComp*[T: Comp](owner: Univ): ptr T =
  getComp[T](cast[Elem](owner))

proc getElem*(node: Elem, search: string): Elem =
  let name = search
  if name notin node.elems:
    echo "EXCEPTION: relative Elem not found"
    return nil
  return cast[Elem](node.elems[name])

proc destroy*[T: Univ](node: var T) =
  node.internalDestroying = true
  #[
  if nch.root == addr node:
    nch.root = nil
    node = nil # ???
  ]#


### TimestepMgr ###
type
  TimestepMgr* = object of Comp
    fpsman: FpsManager
    onTick*: Event[proc (univ: Univ, dt: float)]

proc newTimestepMgr*(owner: Elem): TimestepMgr =
  result = TimestepMgr(
    onTick: newEvent[proc (univ: Univ, dt: float)](),
  )
  result.initComp(owner)

proc initialize*(mgr: var TimestepMgr) =
  while not mgr.internalUniv.destroying:
    for e in mgr.onTick.subscriptions:
      e(mgr.internalUniv, 0.0)


### InputMgr ###
type
  InputMgr*[T: enum] = object of Comp
    input: array[T, bool]
    inputLast: array[T, bool]
    handler*: proc (key: Scancode): T
  
  InputState* {.pure.} = enum up, pressed, down, released

proc tick*[T: enum](mgr: var InputMgr[T], dt: float) =
  shallowCopy(mgr.inputLast, mgr.input)
  var event = defaultEvent
  while pollEvent(event):
    case event.kind
    of QuitEvent:
      mgr.internalUniv.destroy()
      discard
    of KeyDown:
      mgr.input[mgr.handler(event.key.keysym.scancode)] = true
    of KeyUp:
      mgr.input[mgr.handler(event.key.keysym.scancode)] = false
    else:
      discard

proc inputMgr_tick*[T: enum](univ: Univ, dt: float) =
  for comp in cast[CompAlloc[InputMgr[T]]](univ.compAllocs[typedesc[InputMgr[T]].name]).comps.contents.mitems:
    tick[T](comp, dt)

proc newInputMgr*[T: enum](owner: Elem): InputMgr[T] =
  result = InputMgr[T]()
  result.initComp(owner)

proc regInputMgr*[T: enum](univ: Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, inputMgr_tick[T])


proc setHandler*[T: enum](mgr: var InputMgr[T], handler: proc (key: Scancode): T) =
  mgr.handler = handler

proc getInput*[T: enum](mgr: var InputMgr[T], input: T): InputState =
  if not mgr.input[input] and not mgr.inputLast[input]: return InputState.up
  if mgr.input[input] and not mgr.inputLast[input]: return InputState.pressed
  if mgr.input[input] and mgr.inputLast[input]: return InputState.down
  return InputState.released




### Renderer ###
type
  Renderer* = object of Comp
    ren*: RendererPtr
    win: WindowPtr
  
  SDLException = object of Exception

proc newRenderer*(owner: Elem): Renderer =
  result = Renderer()
  result.initComp(owner)

template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

proc initialize*(renderer: var Renderer) =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "0")):
    "Point texture filtering could not be enabled"

  renderer.win = createWindow(title = renderer.internalUniv.name,
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = 160, h = 120, flags = SDL_WINDOW_SHOWN)
  sdlFailIf renderer.win.isNil: "Window could not be created"

  renderer.ren = renderer.win.createRenderer(index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync)
  sdlFailIf renderer.ren.isNil: "Renderer could not be created"

proc tick(renderer: var Renderer, dt: float) =
  #echo repr renderer.ren
  renderer.ren.setDrawColor(0, 255, 0, 255)
  renderer.ren.clear()
  renderer.ren.present()

proc renderer_tick(univ: Univ, dt: float) =
  for comp in cast[CompAlloc[Renderer]](univ.compAllocs[typedesc[Renderer].name]).comps.contents.mitems:
    comp.tick(dt)

proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()

proc regRenderer*(univ: Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, renderer_tick)
  discard







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

when isMainModule:
  var app: Univ
  initUniv(app, "nch test app")
  var world = app.add("world")

  register[TimestepMgr](app, newTimestepMgr)
  attach[TimestepMgr](app)

  register[InputMgr[Input]](app, newInputMgr[Input], regInputMgr[Input])
  attach[InputMgr[Input]](app)
  register[Renderer](app, newRenderer, regRenderer)
  attach[Renderer](app)

  getComp[Renderer](app).initialize()
  getComp[InputMgr[Input]](app).setHandler(toInput)
  getComp[TimestepMgr](app).initialize()