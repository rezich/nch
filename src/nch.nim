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


converter toPoint2d*(x: Vector2d): Point2d = point2d(x.x, x.y)
converter toPoint*(x: Vector2d): Point = point(x.x.cint, x.y.cint)
converter toPoint*(x: Point2d): Point = point(x.x.cint, x.y.cint)
converter toVector2d*(x: Point2d): Vector2d = vector2d(x.x, x.y)
converter toVector2d*(x: Point): Vector2d = vector2d(x.x.float, x.y.float)

### SYSTEM ###
const
  compsPerPage = 2 #TODO: make per-Comp setting. this might require a lot of work

type
  # memory manager container
  Page*[T] = object of RootObj
    contents*: array[0..compsPerPage, T]
    next: ptr Page[T]

  #TODO
  Node* = object of RootObj
    name*: string
    internalUniv*: Elem
    internalDestroying*: bool
  
  #TODO
  CompAllocBase* = ref object of RootObj
    vacancies: seq[int]
    size: int

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
    compPtr: ptr Comp
    univ: Elem
  
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
    compAllocs*: OrderedTableRef[string, CompAllocBase]
    destroyingElems: seq[Elem]
    
  # container for the entire engine
  Nch* = object of RootObj
    root*: ptr Elem

# singleton container for the entire engine
var nch* = Nch(root: nil)


#[
  Easy: function(x, target, speed, snap) {
    if (speed === undefined)
      speed = 0.1;
    var ret = x + (target - x) * speed;
    if (snap === undefined)
      snap = 0.001;
    if (Math.abs(x - target) <= snap)
      ret = target;
    return ret;
  },
]#

proc ease(x: var float, target: float, speed: float = 0.1, snap: float = 0.01) =
  x = x + (target - x) * speed
  if (abs(x - target)) <= snap:
    x = target

proc pluralize(n: int, singular, plural: string): string =
  if n == 1:
    singular
  else:
    plural

proc nilCompRef*(): CompRef =
  CompRef(
    empty: true
  )

proc getTransform*(elem: Elem): Matrix2d =
  result = stretch(elem.scale.x, elem.scale.y) & rotate(elem.rot) & move(elem.pos)
  var parent = elem.parent
  while parent != nil:
    result = parent.getTransform() & result
    parent = parent.parent

proc globalPos*(elem: Elem): Vector2d =
  point2d(0, 0) & elem.getTransform

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
proc univ*[T: Elem](elem: T): Elem =
  if elem.internalUniv == nil:
    return elem
  elem.internalUniv

# gets the Univ the given Comp is a part of
proc univ*[T: Comp](comp: T): Elem =
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
  elem.compAllocs = nil
  elem.destroyingElems = nil

# initialize a Univ
proc initUniv*(univ: var Elem, name: string) =
  univ = Elem(
    name: name
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
  #[for i in result.contents.mitems:`
    i.active = false]#
  for i in 0..compsPerPage:
    result.contents[i] = T(active: false)

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
proc register*[T: Comp](univ: Elem, newProc: proc (owner: Elem): T, regProc: proc (univ: Elem) = nil) =
  let name = typedesc[T].name

  if univ.compAllocs == nil:
    univ.compAllocs = newOrderedTable[string, CompAllocBase]()
    univ.destroyingElems = @[]

  if name in univ.compAllocs:
    echo "EXCEPTION: " & name & " already registered in this Univ"
    return
  univ.compAllocs[name] = newCompAlloc[T](newProc)
  if regProc != nil:
    regProc(univ)

# allocate a new Comp inside a given Univ
proc allocComp[T: Comp](univ: Elem, owner: Elem): (ptr T, int) =
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
  var curPageNum = 0
  while index >= compsPerPage: # skip ahead to the necessary Page, given the index
    index = index - compsPerPage
    if curPage.next == nil:
      newPage[T](curPage)
    curPage = curPage.next
    inc curPageNum
  #echo "allocating " & name & "#" & $realIndex
  #echo "    (page " & $curPageNum & ", index " & $index & ")"
  if curPage == nil:
    echo "ERROR: SHOULD NOT BE NIL"
  
  curPage.contents[index] = compAlloc.newProc(owner)
  result = (cast[ptr T](addr(curPage.contents[index])), realIndex)

proc getUpAlloc[T: Comp](elem: Elem): Elem =
  #TODO: cache!
  let name = typedesc[T].name
  result = nil
  var parent = elem
  while parent != nil and result == nil:
    if parent.compAllocs == nil:
      parent = parent.parent
    else:
      if name in parent.compAllocs:
        result = parent
      else:
        parent = parent.parent
  if result == nil:
    echo "EXCEPTION: getUpAlloc[" & name & "] failed"
  
