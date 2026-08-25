# Benchmarks: statecraft vs statesman vs aasm

Three measurements, each honest about what it shows:

1. **`read_state.rb`** — reading the current state. statecraft and aasm
   answer from an indexed column (expect parity — that is the point);
   statesman derives state from its transition table, so `in_state` pays a
   `most_recent` join. Corpus: 200k rows per stack, half paid.
2. **`concurrent_write.rb`** — 8 threads race one pending record through
   the same transition. The output is a table of outcomes: successes,
   error classes, log rows written, callbacks fired. statecraft yields
   exactly one winner plus deterministic `TransitionConflict`s; aasm
   without an explicit lock silently loses updates and fires callbacks
   more than once; statesman is saved by its unique index, surfacing as
   `RecordNotUnique` from inside the INSERT.
3. **`single_transition.rb`** — the cost of one uncontended transition.
   statecraft pays a savepoint + CAS UPDATE + log INSERT against aasm's
   single UPDATE — the gap is the price of the audit log and conflict
   safety, and it is published as such.

## Running

Smoke (seconds, tiny figures — the CI-style gate):

```sh
docker compose run --rm bench
```

Full run (minutes; the numbers for site/compare.html):

```sh
docker compose run --rm bench bash -c "bundle install && bundle exec ruby read_state.rb && bundle exec ruby concurrent_write.rb && bundle exec ruby single_transition.rb"
```

Against your own PostgreSQL: `DATABASE_URL=postgres://… bundle exec ruby read_state.rb`
from this directory. Every script prints its environment banner (gem
versions, Ruby, PostgreSQL, date) — quote it next to the numbers.

The stacks are isolated: separate tables (`bench_*`), separate models, one
schema reset per run. Dependencies live only in this directory's Gemfile —
the gem itself never depends on its competitors.
