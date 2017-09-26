## SlotMap
# high-performance associative data structure
# based on:
#  http://seanmiddleditch.com/data-structures-for-game-developers-the-slot-map/
#  http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0661r0.pdf
#  https://www.youtube.com/watch?v=SHaAR7XPtNU

import typetraits

type
  Slot*[T] = object
    slotMap: SlotMap[T]
    index: tuple[chunk: int, chunkIndex: int]
    gen: int

  SlotMap*[T] = ref object
    perChunk: int
    chunks: seq[ref seq[T]]
    gens: seq[int]
    vacancies: seq[int]
    active: seq[bool]
    next: int

proc addChunk[T](slotMap: SlotMap[T]) =
  if slotMap.chunks == nil:
    slotMap.chunks = @[]
  var chunk = new(seq[T])
  chunk[] = newSeq[T](slotMap.perChunk)
  slotMap.chunks.add(chunk)
  slotMap.active.setLen(slotMap.active.len + slotMap.perChunk)
  slotMap.gens.setLen(slotMap.gens.len + slotMap.perChunk)

proc initSlotMap[T](slotMap: SlotMap[T]) =
  if slotMap.chunks == nil:
    addChunk(slotMap)

proc newSlotMap*[T](perChunk: int = 128, allocFirstPage: bool = true): SlotMap[T] =
  new(result)
  result.perChunk = perChunk
  result.next = 0
  result.active = @[]
  result.vacancies = @[]
  result.gens = @[]
  if allocFirstPage:
    addChunk(result)
  else:
    result.chunks = @[]

proc internalIndex[T](slot: Slot[T]): int =
  slot.index.chunk * slot.slotMap.perChunk + slot.index.chunkIndex

proc add*[T](slotMap: SlotMap[T], item: T): Slot[T] {.discardable.} =
  initSlotMap(slotMap)
  var index = slotMap.next
  if slotMap.vacancies.len > 0:
    index = slotMap.vacancies.pop()
  else:
    inc slotMap.next

  var chunk = index div slotMap.perChunk
  var chunkIndex = index mod slotMap.perChunk

  if chunk > slotMap.chunks.high:
    slotMap.addChunk()
  
  index = chunk * slotMap.perChunk + chunkIndex
  slotMap.chunks[chunk][chunkIndex] = item
  slotMap.active[index] = true
  inc slotMap.gens[index]
  Slot[T](
    slotMap: slotMap,
    index: (chunk, chunkIndex),
    gen: slotMap.gens[index]
  )

proc remove*[T](slotMap: SlotMap[T], slot: Slot[T]) =
  if slotMap.chunks == nil:
    raise newException(AccessViolationError, "SlotMap[" & typedesc[T].name & "] not initialized")
  if slot.gen != slot.slotMap.gens[slot.internalIndex]:
    raise newException(IndexError, "Slot[" & typedesc[T].name & "] outdated, points to dead object")
  slotMap.active[slot.internalIndex] = false
  slotMap.vacancies.add(slot.internalIndex)

proc remove*[T](slot: Slot[T]) = # considering renaming this to "destroy" or something similar
  slot.slotMap.remove(slot)

proc clear*[T](slotMap: SlotMap[T], allocFirstPage: bool = true) =
  slotMap.active = @[]
  slotMap.vacancies = @[]
  slotMap.gens = @[]
  slotMap.next = 0
  if allocFirstPage:
    addChunk(slotMap)
  else:
    slotMap.chunks = @[]

iterator mitems*[T](slotMap: SlotMap[T]): var T =
  if slotMap.chunks == nil:
    raise newException(AccessViolationError, "SlotMap[" & typedesc[T].name & "] not initialized")
  if slotMap.next != 0:
    for i in 0..slotMap.chunks.high:
      for j in 0..slotMap.perChunk - 1:
        if slotMap.active[i * slotMap.perChunk + j]:
          yield slotMap.chunks[i][j mod slotMap.perChunk]

proc `[]`[T](slot: Slot[T]): var T =
  if slot.gen != slot.slotMap.gens[slot.internalIndex]:
    raise newException(IndexError, "Slot[" & typedesc[T].name & "] outdated, points to dead object")
  slot.slotMap.chunks[slot.index.chunk][slot.index.chunkIndex]


## tests
when isMainModule:
  type
    Foo = object
      bar: int


  var sm = newSlotMap[Foo](8)

  var obj = sm.add Foo(bar: 42) # returns a Slot[Foo]

  echo obj[].bar # use [] (dereference) to get the object being pointed at

  obj.remove()
  # sm.remove(obj) # alternative

  for i in 0..32:
    sm.add Foo(bar: i)
  
  sm.clear()

  #echo obj[].bar # this should fail because we removed obj earlier

  for foo in sm.mitems: # use mitems to iterate through all active instances in the SlotMap
    echo foo.bar