# create a new instance of a Comp sub-type and attach it to an Elem
proc attach*[T: Comp](owner: Elem): ptr T {.discardable.} =
  #TODO: figure out a way to check if owner already has the same Comp
  var index : int
  let univ = getUpAlloc[T](owner)
  (result, index) = allocComp[T](univ, owner)
  result.initComp(owner)
  owner.comps[result.name] = CompRef(
    name: result.name,
    index: index,
    compPtr: result,
    univ: univ
  )

# get the instance of a Comp sub-type attached to a given Elem
proc getComp*[T: Comp](owner: Elem): ptr T =
  let name = typedesc[T].name
  let upAlloc = getUpAlloc[T](owner)
  if name notin upAlloc.compAllocs:
    echo "EXCEPTION: Comp " & name & " not registered w/ Univ"
    return nil
  if name notin owner.comps:
    echo "EXCEPTION: Comp " & name & " not found in Node"
    return nil
  var compAlloc = cast[CompAlloc[T]](upAlloc.compAllocs[name])
  var curPage = addr compAlloc.comps
  var index = owner.comps[name].index
  while index >= compsPerPage: # skip ahead to the given Page, given the index
    index = index - compsPerPage
    curPage = curPage.next
  addr curPage.contents[index]

# get a named child Elem of a given Elem
proc getElem*(node: Elem, search: string): Elem =
  #TODO: upgrade to parse `search`, allowing for hierarchical Elem tree traversal
  let name = search
  if name notin node.elems:
    echo "EXCEPTION: relative Elem not found"
    return nil
  cast[Elem](node.elems[name])

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
  #[
  if nch.root == addr node:
    nch.root = nilcd;
    node = nil # ???
  ]#

# "finish off" a given Elem. do this e.g. at the end of a frame
proc bury*[T: Elem](elem: var T) =
  for i in elem.comps.pairs:
    var key: string
    var val: CompRef
    (key, val) = i
    #TODO: bury Comps
    val.univ.compAllocs[key].vacancies.add(val.index) # add a vacancy to the memory manager
    val.compPtr.owner = nil
    val.compPtr.active = false
  elem = nil

# destroy a given instance of a Comp sub-type
proc destroy*[T: Comp](comp: ptr T) =
  comp.active = false
  comp.internalDestroying = true

proc cleanup*(univ: Elem) =
  for elem in univ.destroyingElems.mitems:
    bury(elem)
  univ.destroyingElems = @[]

iterator siblings*(elem: var Elem): Elem =
  var e = elem
  yield e
  while e.next != nil:
    yield e.next
    e = e.next

# iterate through all active instances of a given Comp sub-type in a given Univ
iterator mitems*[T: Comp](univ: Elem): ptr T =
  var curPage = addr cast[CompAlloc[T]](univ.compAllocs[typedesc[T].name]).comps
  while curPage != nil:
    for i in curPage.contents.mitems:
      if i.active and not i.owner.internalDestroying: # skip inactive Comps
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


proc getUp*[T: Comp](elem: Elem): ptr T =
  #TODO: cache!
  result = nil
  let name = typedesc[T].name
  var parent = elem.parent
  while parent != nil and result == nil:
    if name in parent.comps:
      result = cast[ptr T](
        getComp[T](parent)
      )
    else:
      parent = parent.parent
  if result == nil:
    echo "EXCEPTION: couldn't getUp[" & name & "] on Elem!"


### DEMO ###
import
  nchpkg/sys,
  nchpkg/phy,
  nchpkg/vgfx


type
  # input definitions for InputMgr
  Input {.pure.} = enum none, up, down, left, right, action, restart, quit
  
  PlayerController = object of Comp
    font: VecFont
    score*: int
  
  Bullet = object of Comp
    velocity: Vector2d
  
  Enemy = object of Comp

proc newEnemy*(owner: Elem): Enemy =
  result = Enemy()


proc regBullet*(univ: Elem) =
  register[Bullet](
    univ,
    proc (owner: Elem): Bullet =
      result = Bullet(
        velocity: vector2d(0.1, 0)
      )
      on(getComp[CircleCollider](owner).evCollision, proc (a, b: ptr Collider) =
        if (b.owner.name == "enemy"):
          a.owner.destroy()
          b.owner.destroy()
          inc getComp[PlayerController](a.owner.parent.elems["player"]).score
          let score = getComp[PlayerController](a.owner.parent.elems["player"]).score
          getComp[VecText](a.owner.parent.elems["score"]).text = $score & " " & pluralize(score, "POINT ", "POINTS")
      )
    ,
    proc (owner: Elem) =
      on(getComp[TimestepMgr](univ).evTick, proc (univ: Elem, dt: float) =
        for bullet in mitems[Bullet](univ):
          bullet.owner.pos += bullet.velocity
          bullet.owner.rot -= 0.1
          if bullet.owner.pos.x > 8:
            bullet.owner.destroy()
      )
  )

