## SlotMap
# high-performance associative data structure
# based on:
#  http://seanmiddleditch.com/data-structures-for-game-developers-the-slot-map/
#  http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0661r0.pdf
#  https://www.youtube.com/watch?v=SHaAR7XPtNU
#
# scroll to the "TESTS" section for documentation

import typetraits

type
  Slot*[T] = object
    slotMap: SlotMap[T]
    index: tuple[chunk: int, chunkIndex: int]
    gen: int

  SlotMap*[T] = ref object
    perChunk: int
    chunks: seq[ref seq[T]]
    slotInfo: seq[tuple[active: bool, gen: int]]
    vacancies: seq[int]
    next: int

proc addChunk[T](slotMap: SlotMap[T]) =
  var chunk = new(seq[T])
  chunk[] = newSeq[T](slotMap.perChunk)
  slotMap.chunks.add(chunk)
  slotMap.slotInfo.setLen(slotMap.slotInfo.len + slotMap.perChunk)

proc initSlotMap*[T](slotMap: SlotMap[T], perChunk: int = 128, addFirstChunk: bool = true) =
  slotMap.chunks = @[]
  slotMap.perChunk = perChunk
  slotMap.next = 0
  slotMap.vacancies = @[]
  slotMap.slotInfo = @[]
  if addFirstChunk:
    addChunk(slotMap)

proc newSlotMap*[T](perChunk: int = 128): SlotMap[T] =
  new(result)
  initSlotMap(result, perChunk)

proc internalIndex[T](slot: Slot[T]): int =
  slot.index.chunk * slot.slotMap.perChunk + slot.index.chunkIndex

proc add*[T](slotMap: SlotMap[T], item: T): Slot[T] =
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
  let gen = slotMap.slotInfo[index].gen + 1
  slotMap.slotInfo[index] = (
    active: true,
    gen: gen
  )
  Slot[T](
    slotMap: slotMap,
    index: (chunk, chunkIndex),
    gen: gen
  )

proc remove*[T](slotMap: SlotMap[T], slot: Slot[T]) =
  if slotMap.chunks == nil:
    raise newException(AccessViolationError, "SlotMap[" & typedesc[T].name & "] not initialized")
  if slot.gen != slot.slotMap.slotInfo[slot.internalIndex].gen or not slot.slotMap.slotInfo[slot.internalIndex].active:
    raise newException(IndexError, "Slot[" & typedesc[T].name & "] outdated, points to dead object")
  slotMap.slotInfo[slot.internalIndex].active = false
  slotMap.vacancies.add(slot.internalIndex)

proc destroy*[T](slot: Slot[T]) =
  slot.slotMap.remove(slot)

proc clear*[T](slotMap: SlotMap[T], addFirstChunk: bool = true) =
  initSlotMap(slotMap, slotMap.perChunk, addFirstChunk)

iterator mitems*[T](slotMap: SlotMap[T]): var T =
  if slotMap.chunks == nil:
    raise newException(AccessViolationError, "SlotMap[" & typedesc[T].name & "] not initialized")
  if slotMap.next != 0:
    for i in 0..slotMap.chunks.high:
      for j in 0..slotMap.perChunk - 1:
        if slotMap.slotInfo[i * slotMap.perChunk + j].active:
          yield slotMap.chunks[i][j mod slotMap.perChunk]

proc `[]`*[T](slot: Slot[T]): var T =
  if not slot.slotMap.slotInfo[slot.internalIndex].active or slot.gen != slot.slotMap.slotInfo[slot.internalIndex].gen:
    raise newException(IndexError, "Slot[" & typedesc[T].name & "] outdated, points to dead object")
  slot.slotMap.chunks[slot.index.chunk][slot.index.chunkIndex]


## TESTS
when isMainModule:
  # sample object type with single value
  type
    Foo = object
      bar: int


  # create a collection of `Foo`, estimated (by us) to contain about eight objects
  let foos = newSlotMap[Foo](8)


  # instantiate a `Foo`, storing it in `foos`, and
  # get back a "slot" (`Slot[Foo]`) that "points to it"
  var obj = foos.add Foo(bar: 42)
  

  # we can use the object that the "slot" "points to"
  # by using the dereference operator
  echo "foobar: " & $obj[].bar


  # destroying the object a "slot" "points to" is easy:
  obj.destroy()
  # this marks the object "being pointed at" as "free",
  # such that it can be reused the next time the
  # container  needs space for a new object


  # alternatively, we could *remove* it from the collection itself:
  var failedToRemoveTwice = false
  try:
    foos.remove(obj)
  except IndexError:
    failedToRemoveTwice = true
  # however, doing so right now throws an exception,
  # because we've already destroyed the object that
  # `obj` "points to"
  assert failedToRemoveTwice


  # now, when we instantiate a new `Foo` in the collection...
  var obj2 = foos.add Foo(bar: 108)
  # ...it will reuse the same memory location as `obj`,
  # since we destroyed it earlier
  assert obj.index == obj2.index
  # despite residing in the same location in memory,
  # the two "slots" are not equal
  assert obj != obj2
  # this is because "slots" also track a "generation index",
  # distinct between re-uses of the memory address in the
  # internal data structure


  # let's add seven more things to the collection
  for i in 1..7:
    discard foos.add Foo(bar: i * i)
  # no problem; these are all allocated properly
  

  # now, let's add one more item to the collection,
  # which will bring the total number of items to nine—
  # one more than the eight we "expected"
  discard foos.add Foo(bar: 999)
  # it didn't crash! instead, it created a new "chunk" of
  # memory, just as big as the first one, and used that
  assert foos.chunks.len == 2

  
  # we can easily iterate through all items in
  # the container, even though they're spread
  # across chunks and some might be invalid
  for foo in foos.mitems:
    echo foo.bar


  # we can empty out the collection, destroying everything within:
  foos.clear()
  

  # of course, if we try to use a "slot" after its
  # collection has been cleared, it won't work
  var failedToRemoveAfterClear = false
  try:
    echo obj[].bar
  except IndexError:
    failedToRemoveAfterClear = true
  assert failedToRemoveAfterClear
  