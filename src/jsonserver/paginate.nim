# Port of json-server src/paginate.ts.

import jsonvalue

proc paginate*(items: seq[JsonValue]; page, perPage: int): JsonValue =
  let totalItems = items.len
  let safePerPage = if perPage > 0: perPage else: 1
  let pages = max(1, (totalItems + safePerPage - 1) div safePerPage)
  let currentPage = max(1, min(page, pages))

  let start = (currentPage - 1) * safePerPage
  let stop = min(start + safePerPage, totalItems)
  var data = newJArray()
  for i in start ..< stop: data.add items[i]

  result = newJObject()
  result["first"] = newJNumber(1)
  result["prev"] = if currentPage > 1: newJNumber(currentPage - 1) else: newJNull()
  result["next"] = if currentPage < pages: newJNumber(currentPage + 1) else: newJNull()
  result["last"] = newJNumber(pages)
  result["pages"] = newJNumber(pages)
  result["items"] = newJNumber(totalItems)
  result["data"] = data
