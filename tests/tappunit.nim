# The app as a function, below the socket: behaviors of src/app.ts that the
# upstream HTTP table (ported in tapp.nim) does not pin, each checked against
# what the TypeScript does.

import std / strutils
import harness
import ../src/jsonserver / [jsonvalue, lowdb, app]

let db = newLow(newMemory(), newJObject())
let a = newApp(db)

proc reset() =
  db.data = j"""{
    posts: [
      {id: '1', title: 'foo', views: 100, author: {name: 'a'}},
      {id: '2', title: 'bar', views: 200, author: {name: 'b'}},
      {id: '3', title: 'baz', views: 300, author: {name: 'c'}}],
    comments: [{id: '1', postId: '1'}, {id: '2', postId: '2'}],
    object: {f1: 'foo'}}"""

proc req(meth, path: string; query = ""; body = "";
         headers: seq[(string, string)] = @[]): Response =
  a.handle(Request(meth: meth, path: path, query: query, headers: headers,
                   body: body, bodyTooLarge: false))

proc data(r: Response): Maybe =
  var v: Maybe = nil
  var err = ""
  discard tryParseJson(r.body, v, err)
  result = v

proc ids(r: Response): string =
  result = ""
  for item in r.data: result.add item["id"].getStr

test "index lists resources":
  reset()
  let r = req("GET", "/")
  check r.status == 200
  check r.body.contains("<span>/posts</span>") and r.body.contains("3 items")
  check r.body.contains("object")

test "static file wins over CORS, which it does not get":
  let r = req("GET", "/test.html")
  check r.status == 200
  check r.header("Access-Control-Allow-Origin") == ""
  check r.header("Content-Type") == "text/html;charset=utf-8"
  check r.header("Cache-Control") == "no-store"
  check r.header("Last-Modified").endsWith(" GMT")

test "API responses carry CORS headers":
  reset()
  let r = req("GET", "/posts")
  check r.header("Access-Control-Allow-Origin") == "*"
  check r.header("Access-Control-Allow-Headers") == "content-type"

test "preflight echoes the requested headers":
  let r = req("OPTIONS", "/anything/at/all", headers = @[
    ("access-control-request-headers", "X-Token, content-type")])
  check r.status == 204
  check r.header("Access-Control-Allow-Headers") == "X-Token,content-type"
  check r.header("Access-Control-Allow-Methods") == "GET, HEAD, PUT, PATCH, POST, DELETE"

test "operators in the query string":
  reset()
  check req("GET", "/posts", "views:gt=100").ids == "23"
  check req("GET", "/posts", "views_lte=200&title:ne=foo").ids == "2"
  check req("GET", "/posts", "title:in=foo,baz").ids == "13"
  check req("GET", "/posts", "title:startsWith=BA").ids == "23"
  check req("GET", "/posts", "author.name=c").ids == "3"
  # Upstream quirk, kept: `2` is coerced to a number and ids are strings, so
  # `===` never holds. `?id=2` matches nothing in json-server v1 either.
  check req("GET", "/posts", "id=2").ids == ""

test "unknown underscore keys are filters that match nothing":
  # `_limit` is not reserved in v1: it becomes `{_limit: {eq: 1}}`.
  reset()
  check req("GET", "/posts", "_limit=1").ids == ""

test "_where replaces the query-string filters; invalid JSON is ignored":
  reset()
  check req("GET", "/posts", "_where=%7B%22or%22%3A%5B%7B%22views%22%3A%7B%22lt%22%3A150%7D%7D%2C%7B%22title%22%3A%7B%22eq%22%3A%22baz%22%7D%7D%5D%7D").ids == "13"
  check req("GET", "/posts", "title=foo&_where=%7Bnope").ids == "1"

test "_sort, several keys and descending":
  reset()
  check req("GET", "/posts", "_sort=-views").ids == "321"
  check req("GET", "/posts", "_sort=title").ids == "231"

test "_page and _per_page":
  reset()
  let page = req("GET", "/posts", "_page=2&_per_page=2").data
  checkJson page["data"], j"[{id: '3', title: 'baz', views: 300, author: {name: 'c'}}]"
  let next = page["next"]
  check page["prev"].getNum == 1.0 and next.isNull
  # _page alone: 10 per page; parseInt leniency: "1abc" is 1
  check req("GET", "/posts", "_page=1abc").data["pages"].getNum == 1.0
  # not a number: no pagination at all
  let plain = req("GET", "/posts", "_page=x").data
  check plain.isArray

test "_embed on a list and on one item, repeated":
  reset()
  let one = req("GET", "/posts/1", "_embed=comments").data
  checkJson one["comments"], j"[{id: '1', postId: '1'}]"
  let c = req("GET", "/comments/2", "_embed=post").data
  check c["post"]["title"] == "bar"
  let list = req("GET", "/posts", "_embed=comments&_embed=nothing").data
  check list[1]["comments"].len == 1
  check list[0]["nothing"] == nil

test "POST ignores a client id and answers 201":
  reset()
  let r = req("POST", "/posts", body = """{"id": "x", "title": "t"}""")
  check r.status == 201
  check not (r.data["id"] == "x")
  check db.data["posts"].len == 4

test "POST with no body creates an item with only an id":
  reset()
  let r = req("POST", "/posts")
  check r.status == 201 and r.data.len == 1

test "PUT replaces, PATCH merges, the id stays":
  reset()
  checkJson req("PUT", "/posts/1", body = """{"id": "9", "x": 1}""").data, j"{x: 1, id: '1'}"
  checkJson req("PATCH", "/posts/2", body = """{"views": 0}""").data,
    j"{id: '2', title: 'bar', views: 0, author: {name: 'b'}}"
  checkJson req("PATCH", "/object", body = """{"f2": 2}""").data, j"{f1: 'foo', f2: 2}"

test "DELETE nullifies foreign keys, or deletes dependents":
  reset()
  check req("DELETE", "/posts/1").status == 200
  checkJson db.data["comments"][0], j"{id: '1', postId: null}"
  reset()
  check req("DELETE", "/posts/2", "_dependent=comments").status == 200
  checkJson db.data["comments"], j"[{id: '1', postId: '1'}]"

test "malformed JSON body is tinyhttp's 500, as plain text":
  reset()
  let r = req("POST", "/posts", body = "{nope")
  check r.status == 500
  check r.header("Content-Type") == "text/plain; charset=utf-8"
  check r.header("X-Content-Type-Options") == "nosniff"

test "no route: plain 404; under a name: JSON 404":
  let r = req("POST", "/")
  check r.status == 404 and r.body == "Not Found"
  let r2 = req("GET", "/posts/1/comments")
  check r2.status == 404 and r2.header("Content-Type") == "application/json"

test "responses are JSON.stringify(data, null, 2)":
  reset()
  check req("GET", "/object").body == "{\n  \"f1\": \"foo\"\n}"

finish()
