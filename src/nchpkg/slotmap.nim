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
  if slotMap.chunks == nil:
    slotMap.chunks = @[]
  var chunk = new(seq[T])
  chunk[] = newSeq[T](slotMap.perChunk)
  slotMap.chunks.add(chunk)
  slotMap.slotInfo.setLen(slotMap.slotInfo.len + slotMap.perChunk)

proc initSlotMap[T](slotMap: SlotMap[T]) =
  if slotMap.chunks == nil:
    addChunk(slotMap)

proc newSlotMap*[T](perChunk: int = 128, allocFirstPage: bool = true): SlotMap[T] =
  new(result)
  result.perChunk = perChunk
  result.next = 0
  result.vacancies = @[]
  result.slotInfo = @[]
  if allocFirstPage:
    addChunk(result)
  else:
    result.chunks = @[]

proc internalIndex[T](slot: Slot[T]): int =
  slot.index.chunk * slot.slotMap.perChunk + slot.index.chunkIndex

proc add*[T](slotMap: SlotMap[T], item: T): Slot[T] =
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

proc clear*[T](slotMap: SlotMap[T], allocFirstPage: bool = true) =
  slotMap.vacancies = @[]
  slotMap.slotInfo = @[]
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
        if slotMap.slotInfo[i * slotMap.perChunk + j].active:
          yield slotMap.chunks[i][j mod slotMap.perChunk]

proc `[]`*[T](slot: Slot[T]): var T =
  if slot.slotMap.slotInfo[slot.internalIndex].active || slot.gen != slot.slotMap.slotInfo[slot.internalIndex].gen:
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
  # returns a `Slot[Foo]` that "points to it"
  var obj = foos.add Foo(bar: 42)
  

  # we can use the object that the `Slot[T]` "points to"
  # by using the dereference operator
  echo "foobar: " & $obj[].bar


  # destroying an object using a `Slot[T]` is easy:
  obj.destroy()
  # this marks the object "being pointed at" as "free",
  # such that it can be reused the next time the
  # `SlotMap[T]` needs space for a `T`


  # alternatively, we could *remove* it from the `SlotMap[T]` itself:
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
  # the two `Slot[T]`s are not equal
  assert obj != obj2
  # this is because `Slot[T]` also tracks a "generation index",
  # distinct between re-uses of the memory address in the
  # `Slot[T]`'s `SlotMap[T]`'s internal data structure


  # let's add seven more things to the collection
  for i in 1..7:
    discard foos.add Foo(bar: i * i) # (we `discard` the returned slot here—normally, don't do this)
  # no problem; these are all allocated properly
  

  # now, let's add one more item to the collection,
  # which will bring the total number of items to nine—
  # one more than the eight we "expected"
  discard foos.add Foo(bar: 999)
  # it didn't crash! instead, it created a new "chunk"
  # of memory, just as big as the initial chunk
  # (`8 * sizeof(T)`), and used that.
  assert foos.chunks.len == 2

  
  # we can easily iterate through all items in
  # the container, even though they're spread
  # across chunks and some might be invalid
  for foo in foos.mitems:
    echo foo.bar


  # we can empty out the collection, destroying everything within:
  foos.clear()
  

  # of course, if we try to use a `Slot[T]` "into" a collection
  # after we clear said collection, it won't work:
  var failedToRemoveAfterClear = false
  try:
    echo obj[].bar
  except IndexError:
    failedToRemoveAfterClear = true
  assert failedToRemoveAfterClear
  