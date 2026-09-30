# Adapted from json-server src/adapters/normalized-adapter.test.ts. The stub
# adapter is `Memory`, which clones on read and write like the stub does.

import harness
import ../src/jsonserver / [jsonvalue, lowdb]

test "read removes $schema and normalizes ids":
  let stub = newMemory()
  var err = ""
  stub.write(j"{$schema: './custom/schema.json', posts: [{id: 1}, {title: 'missing id'}], profile: {name: 'x'}}", err)

  let normalized = newNormalizedAdapter(stub).read(err)
  check normalized != nil
  check normalized["$schema"] == nil
  checkJson normalized["profile"], j"{name: 'x'}"

  let posts = normalized["posts"]
  check posts.isArray
  check posts[0]["id"] == "1"
  let id1 = posts[1]["id"]
  check id1.isString
  check not (id1 == "")

test "write always overwrites $schema":
  let stub = newMemory()
  var err = ""
  newNormalizedAdapter(stub).write(j"{posts: [{id: '1'}]}", err)
  let data = stub.stored
  check data != nil
  check data["$schema"] == DefaultSchemaPath

finish()
