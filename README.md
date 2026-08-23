# statecraft

[![Gem Version](https://img.shields.io/gem/v/statecraft.svg)](https://rubygems.org/gems/statecraft)
[![CI](https://github.com/supostat/statecraft/actions/workflows/ci.yml/badge.svg)](https://github.com/supostat/statecraft/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

**[Website →](https://supostat.github.io/statecraft/)** · [RubyGems](https://rubygems.org/gems/statecraft) · [Issues](https://github.com/supostat/statecraft/issues)

A state machine for ActiveRecord where the current state lives in a column as
the single source of truth, history is an append-only per-model log with
write-once metadata, and every transition is guarded by a compare-and-swap
update inside a savepoint. Event-aware guards, an explicit bypass policy, and
telemetry for both successes and refusals.

statecraft is an **ActiveRecord gem**, not a Rails gem: its runtime depends on
`activerecord` and `activesupport` only. Anything that can call
`ActiveRecord::Base.establish_connection` gets the full pipeline; Rails adds
the generator as a progressive enhancement.

## Why

- `in_state?` and state scopes are a plain `WHERE` on a column — zero joins,
  unlike log-derived current state (`most_recent`-style schemas).
- Concurrency safety comes from a CAS `UPDATE ... WHERE state = :expected`:
  of N concurrent writers exactly one wins, the rest get a deterministic
  `Statecraft::TransitionConflict`, and the log records exactly one row.
- The log carries first-class, write-once `jsonb` metadata: what the guards
  checked is byte-for-byte what the log stored.

## Installation

```ruby
gem "statecraft"
```

Requires Ruby >= 3.3 and ActiveRecord/ActiveSupport >= 7.2, < 9.
PostgreSQL is the first-class database; SQLite works for development and
tests (see [SQLite limits](#sqlite-limits)); MySQL is out of scope for v0.

## Quick start

```sh
bin/rails generate statecraft:machine Order
```

The generator creates the migration (state column, `state_changed_at`, the
log table with a cascade FK — and a CHECK constraint when the table is
freshly created), the machine class, the readonly log model, and mounts the
machine into the model. By hand it looks like this:

```ruby
class OrderFlow < ApplicationMachine
  state :pending, initial: true
  state :paid
  state :cancelled

  event :pay, from: :pending, to: :paid, guard: :payable?
  transition from: :pending, to: :cancelled

  after_commit :enqueue_receipt, event: [:pay]

  private

  def payable?(order, metadata)
    metadata["amount"].to_i.positive?
  end

  def enqueue_receipt(order, transition)
    ReceiptJob.perform_later(order.id, transition.log_record.id)
  end
end

class Order < ApplicationRecord
  state_machine OrderFlow, changed_at: true, helpers: true, scopes: true
end

order = Order.create!                                # born :pending via the column default
order.pay!(metadata: { amount: 100, reason: :web }) # => the created OrderTransition row
order.in_state?(:paid)                               # => true
Order.paid.count                                     # plain WHERE, zero joins
```

Mounting options: `log:` (defaults to the `<Model>Transition` convention),
`column:` (default `:state`), `changed_at:` (off by default; `true` derives
`<column>_changed_at`), `touch:` (default `true` — `updated_at` is written in
the same CAS update), `helpers:` and `scopes:` (both off by default; the
generator turns them on for new code).

## The transition pipeline

`transition_to!` / `fire!` run one strict order:

1. `persisted?` check — transitioning an unsaved record raises
   `Statecraft::UnsavedRecordError`: initial state comes from the column
   default, so there is nothing to transition.
2. Metadata normalization and deep-freeze (see [Metadata](#metadata)).
3. Edge resolution and the bypass policy check.
4. Dirty check on `lock: true` edges — unsaved changes raise
   `Statecraft::DirtyRecordError` instead of being silently destroyed by the
   reload.
5. `transaction(requires_new: true)` — a savepoint inside your transaction,
   a real transaction otherwise: optional `SELECT ... FOR UPDATE` + reload
   (a state that changed under the lock raises
   `Statecraft::TransitionConflict`), guards, `before_transition`
   callbacks, the CAS update (touching `updated_at` and the `changed_at`
   column in the same statement), the log INSERT, `after_transition`.
6. `after_commit` callbacks are registered on the outermost real
   transaction's commit.

A transition is **not** a record save: model validations and model callbacks
do not run, and unsaved changes on other attributes are neither saved nor
(without `lock:`) touched. Guards are the transition's validations; machine
callbacks are the transition's callbacks.

Bang variants return the created log record. Non-bang variants return it too,
or `false` — and `false` means exactly "a guard said no or the edge is not
declared" (`GuardFailed` / `InvalidTransition`). Everything else — including
`TransitionConflict` — always raises, in both variants.

## Guards, events and the bypass policy

A guard is attached to `(from, to, event-or-nil)`: an edge guard always runs,
an event guard runs only when the transition goes through that event. Within
one event, `from` is unique — an event is a partial function from state to
edge, so `fire!` is structurally deterministic. Branching by outcome means
two events (`pay` and `fail_payment`), not one event with two branches.

Calling `transition_to!` directly over an edge that carries event guards is
refused — the guards would be silently skipped. The escape hatch is explicit:
`transition_to!(:paid, bypass_events: true)` skips event guards (edge guards
still run) and records `event: nil` in the log, so audited bypasses stay
visible.

## Callbacks and chains

`before_transition`, `after_transition` and `after_commit` accept `from:`,
`to:` and `event:` filters (arrays welcome). Handlers — symbols resolving to
machine instance methods, or callables — receive `(record, transition)` where
`transition` carries `from`, `to`, `event`, `metadata` and (after the INSERT)
`log_record`.

Launching the next transition from `after_transition` is a supported pattern:
the chain writes one log row per hop and every `after_commit` waits for the
outermost commit. Two facts to know:

- **The after-commit order is inverted.** A nested transition registers its
  `after_commit` before its parent does, so on commit the chain's callbacks
  run innermost-first (`fulfill` before `pay`). This is documented, tested
  semantics — do not "fix" it.
- **The chain depth ceiling is 16.** Deeper nesting raises
  `Statecraft::ChainDepthExceeded` with the printed chain, which makes an
  accidental cycle visible at a glance.

Transitioning the *same record* from a guard or from `before_transition`
raises `Statecraft::NestedTransitionError` immediately — the CAS would
otherwise reject itself and masquerade as a phantom race. Transitioning from
`after_commit` is an independent pipeline and is always legal.

## after_commit and transactional tests

`after_commit` follows Active Record transaction-callback semantics
everywhere, including transactional tests. **Inside your own transaction,
"the transition succeeded" does not mean "after_commit ran"** — the callback
waits for the outermost real commit and silently never runs if that
transaction rolls back, exactly like a model's `after_commit`. In a
transactional test, `order.pay!` behaves the way `record.save` with a model
after_commit callback behaves in that same test — one invariant, no special
cases to learn. Exceptions raised inside `after_commit` propagate as-is: the
transition is already committed, so they are handler errors, not transition
errors.

## Concurrency and isolation

The CAS update is the concurrency contract: on the default READ COMMITTED
isolation a race deterministically produces `TransitionConflict` for every
loser, with the expected `from` in the error. Rescuing the conflict inside
your transaction is safe: the savepoint has already rolled back the
pipeline's effects, your outer work stays intact, and you may retry from the
fresh state or take another branch.

`lock: true` on an edge or event adds `SELECT ... FOR UPDATE` plus a reload
before the guards. The row lock lives until your outermost transaction
commits — releasing the savepoint does not release it.

On stricter isolation levels (SERIALIZABLE) the same race may surface as
`ActiveRecord::SerializationFailure` before the CAS ever sees it — up to and
including commit time. statecraft passes the whole
`ActiveRecord::TransactionRollbackError` family (including `Deadlocked`)
through untouched: those errors mean "restart the whole transaction", a
different protocol than the conflict's "continue from clean state", and the
retry policy belongs to whoever chose the isolation level.

## Introspection

```ruby
order.can_fire?(:pay, metadata: { amount: 100 })  # would the guards pass right now?
order.may_pay?(metadata: { amount: 100 })          # alias, with helpers: true
order.available_events(metadata: { amount: 100 })  # => [:pay]
order.available_transitions(metadata: {})          # => [#<to: :cancelled, via: [:direct]>]
order.transitioned_to?(:paid)                      # strictly log-based
```

`available_transitions` tells you not only *where* you can go but *how*:
`via` lists the events whose guards pass, plus `:direct` when the edge is
free of event guards and its edge guards pass. Every answer is a snapshot —
CAS may still reject the transition a moment later.

A guard that reads metadata makes `may_*?` depend on the metadata you pass.
For a UI "is this button available" question, either do not hang input
validation on a guard, or pass the same metadata to `may_*?` that you will
collect for `fire!`.

## Metadata

Metadata is normalized on pipeline entry with a full JSON round-trip —
symbol keys and values become strings, times become ISO-8601 strings — and
then deep-frozen: **the guards see exactly what the log will store**, and a
guard that mutates metadata dies with `FrozenError` in a transition and in a
check alike. Unserializable values (a `Proc`, a model instance) fail
instantly at the entrance, not inside the transaction.

Facts of the transition moment (a price snapshot, a rules version) are
collected by the caller: `order.pay!(metadata: { price: order.total })`.
There is no metadata schema mechanism — required fields are enforced by
guards — and the shape evolves by convention: carry a `v:` key when you need
versioned readers.

## Initial state is not a transition

Creating a record is not a transition: rows enter the initial state through
the column default (which also covers `insert_all`, fixtures, seeds and ETL),
and the log stays silent about births — a consistently silent audit beats an
inconsistently chatty one.

| Question | Answer |
|---|---|
| When did the record enter the initial state? | `created_at` |
| Has it ever *transitioned to* `:pending`? | `transitioned_to?(:pending)` — `false` until a real transition (a loop or a return counts) |
| Is it in `:pending` now? | `in_state?(:pending)` / `where(state: :pending)` |

## The log model is a read-model

Scopes, reading methods and serializers on the log class are yours. Writing
is not: the pipeline inserts rows through the insert path, so validations and
callbacks declared on the log model never run — guards and machine callbacks
are the single channel of truth. The generated `readonly?` makes persisted
rows reject `update!` and `destroy`; it protects against accidental edits,
not malicious ones (`update_all` and raw SQL still work — the real guarantee
would be database triggers, which are out of v0). Deleting `readonly?` in
your generated class is a supported customization.

Deleting the parent record cascades to its log rows at the database level
(`ON DELETE CASCADE`): an audit without its subject is not an audit. If your
requirement is "history survives deletion", the answer is soft-deleting the
record, not an FK mode — and swapping `:cascade` for `:restrict` in your
generated migration is supported if you disagree.

## Configuration

There is none — deliberately. Every knob lives with its subject: mounting
options on `state_machine`, `lock:` on edges and events, schema choices in
your generated migration, `readonly?` in your generated log class. No
initializer, no `Statecraft.configure`. If a future feature genuinely needs
process-level configuration it will arrive as a designed decision, not as a
convenience knob.

## Renaming a state

The log is never migrated: history is written in the words of its time, and
every reading API handles log rows whose state names are no longer in the
graph. To rename `:pending` to `:awaiting_payment`, follow the three-phase
rolling rename recipe on the column:

1. Declare **both** states in the machine with duplicated edges; widen the
   CHECK constraint to both names (adding a value is cheap).
2. Batch-`UPDATE` the column. Races are loud by construction: a row
   repainted under a live transition makes its CAS miss and raise
   `TransitionConflict` — retry from the new name. For a large table, add
   the widened constraint as `NOT VALID` first and `VALIDATE CONSTRAINT`
   after the cleanup.
3. Drop the old state and its edges; narrow the CHECK back.

## PII and erasure

Metadata is the only place personal data can live — `from_state`, `to_state`
and `event` never carry it, and telemetry payloads exclude metadata entirely.
Three layers, in order of preference:

1. **References, not values.** Store `{ user_id: 42 }`, not an email. Erasure
   then touches the referent, never the log.
2. **Hard delete.** `destroy` cascades to the log rows for free.
3. **Soft delete + scrubbing.** Administrative erasure works at the relation
   level, past `readonly?`:
   `order.history.where(...).update_all(metadata: { scrubbed_at: Time.current.iso8601 })`.
   The tombstone convention keeps the audit honest: "there was data here,
   erased on request" is a legally different statement than "there was
   nothing".

## STI

Mounting a machine on an STI base class is promised behavior: subclasses
inherit the machine, helpers and scopes (`CreditOrder.pending` scopes the
subclass by `type` + `state`, exactly like an enum scope would), CAS and the
log FK hit the base class's table, and guards receive the actual subclass
instance. Two honest boundaries: name-conflict checks at mounting cover the
mounting class only — a subclass method shadowing a generated verb is plain
Ruby method overriding; and mounting a *different* machine in a subclass is
the multi-machine feature, out of v0 — it raises `Statecraft::AlreadyMounted`
at the threshold.

## Multiple databases

The log lives next to its model, always — a cascade FK cannot cross
databases, so this is a definition, not a restriction. The generated log
class inherits the model's connection-owning ancestor (base, roles and
horizontal shards follow automatically), and the generator drops the
migration into that connection's migration path. Mounting verifies connection
identity — same pool, same per-thread connection, one real transaction — and
raises `Statecraft::ConnectionMismatch` with a fix hint otherwise. Two
`connects_to` blocks pointing at one physical database are still two pools:
that also fails the check, correctly.

## Outside Rails

No railties at runtime — the hygiene is enforced by a test, not a promise.
Without the generator, create the schema by hand; the reference shape:

```ruby
create_table :orders do |t|
  t.string :state, null: false, default: "pending", index: true
  t.datetime :state_changed_at
  t.timestamps null: false
end
add_check_constraint :orders, "state IN ('pending')", name: "orders_state_check"

create_table :order_transitions do |t|
  t.references :order, null: false,
                       foreign_key: { on_delete: :cascade }, index: false
  t.string :from_state, null: false
  t.string :to_state, null: false
  t.string :event
  t.jsonb :metadata, null: false, default: {}
  t.datetime :created_at, null: false
  t.index %i[order_id id]
end
```

## SQLite limits

SQLite is a development and test database: `metadata` falls back to
`json`/text, concurrency specs skip (the concurrency proof runs on
PostgreSQL in CI), and `lock: true` degrades the way ActiveRecord itself
degrades — the locking clause is dropped, the reload still runs, and
statecraft warns once per machine per process that row-locking guarantees
require PostgreSQL.

## Running the tests

Natively, against SQLite:

```sh
bundle install
bundle exec rspec
```

Against PostgreSQL — where the concurrency proof actually runs — point
`DATABASE_URL` at a database of your own, or use the bundled containers, which
pin the same PostgreSQL major as CI and take the Ruby and ActiveRecord versions
as parameters, so any CI matrix cell reproduces locally:

```sh
docker compose run --rm test                                # sqlite, default Ruby
docker compose run --rm test-postgres                       # PostgreSQL 16
AR_VERSION=7.2 RUBY_VERSION=3.3 docker compose run --rm test-postgres
```

## Links

- Landing page: <https://supostat.github.io/statecraft/>
- RubyGems: <https://rubygems.org/gems/statecraft>
- Issues: <https://github.com/supostat/statecraft/issues>

## License

MIT. See [LICENSE.txt](LICENSE.txt).
