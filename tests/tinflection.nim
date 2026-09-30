# Not in upstream (json-server takes these from the `inflection` package).
# Expectations are what inflection 3.0.2 answers.

import harness
import ../src/jsonserver/inflection

const plurals = [
  ("post", "posts"), ("comment", "comments"), ("person", "people"),
  ("man", "men"), ("woman", "women"), ("child", "children"),
  ("category", "categories"), ("query", "queries"), ("day", "days"),
  ("box", "boxes"), ("church", "churches"), ("bus", "buses"),
  ("status", "statuses"), ("knife", "knives"), ("wolf", "wolves"),
  ("mouse", "mice"), ("tooth", "teeth"), ("matrix", "matrices"),
  ("datum", "data"), ("axis", "axes"), ("quiz", "quizzes"),
  ("information", "information"), ("sheep", "sheep"), ("Post", "Posts"),
  ("posts", "posts"), ("people", "people"), ("tomato", "tomatoes")]

const singulars = [
  ("posts", "post"), ("comments", "comment"), ("people", "person"),
  ("men", "man"), ("children", "child"), ("categories", "category"),
  ("queries", "query"), ("boxes", "box"), ("buses", "bus"),
  ("statuses", "status"), ("knives", "knife"), ("wolves", "wolf"),
  ("mice", "mouse"), ("teeth", "tooth"), ("matrices", "matrix"),
  ("vertices", "vertex"), ("data", "datum"), ("quizzes", "quiz"),
  ("movies", "movie"), ("series", "series"), ("post", "post"),
  ("profile", "profile"), ("user", "user"), ("Users", "User"),
  ("address", "address"), ("addresses", "address"),
  ("analyses", "analyasis"), ("diagnoses", "diagnosis")]

test "pluralize":
  for (s, p) in plurals:
    check pluralize(s) == p, s & " -> " & pluralize(s) & ", want " & p

test "singularize":
  for (p, s) in singulars:
    check singularize(p) == s, p & " -> " & singularize(p) & ", want " & s

finish()
