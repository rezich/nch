# nch standard library

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
    evTick*: nch.Event[proc (univ: Univ, dt: float)]

# create a new TimestepMgr instance
proc newTimestepMgr*(owner: Elem): TimestepMgr =
  result = TimestepMgr(
    evTick: newEvent[proc (univ: Univ, dt: float)]()
  )

# initialize a given TimestepMgr
proc initialize*(mgr: var TimestepMgr) =
  while not mgr.univ.internalDestroying:
    for ev in mgr.evTick:
      let (p, _) = ev
      p(mgr.internalUniv, 0.0)
    mgr.univ.cleanup()


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
  before(getComp[TimestepMgr](univ).evTick, inputMgr_tick[T])

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
    evDraw*: nch.Event[proc (univ: Univ, ren: ptr Renderer)]
    width: int
    height: int
    center: Point
  
  # exception sub-type for SDL things
  SDLException = object of Exception

proc point*(x: int, y: int): Point =
  (x.cint, y.cint)

converter toPoint*(v: Vector2d): Point = result = point(v.x, v.y)

proc worldToScreen*(renderer: ptr Renderer, v: Vector2d): Point =
  point(renderer.center.x.float + v.x, renderer.center.y.float - v.y)

# create a new Renderer instance
proc newRenderer*(owner: Elem): Renderer =
  result = Renderer(
    evDraw: newEvent[proc (univ: Univ, ren: ptr Renderer)]()
  )

# allow SDL to fail gracefully
template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

# initialize a given Renderer instance
proc initialize*(renderer: var Renderer, width: int, height: int) =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "0")):
    "Point texture filtering could not be enabled"

  renderer.win = createWindow(title = renderer.internalUniv.name,
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = width.cint, h = height.cint, flags = SDL_WINDOW_SHOWN)
  sdlFailIf renderer.win.isNil: "Window could not be created"

  renderer.width = width
  renderer.height = height
  renderer.center = point(width / 2, height / 2)

  renderer.ren = renderer.win.createRenderer(index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync)
  sdlFailIf renderer.ren.isNil: "Renderer could not be created"

# render things to the screen
proc tick(renderer: ptr Renderer, dt: float) =
  renderer.ren.setDrawColor(0, 0, 0, 255)
  renderer.ren.clear()

  for ev in renderer.evDraw:
    let (p, _) = ev
    p(renderer.internalUniv, renderer)

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
  after(getComp[TimestepMgr](univ).evTick, renderer_tick)
