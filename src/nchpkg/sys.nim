import ../nch

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

### TimestepMgr ###
type
  TimestepMgr* = object of Comp
    fpsman: FpsManager
    onTick*: nch.Event[proc (univ: Univ, dt: float)]

proc newTimestepMgr*(owner: Elem): TimestepMgr =
  result = TimestepMgr(
    onTick: newEvent[proc (univ: Univ, dt: float)](),
  )
  result.initComp(owner)

proc initialize*(mgr: var TimestepMgr) =
  while not mgr.univ.internalDestroying:
    for e in mgr.onTick:
      e(mgr.internalUniv, 0.0)


### InputMgr ###
type
  InputMgr*[T: enum] = object of Comp
    input: array[T, bool]
    inputLast: array[T, bool]
    handler*: proc (key: Scancode): T
  
  InputState* {.pure.} = enum up, pressed, down, released

proc tick*[T: enum](mgr: ptr InputMgr[T], dt: float) =
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
  for comp in mitems[InputMgr[T]](univ):
    tick[T](comp, dt)

proc newInputMgr*[T: enum](owner: Elem): InputMgr[T] =
  result = InputMgr[T]()
  result.initComp(owner)

proc regInputMgr*[T: enum](univ: Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, inputMgr_tick[T])

proc initialize*[T: enum](mgr: var InputMgr[T], handler: proc (key: Scancode): T) =
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
    w = 640, h = 480, flags = SDL_WINDOW_SHOWN)
  sdlFailIf renderer.win.isNil: "Window could not be created"

  renderer.ren = renderer.win.createRenderer(index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync)
  sdlFailIf renderer.ren.isNil: "Renderer could not be created"

proc tick(renderer: ptr Renderer, dt: float) =
  #echo repr renderer.ren
  renderer.ren.setDrawColor(0, 64, 0, 255)
  renderer.ren.clear()
  renderer.ren.present()

proc renderer_tick(univ: Univ, dt: float) =
  for comp in mItems[Renderer](univ):
    comp.tick(dt)

proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()

proc regRenderer*(univ: Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, renderer_tick)
  discard