proc regPlayerController*(univ: Elem) =
  register[PlayerController](
    univ,
    proc (owner: Elem): PlayerController =
      result = PlayerController(
        font: vecFont("sys"),
        score: 0
      )
      on(getComp[CircleCollider](owner).evCollision, proc (a, b: ptr Collider) =
        b.owner.destroy()
      )
    ,
    proc (owner: Elem) =
      on(getComp[TimestepMgr](univ).evTick, proc (univ: Elem, dt: float) =
        for player in mitems[PlayerController](univ):
          let inputMgr = getComp[InputMgr[Input]](player.owner.univ)
          let owner = player.owner
          let speed = 0.1
          let cam = getUp[Renderer](player.owner).camera
          #cam.owner.rot = sin(getTicks().float / 800.0) * DEG15 * 0.5
          #cam.size = 10 + sin(getTicks().float / 1000.0) * 2
          #owner.rot = sin(getTicks().float / 800.0) * DEG15
          if inputMgr.getInput(Input.up) == InputState.down:
            owner.pos.y = min(owner.pos.y + speed, 3.5)
            ease(owner.rot, DEG30)
          else:
            if inputMgr.getInput(Input.down) == InputState.down:
              owner.pos.y = max(owner.pos.y - speed, -3.5)
              ease(owner.rot, -DEG30)
            else:
              ease(owner.rot, 0)
          if inputMgr.getInput(Input.action) == InputState.pressed:
            var bullet = owner.parent.add("bullet")
            attach[VecText](bullet).initialize("O")
            bullet.pos = owner.pos + vector2d(1.5, 0)
            bullet.scale = vector2d(0.5, 0.5)
            attach[CircleCollider](bullet)
            attach[Bullet](bullet)
      )
      on(getComp[Renderer](univ).evDraw, proc (univ: Elem, ren: ptr Renderer) =
        for comp in mitems[PlayerController](univ):
          ren.drawString(comp.owner.getTransform, "@", comp.font, color(255, 255, 255, 255), vector2d(1, 1), vector2d(0.2, 0.2), TextAlign.center, 0)
      )
  )

# convert input scancodes into an Input
proc toInput*(key: Scancode): Input =
  case key
  of SDL_SCANCODE_UP: Input.up
  of SDL_SCANCODE_DOWN: Input.down
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_ESCAPE: Input.quit
  of SDL_SCANCODE_SPACE: Input.action
  else: Input.none

# tests
when isMainModule:
  var app: Elem
  initUniv(app, "nch test app")
  var world = app.add("world")

  regTimestepMgr(app)
  attach[TimestepMgr](app)

  regInputMgr[Input](app)
  regRenderer(app)

  attach[Renderer](app).initialize(320, 240)
  attach[InputMgr[Input]](app).initialize(toInput)

  regBullet(app)
  regPlayerController(app)

  regVecText(app)
  regCollisionRealm(app)

  attach[CollisionRealm](world)

  var cam = app.add("mainCam")
  attach[Camera](cam).initialize(10)
  cam.pos = vector2d(0, 0)

  var p1 = world.add("player")
  attach[CircleCollider](p1)
  attach[PlayerController](p1)
  p1.pos = vector2d(-5, 0)

  var obst = world.add("enemy")
  attach[CircleCollider](obst)
  attach[VecText](obst).initialize("#")
  obst.pos = vector2d(5, 3)

  obst = world.add("enemy")
  attach[CircleCollider](obst)
  attach[VecText](obst).initialize("#")
  obst.pos = vector2d(5, 0)

  obst = world.add("enemy")
  attach[CircleCollider](obst)
  attach[VecText](obst).initialize("#")
  obst.pos = vector2d(5, -3)

  var score = world.add("score")
  attach[VecText](score).initialize("0 POINTS", color(255, 255, 255, 255), TextAlign.center, vector2d(0.6, 0.4), vector2d(0.2, 0.2))
  score.pos = vector2d(0, 4.5)

  var url = world.add("url")
  attach[VecText](url).initialize("https://github.com/rezich/nch", color(127, 127, 127, 255), TextAlign.center, vector2d(0.35, 0.4), vector2d(0.1, 0.2))
  url.pos = vector2d(0, -4.5)

  getComp[TimestepMgr](app).initialize()
