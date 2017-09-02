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

### TimestepMgr - attempts to execute tick events at a given framerate  ###
type
  TimestepMgr* = object of Comp
    fpsman: FpsManager
    onTick*: nch.Event[proc (univ: Univ, dt: float)]

# create a new TimestepMgr instance
proc newTimestepMgr*(owner: Elem): TimestepMgr =
  result = TimestepMgr(
    onTick: newEvent[proc (univ: Univ, dt: float)](),
  )
  result.initComp(owner)

# initialize a given TimestepMgr
proc initialize*(mgr: var TimestepMgr) =
  while not mgr.univ.internalDestroying:
    for e in mgr.onTick:
      e(mgr.internalUniv, 0.0)


### InputMgr - handles user input ###
type
  InputMgr*[T: enum] = object of Comp
    input: array[T, bool]
    inputLast: array[T, bool]
    handler*: proc (key: Scancode): T
  
  # button state enumeration
  InputState* {.pure.} = enum up, pressed, down, released

# update input state
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

# InputMgr tick event
proc inputMgr_tick*[T: enum](univ: Univ, dt: float) =
  for comp in mitems[InputMgr[T]](univ):
    tick[T](comp, dt)

# create a new InputMgr instance
proc newInputMgr*[T: enum](owner: Elem): InputMgr[T] =
  result = InputMgr[T]()
  result.initComp(owner)

# register InputMgr with a given Univ
proc regInputMgr*[T: enum](univ: Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, inputMgr_tick[T])

# initialize a given InputMgr
proc initialize*[T: enum](mgr: var InputMgr[T], handler: proc (key: Scancode): T) =
  mgr.handler = handler

# get the current state of a given input
proc getInput*[T: enum](mgr: var InputMgr[T], input: T): InputState =
  if not mgr.input[input] and not mgr.inputLast[input]: return InputState.up
  if mgr.input[input] and not mgr.inputLast[input]: return InputState.pressed
  if mgr.input[input] and mgr.inputLast[input]: return InputState.down
  return InputState.released




### Renderer - SDL-based graphical renderer ###
type
  Renderer* = object of Comp
    ren*: RendererPtr
    win: WindowPtr
  
  # exception sub-type for SDL things
  SDLException = object of Exception

# create a new Renderer instance
proc newRenderer*(owner: Elem): Renderer =
  result = Renderer()
  result.initComp(owner)

# allow SDL to fail gracefully
template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

# initialize a given Renderer instance
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

# render things to the screen
proc tick(renderer: ptr Renderer, dt: float) =
  #echo repr renderer.ren
  renderer.ren.setDrawColor(0, 64, 0, 255)
  renderer.ren.clear()

  renderer.ren.setDrawColor(0, 192, 0, 255)
  var points = newSeq[Point]()
  points.add((0.cint, 0.cint))
  points.add((100.cint, 100.cint))
  renderer.ren.drawLines(addr points[0], points.len.cint)

  renderer.ren.present()

# Renderer tick event
proc renderer_tick(univ: Univ, dt: float) =
  for comp in mItems[Renderer](univ):
    comp.tick(dt)

# shut down a given Renderer
proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()

# register Renderer with a given Univ
proc regRenderer*(univ: Univ) =
  subscribe(getComp[TimestepMgr](univ).onTick, renderer_tick)
  discard