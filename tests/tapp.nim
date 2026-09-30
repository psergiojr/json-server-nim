# Adapted from json-server src/app.test.ts: the same route table, over real
# HTTP against a server on an ephemeral port.

import std / [syncio, dirs, paths, strutils, uri]
import harness, httpclient
import ../src/jsonserver / [jsonvalue, lowdb, app, server, randomid]

# Custom static dir with an html file
let tmpDir = "/tmp/json-server-nim-" & randomId().replace("-", "_")
try:
  createDir(path(tmpDir))
  writeFile(tmpDir & "/file.html", "utf-8")
except ErrorCode as e:
  echo "cannot create ", tmpDir, ": ", e
  quit(2)
const file = "file.html"

proc freshData(): JsonValue =
  j"{posts: [{id: '1', title: 'foo'}], comments: [{id: '1', postId: '1'}], object: {f1: 'foo'}}"

let db = newLow(newMemory(), newJObject())
db.data = freshData()
let port = startServer(newApp(db, AppOptions(staticDirs: @[tmpDir])), 0)
if port <= 0:
  echo "server did not start"
  quit(2)
setPort(port)

const
  POSTS = "/posts"
  POSTS_WITH_COMMENTS = "/posts?_embed=comments"
  POST_1 = "/posts/1"
  POST_NOT_FOUND = "/posts/-1"
  POST_WITH_COMMENTS = "/posts/1?_embed=comments"
  COMMENTS = "/comments"
  POST_COMMENTS = "/comments?postId=1"
  NOT_FOUND = "/not-found"
  OBJECT = "/object"
  OBJECT_1 = "/object/1"

let arr = [
  # Static
  ("GET", "/", 200),
  ("GET", "/test.html", 200),
  ("GET", "/" & file, 200),

  # CORS
  ("OPTIONS", POSTS, 204),

  # API
  ("GET", POSTS, 200),
  ("GET", POSTS_WITH_COMMENTS, 200),
  ("GET", POST_1, 200),
  ("GET", POST_NOT_FOUND, 404),
  ("GET", POST_WITH_COMMENTS, 200),
  ("GET", COMMENTS, 200),
  ("GET", POST_COMMENTS, 200),
  ("GET", OBJECT, 200),
  ("GET", OBJECT_1, 404),
  ("GET", NOT_FOUND, 404),

  ("POST", POSTS, 201),
  ("POST", POST_1, 404),
  ("POST", POST_NOT_FOUND, 404),
  ("POST", OBJECT, 404),
  ("POST", OBJECT_1, 404),
  ("POST", NOT_FOUND, 404),

  ("PUT", POSTS, 404),
  ("PUT", POST_1, 200),
  ("PUT", OBJECT, 200),
  ("PUT", OBJECT_1, 404),
  ("PUT", POST_NOT_FOUND, 404),
  ("PUT", NOT_FOUND, 404),

  ("PATCH", POSTS, 404),
  ("PATCH", POST_1, 200),
  ("PATCH", OBJECT, 200),
  ("PATCH", OBJECT_1, 404),
  ("PATCH", POST_NOT_FOUND, 404),
  ("PATCH", NOT_FOUND, 404),

  ("DELETE", POSTS, 404),
  ("DELETE", POST_1, 200),
  ("DELETE", OBJECT, 404),
  ("DELETE", OBJECT_1, 404),
  ("DELETE", POST_NOT_FOUND, 404),
  ("DELETE", NOT_FOUND, 404),
]

proc parsed(body: string): Maybe =
  var v: Maybe = nil
  var err = ""
  discard tryParseJson(body, v, err)
  result = v

for (meth, url, statusCode) in arr:
  test "createApp " & meth & " " & url:
    let response = fetch(meth, url)
    check response.status == statusCode,
      $response.status & " !== " & $statusCode & " " & meth & " " & url & " failed"
    if statusCode == 404:
      checkJson parsed(response.body), j"{error: 'Not Found'}"

test "GET /posts?_where=... uses JSON query":
  # Reset data since previous tests may have modified it
  db.data = freshData()
  let where = encodeUrl("""{"title":{"eq":"foo"}}""")
  let response = fetch("GET", "/posts?_where=" & where)
  check response.status == 200
  checkJson parsed(response.body), j"[{id: '1', title: 'foo'}]"

test "GET /posts?_where=... overrides query params":
  let where = encodeUrl("""{"title":{"eq":"foo"}}""")
  let response = fetch("GET", "/posts?title:eq=bar&_where=" & where)
  check response.status == 200
  checkJson parsed(response.body), j"[{id: '1', title: 'foo'}]"

test "POST /posts with array body returns 400":
  let response = fetch("POST", "/posts", """[{"title":"foo"}]""", "application/json")
  check response.status == 400
  checkJson parsed(response.body), j"{error: 'Body must be a JSON object'}"

test "PATCH /posts/1 with string body returns 400":
  let response = fetch("PATCH", "/posts/1", "\"hello\"", "application/json")
  check response.status == 400
  checkJson parsed(response.body), j"{error: 'Body must be a JSON object'}"

test "PUT /posts/1 with null body returns 400":
  let response = fetch("PUT", "/posts/1", "null", "application/json")
  check response.status == 400
  checkJson parsed(response.body), j"{error: 'Body must be a JSON object'}"

try:
  removeFile(path(tmpDir & "/file.html"))
  removeDir(path(tmpDir))
except ErrorCode: discard

finish()
