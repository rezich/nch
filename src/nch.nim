# nch #

import
  tables,
  typetraits,
  sequtils,
  future

import sdl2, sdl2/gfx, sdl2.image, sdl2.ttf, basic2d, random, math

{.experimental.}


### SYSTEM ###

proc box[T](x: T): ref T =
  new(result); result[] = x

type
  Node* = object of RootObj
    name*: string
    internalUniv*: ref Univ
    relatives: OrderedTableRef[string, ref Node]
  
  CompAllocBase = ref object of RootObj

  CompAlloc[T] = ref object of CompAllocBase
    comps: seq[T]
    newProc: proc (owner: Elem): T

  Elem* = ref object of Node

  Univ* = ref object of Elem
    compAllocs: OrderedTableRef[string, CompAllocBase]

  Comp* = object of Node

  Nch = object of RootObj
    root*: ptr Univ

var nch* = Nch(root: nil)
    
proc univ*(node: Node): ref Univ =
  return node.internalUniv

proc univ*(node: ref Node): ref Univ =
  if node.internalUniv == nil:
    return cast[ref Univ](box(node))
  return node.internalUniv

proc initElem[T: Elem](elem: var T, parent: Elem = nil) =
  if parent != nil:
    elem.internalUniv = parent.univ
  elem.relatives = newOrderedTable[string, ref Node]()
  elem.relatives[".."] = cast[ref Node](parent)

proc initUniv*(univ: var Univ, name: string) =
  univ = Univ(
    name: name,
    compAllocs: newOrderedTable[string, CompAllocBase]()
  )
  initElem(univ)
  univ.internalUniv = nil
  if nch.root == nil:
    nch.root = addr univ

proc destroy[T: Univ](node: var T) =
  if nch.root == addr node:
    nch.root = nil
    node = nil # ???
  
proc add*[T: Elem](parent: var T, name: string): Elem {.discardable.} =
  new(result)
  result.name = name
  initElem(result, cast[Elem](parent))
  parent.relatives[name] = result
  

proc initComp*[T: Comp](comp: var T, owner: Elem) =
  comp.name = typedesc[T].name
  comp.relatives = newOrderedTable[string, ref Node]()
  comp.internalUniv = owner.univ

proc newCompAlloc[T: Comp](newProc: proc (owner: Elem): T) : CompAlloc[T] =
  result = CompAlloc[T](
    comps: newSeq[T](),
    newProc: newProc
  )

proc register[T](univ: Univ, newProc: proc (owner: Elem): T) =
  let name = typedesc[T].name
  if name in univ.compAllocs:
    echo "EXCEPTION: " & name & " already registered in this Univ"
    return
  univ.compAllocs[name] = newCompAlloc[T](newProc)


proc allocComp[T: Comp](univ: var Univ): T =
  let name = typedesc[T].name
  if name notin univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return
  # TODO: use empty spaces if available
  let compAlloc = cast[CompAlloc[T]](univ.compAllocs[name])
  compAlloc.comps.add(compAlloc.newProc(univ))
  return compAlloc.comps[compAlloc.comps.high]

proc attach*[T: Comp](parent: ref Node): T {.discardable.} =
  result = allocComp[T](parent.univ)
  #parent.relatives[">" & result.name] = cast[ref Node](result)
  parent.relatives[">" & result.name] = box(result)

proc getComp[T: Comp](node: Node): ref T =
  if typedesc[T].name notin node.univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return nil
  if ">" & typedesc[T].name notin node.relatives:
    echo "EXCEPTION: Comp not found in Node"
    return nil
  return nil

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
  


### TESTS ###

when isMainModule:
  var app : Univ
  initUniv(app, "nch test app")

  var world = app.add("world")
  assert(world.relatives[".."].name == "nch test app")
  assert(app.relatives["world"].name == "world")
  
  assert(addr(app) == nch.root)

  register[TestComp](app, newTestComp)
  register[InputMgr[Input]](app, newInputMgr[Input])
  register[Renderer](app, newRenderer)
  register[TimestepMgr](app, newTimestepMgr)

  attach[Renderer](app)
  attach[InputMgr[Input]](app)
  attach[TestComp](world)

  assert(world.relatives[">TestComp"] != nil)
  assert(app.relatives[">InputMgr[nch.Input]"] != nil)

  assert(cast[ref InputMgr[Input]](app.relatives[">InputMgr[nch.Input]"]).getInput(Input.action) == InputState.up)

  cast[ref Renderer](app.relatives[">Renderer"]).initialize()

  var name = typedesc[TestComp].name
  var comps = addr cast[CompAlloc[TestComp]](app.compAllocs[name]).comps
  assert(comps.len == 1)
  assert(comps[0].things == 42)

  #echo cast[CompAlloc[TestComp]](app.univ().compAllocs["TestComp"]).comps.len

  app.destroy()
  
  assert(app == nil)