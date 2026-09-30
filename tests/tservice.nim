# Adapted from json-server src/service.test.ts.

import harness
import ../src/jsonserver / [jsonvalue, lowdb, service, parsewhere]

let adapter = newMemory()
let db = newLow(adapter, j"{posts: [], comments: [], object: {}}")
let svc = newService(db)

const
  POSTS = "posts"
  COMMENTS = "comments"
  OBJECT = "object"
  UNKNOWN_RESOURCE = "xxx"
  UNKNOWN_ID = "xxx"

let post1 = j"{id: '1', title: 'a', views: 100, published: true, author: {name: 'foo'}, tags: ['foo', 'bar']}"
let post2 = j"{id: '2', title: 'b', views: 200, published: false, author: {name: 'bar'}, tags: ['bar']}"
let post3 = j"{id: '3', title: 'c', views: 300, published: false, author: {name: 'baz'}, tags: ['foo']}"
let comment1 = j"{id: '1', title: 'a', postId: '1'}"
let obj = j"{f1: 'foo'}"

proc beforeEach() =
  let d = newJObject()
  d["posts"] = newJArray(@[post1, post2, post3])
  d["comments"] = newJArray(@[comment1])
  d["object"] = obj
  db.data = copy(d)       # structuredClone

proc with(a: JsonValue; key: string; v: JsonValue): JsonValue =
  ## `{ ...a, [key]: v }`
  result = copy(a)
  result[key] = v

proc opts(where: JsonValue): FindOpts =
  FindOpts(where: where, sort: "", page: 0, hasPage: false, perPage: 0,
           hasPerPage: false, embed: @[])

test "findById":
  beforeEach()
  checkJson svc.findById(POSTS, "1"), db.data[POSTS][0]
  checkJson svc.findById(POSTS, UNKNOWN_ID), nil
  checkJson svc.findById(POSTS, "1", @["comments"]),
    with(post1, "comments", newJArray(@[comment1]))
  checkJson svc.findById(COMMENTS, "1", @["post"]), with(comment1, "post", post1)
  checkJson svc.findById(UNKNOWN_RESOURCE, "1"), nil

block find:
  let whereFromPayload = j"""{"author":{"name":{"eq":"bar"}}}"""
  test "find {where: {title: {eq: 'b'}}}":
    beforeEach()
    checkJson svc.find(POSTS, opts(j"{title: {eq: 'b'}}")), newJArray(@[post2])
  test "find {where: <from payload>}":
    beforeEach()
    checkJson svc.find(POSTS, opts(whereFromPayload)), newJArray(@[post2])
  test "find {where: {}, sort: '-views'}":
    beforeEach()
    var o = opts(newJObject())
    o.sort = "-views"
    checkJson svc.find(POSTS, o), newJArray(@[post3, post2, post1])
  test "find {where: {}, page: 2, perPage: 2}":
    beforeEach()
    var o = opts(newJObject())
    o.page = 2
    o.hasPage = true
    o.perPage = 2
    o.hasPerPage = true
    let expected = j"{first: 1, prev: 1, next: null, last: 2, pages: 2, items: 3}"
    expected["data"] = newJArray(@[post3])
    checkJson svc.find(POSTS, o), expected

test "create":
  beforeEach()
  let post = j"{title: 'new post'}"
  var res = svc.create(POSTS, post)
  check res["title"] == "new post"
  let id = res["id"]
  check id.isString, "id should be a string"

  res = svc.create(POSTS, with(post, "id", newJString("foo")))
  check not (res["id"] == "foo"),
    "user should not be able to set id"

  check svc.create(UNKNOWN_RESOURCE, post) == nil

test "update":
  beforeEach()
  let o = j"{f1: 'bar'}"
  let res = svc.update(OBJECT, o)
  check strictEq(res, o)          # assert.equal: the very same object

  check svc.update(UNKNOWN_RESOURCE, o) == nil, "should ignore unknown resources"
  check svc.update(POSTS, newJObject()) == nil, "should ignore arrays"

test "patch":
  beforeEach()
  let o = j"{f2: 'bar'}"
  let res = svc.patch(OBJECT, o)
  checkJson res, j"{f1: 'foo', f2: 'bar'}"

  check svc.patch(UNKNOWN_RESOURCE, o) == nil, "should ignore unknown resources"
  check svc.patch(POSTS, newJObject()) == nil, "should ignore arrays"

test "updateById":
  beforeEach()
  let post = j"{id: 'xxx', title: 'updated post'}"
  let res = svc.updateById(POSTS, "1", post)
  check res["id"] == "1", "id should not change"
  check res["title"] == "updated post"

  check svc.updateById(UNKNOWN_RESOURCE, "1", post) == nil
  check svc.updateById(POSTS, UNKNOWN_ID, post) == nil

test "patchById":
  beforeEach()
  let post = j"{id: 'xxx', title: 'updated post'}"
  let res = svc.patchById(POSTS, "1", post)
  check res != nil
  check res["id"] == "1"
  check res["title"] == "updated post"

  check svc.patchById(UNKNOWN_RESOURCE, "1", post) == nil
  check svc.patchById(POSTS, UNKNOWN_ID, post) == nil

test "destroy: nullifies foreign keys":
  beforeEach()
  let prevLength = db.data[POSTS].len
  discard svc.destroyById(POSTS, "1")
  check db.data[POSTS].len == prevLength - 1
  checkJson db.data[COMMENTS], newJArray(@[with(comment1, "postId", newJNull())])

test "destroy: deletes dependent resources":
  beforeEach()
  let prevLength = db.data[POSTS].len
  discard svc.destroyById(POSTS, "1", @[COMMENTS])
  check db.data[POSTS].len == prevLength - 1
  check db.data[COMMENTS].len == 0

test "destroy: ignores unknown resources":
  beforeEach()
  check svc.destroyById(UNKNOWN_RESOURCE, "1") == nil
  check svc.destroyById(POSTS, UNKNOWN_ID) == nil

finish()
