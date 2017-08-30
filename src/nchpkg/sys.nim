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

proc newTimestepMgr*(owner: Elem): TimestepMgr =
  result = TimestepMgr()
  result.initComp(owner)





### InputMgr ###

type
  InputMgr*[T: enum] = object of Comp
    input: array[T, bool]
    inputLast: array[T, bool]
    handler: proc (key: Scancode): T
  
  InputState* {.pure.} = enum up, pressed, down, released

proc newInputMgr*[T: enum](owner: Elem): InputMgr[T] =
  result = InputMgr[T]()
  result.initComp(owner)

proc tick*[T: enum](mgr: ref InputMgr[T]) =
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


proc setHandler*[T: enum](mgr: var InputMgr[T], handler: proc (key: Scancode): T) =
  mgr.handler = handler

proc getInput*[T: enum](mgr: InputMgr[T], input: T): InputState =
  if not mgr.input[input] and not mgr.inputLast[input]: return InputState.up
  if mgr.input[input] and not mgr.inputLast[input]: return InputState.pressed
  if mgr.input[input] and mgr.inputLast[input]: return InputState.down
  return InputState.released



### Renderer ###

type
  Renderer* = object of Comp
    ren: RendererPtr
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

proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()


proc initialize*(mgr: TimestepMgr) =
  while not mgr.univ[].destroying:
    getComp[Renderer](mgr.univ[]).ren.setDrawColor(0, 0, 0, 255)
    getComp[Renderer](mgr.univ[]).ren.clear()
    getComp[Renderer](mgr.univ[]).ren.present()