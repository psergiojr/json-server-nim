# Port of json-server src/service.ts.

import jsonvalue, lowdb, inflection, matcheswhere, paginate, sorton, randomid
import std / strutils

type
  Service* = ref object
    db*: Low

  FindOpts* = object
    where*: JsonValue
    sort*: string              ## "" when absent
    page*: int
    hasPage*: bool
    perPage*: int
    hasPerPage*: bool
    embed*: seq[string]

proc newService*(db: Low): Service = Service(db: db)

proc get(s: Service; name: string): Maybe = s.db.data[name]

proc has*(s: Service; name: string): bool = s.db.data.hasKey(name)

proc embed(db: Low; name: string; item: JsonValue; related: string): JsonValue =
  if singularize(related) == related:
    let relatedData = db.data[pluralize(related)]
    # Upstream casts to Item[] unchecked; a non-array here is a TypeError
    # there. Treated as "nothing to embed".
    if not relatedData.isArray: return item
    let foreignKey = related & "Id"
    var found: Maybe = nil
    for r in relatedData:
      if strictEq(r["id"], item[foreignKey]):
        found = r
        break
    result = spread(item, nil)
    # `{...item, [related]: undefined}` serializes without the key.
    if found != nil: result[related] = found
    return
  let relatedData = db.data[related]
  if not relatedData.isArray: return item
  let foreignKey = singularize(name) & "Id"
  let children = newJArray()
  for r in relatedData:
    if strictEq(r[foreignKey], item["id"]): children.add r
  result = spread(item, nil)
  result[related] = children

proc nullifyForeignKey(db: Low; name, id: string) =
  let foreignKey = singularize(name) & "Id"
  for key, items in db.data:
    if key == name: continue
    for item in items:
      if item.isObject:
        let fk = item[foreignKey]
        if fk.isString and fk.str == id:
          item[foreignKey] = newJNull()

proc deleteDependents(db: Low; name: string; dependents: seq[string]) =
  let foreignKey = singularize(name) & "Id"
  for key, items in db.data:
    if key == name or key notin dependents: continue
    if items.isArray:
      var kept: seq[JsonValue] = @[]
      for item in items:
        let fk = item[foreignKey]
        if not fk.isNull: kept.add item
      items.elems = kept

proc findIndexById(items: JsonValue; id: string): int =
  for i, item in items.elems:
    let v = item["id"]
    if v.isString and v.str == id: return i
  result = -1

proc findById*(s: Service; name, id: string; embed: seq[string] = @[]): Maybe =
  let value = s.get(name)
  if not value.isArray: return nil
  let i = findIndexById(value, id)
  if i < 0: return nil
  var item = value.elems[i]
  for related in embed:
    item = embed(s.db, name, item, related)
  result = item

proc find*(s: Service; name: string; opts: FindOpts): Maybe =
  ## The collection filtered, sorted and maybe paginated; a non-array resource
  ## as it is; undefined for an unknown one.
  let items = s.get(name)
  if not items.isArray: return items

  var results = items.elems
  for related in opts.embed:
    var embedded: seq[JsonValue] = @[]
    for item in results: embedded.add embed(s.db, name, item, related)
    results = embedded

  var filtered: seq[JsonValue] = @[]
  for item in results:
    if matchesWhere(item, opts.where): filtered.add item
  results = filtered

  if opts.sort.len > 0:
    results = sortOn(results, opts.sort.split(','))

  if opts.hasPage:
    return paginate(results, opts.page, if opts.hasPerPage: opts.perPage else: 10)
  result = newJArray(results)

proc create*(s: Service; name: string; data: JsonValue): Maybe =
  let items = s.get(name)
  if not items.isArray: return nil
  let id = newJObject()
  id["id"] = newJString(randomId())
  let item = spread(data, id)       # a client-sent id is overwritten in place
  items.add item
  s.db.write()
  result = item

proc updateOrPatch(s: Service; name: string; body: JsonValue; isPatch: bool): Maybe =
  let item = s.get(name)
  if item == nil or item.kind == JArray: return nil
  let next = if isPatch: spread(item, body) else: body
  s.db.data[name] = next
  s.db.write()
  result = next

proc updateOrPatchById(s: Service; name, id: string; body: JsonValue;
                       isPatch: bool): Maybe =
  let items = s.get(name)
  if not items.isArray: return nil
  let i = findIndexById(items, id)
  if i < 0: return nil
  let idObj = newJObject()
  idObj["id"] = newJString(id)
  let next = if isPatch: spread(spread(items.elems[i], body), idObj)
             else: spread(body, idObj)
  items.elems[i] = next
  s.db.write()
  result = next

proc update*(s: Service; name: string; body: JsonValue): Maybe =
  updateOrPatch(s, name, body, false)

proc patch*(s: Service; name: string; body: JsonValue): Maybe =
  updateOrPatch(s, name, body, true)

proc updateById*(s: Service; name, id: string; body: JsonValue): Maybe =
  updateOrPatchById(s, name, id, body, false)

proc patchById*(s: Service; name, id: string; body: JsonValue): Maybe =
  updateOrPatchById(s, name, id, body, true)

proc destroyById*(s: Service; name, id: string;
                  dependents: seq[string] = @[]): Maybe =
  let items = s.get(name)
  if not items.isArray: return nil
  let i = findIndexById(items, id)
  if i < 0: return nil
  let item = items.elems[i]
  items.elems.delete(i)
  nullifyForeignKey(s.db, name, id)
  deleteDependents(s.db, name, dependents)
  s.db.write()
  result = item
