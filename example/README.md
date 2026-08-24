# statecraft example

A test harness, not a deployable app: a full Rails application that lives the
statecraft gem page by page — real user flows over real models, seeded data,
and an e2e suite on top. It doubles as living documentation of the gem and as
its integration contour in an actual Rails (the gem's own suite runs bare
ActiveRecord).

## Running it

```
bin/setup
bin/rails s
```

PostgreSQL only, two databases on one server (primary + analytics) — SQLite
would show `json` where production shows `jsonb`, and what you look at must
be what is proven. The `production` environment does not exist by
construction: no `production.rb`, no credentials, and boot aborts if asked.

## The suite

From the gem root:

```
bin/example spec
```

`admin` is a route namespace, not a security boundary: the harness has no
users and no auth by design.
