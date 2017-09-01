import ../nch

import
  tables,
  typetraits,
  sequtils,
  future

import sdl2, sdl2/gfx, sdl2.image, sdl2.ttf, basic2d, random, math


### Transform2D ###

type
  Transform2D* = object of RootObj



### TimestepMgr ###

type
  TimestepMgr* = object of Comp
    fpsman: FpsManager
    onTick*: nch.Event[proc (univ: var Univ, dt: float)]

proc newTimestepMgr*(owner: Elem): TimestepMgr =
  result = TimestepMgr(
    onTick: newEvent[proc (univ: var Univ, dt: float)]()
  )
  result.initComp(owner)



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
      mgr.univ[].destroy()
    of KeyDown:
      mgr.input[mgr.handler(event.key.keysym.scancode)] = true
    of KeyUp:
      mgr.input[mgr.handler(event.key.keysym.scancode)] = false
    else:
      discard

proc inputMgr_tick*[T: enum](univ: var Univ, dt: float) =
  for comp in cast[CompAlloc[InputMgr[T]]](univ.compAllocs[typedesc[InputMgr[T]].name]).comps.contents.mitems:
    tick[T](comp, dt)

proc newInputMgr*[T: enum](owner: Elem): InputMgr[T] =
  result = InputMgr[T]()
  result.initComp(owner)

proc regInputMgr*[T: enum](univ: var Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, inputMgr_tick[T])


proc setHandler*[T: enum](mgr: var InputMgr[T], handler: proc (key: Scancode): T) =
  #echo repr handler
  mgr.handler = handler
  #echo repr mgr.handler

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

proc renderer_tick(univ: var Univ, dt: float) =
  for comp in cast[CompAlloc[Renderer]](univ.compAllocs[typedesc[Renderer].name]).comps.contents.mitems:
    #echo repr comp.ren
    #comp.tick(dt)
    comp.tick(dt)

proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()

proc regRenderer*(univ: var Univ) =
  discard#subscribe(getComp[TimestepMgr](univ).onTick, renderer_tick)



proc initialize*(mgr: var TimestepMgr) =

  echo "SHOULD NOT BE NIL:"
  echo repr cast[CompAlloc[Renderer]](mgr.univ.compAllocs[typedesc[Renderer].name]).comps.contents[0].ren

  while not mgr.univ[].destroying:
    for e in mgr.onTick.subscriptions:
      e(mgr.univ[], 0.0)