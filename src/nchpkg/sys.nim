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
    evTick*: nch.Event[proc (univ: Elem, dt: float)]

proc regTimestepMgr*(univ: Elem) =
  register[TimestepMgr](
    univ,
    proc (owner: Elem): TimestepMgr =
      result = TimestepMgr(
        evTick: newEvent[proc (univ: Elem, dt: float)]()
      )
    ,
    proc (owner: Elem) =
      discard
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

proc regInputMgr*[T: enum](univ: Elem) =
  register[InputMgr[T]](
    univ,
    proc (owner: Elem): InputMgr[T] =
      result = InputMgr[T]()
      result.initComp(owner)
    ,
    proc (owner: Elem) =
      before(getComp[TimestepMgr](univ).evTick, proc (univ: Elem, dt: float) =
        for mgr in mitems[InputMgr[T]](univ):
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
      )
  )

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
  Camera* = object of Comp
    size*: float

  Renderer* = object of Comp
    ren*: RendererPtr
    win: WindowPtr
    evDraw*: nch.Event[proc (univ: Elem, ren: ptr Renderer)]
    width: int
    height: int
    center: Point
    camera*: ptr Camera
    camMatrix*: Matrix2d
  
  # exception sub-type for SDL things
  SDLException = object of Exception

proc worldToScreen*(renderer: ptr Renderer, v: Vector2d): Point =
  #var p = (v & renderer.camMatrix).toPoint2d() - renderer.camera.owner.pos
  (v.toPoint2d() & renderer.camMatrix).toPoint()

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

proc getMatrix*(cam: ptr Camera, renderer: ptr Renderer): Matrix2d =
  #cam.owner.getTransform
  move(-cam.owner.globalPos) & rotate(cam.owner.rot) & scale(min(renderer.width, renderer.height).float / cam.size) & stretch(cam.owner.scale.x, -cam.owner.scale.y) & move(renderer.center.x.float, renderer.center.y.float)

# shut down a given Renderer
proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()

proc initialize*(camera: ptr Camera, size: float) =
  camera.size = size

# register Renderer with a given Univ
proc regRenderer*(univ: Elem) =
  register[Renderer](
    univ,
    proc (owner: Elem): Renderer =
      result = Renderer(
        evDraw: newEvent[proc (univ: Elem, ren: ptr Renderer)](),
        camera: nil
      )
    ,
    proc (owner: Elem) =
      register[Camera](
        univ,
        proc (owner: Elem): Camera =
          result = Camera(
            size: 1
          )
          if getUp[Renderer](owner).camera == nil:
            getUp[Renderer](owner).camera = addr(result)
        ,
        proc (owner: Elem) =
          discard
      )
      after(getComp[TimestepMgr](univ).evTick, proc (univ: Elem, dt: float) =
        for renderer in mItems[Renderer](univ):
          renderer.ren.setDrawColor(0, 0, 0, 255)
          renderer.ren.clear()
        
          if renderer.camera == nil:
            return
          
          renderer.camMatrix = renderer.camera.getMatrix(renderer)
        
          for ev in renderer.evDraw:
            let (p, _) = ev
            p(renderer.internalUniv, renderer)
        
          renderer.ren.present()
      )
  )
