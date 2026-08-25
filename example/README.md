# statecraft store

A complete, working web store that runs on the statecraft gem — and doubles
as its integration contour in an actual Rails (the gem's own suite runs bare
ActiveRecord).

Two zones, two languages:

- **Storefront** — a catalog with prices, a session cart, checkout (express
  and credit are the customer's checkboxes), and "my orders" told in human
  words: Awaiting payment, Paid, Cancelled, Delivered. The gem's vocabulary
  never surfaces here.
- **Operator zone** (`/admin`) — the same orders with everything the gem can
  show: the prediction panel, the transition history, preview, the bypass
  and admin_override paths, the payment desk whose confirmation captures the
  payment and pays the order, the shipment desk with its conditional express
  cascade, and the operations feed where refusals appear with their reason.

## Roles and permissions

Three demo people live in the top-bar switcher — Uma (user), Mark (manager)
and Ada (admin) — and picking one is the whole "login": there is no
authentication by design, only authorization. Permissions are CanCanCan's:
the `Ability` class maps roles straight onto the machines' events, and every
action button renders in the intersection of the machine's offering
(`offerable_events` — the graph filtered by the record layer of the guards)
and the role's permission (`can?`). Everyone shops and pays their own
orders; a manager works the desks but pays no one else's order — that path
goes through payment confirmation; an admin owns the privileged edge paths
(`admin_override`, bypass). Input guards never gate the render — a
metadata-reading guard refuses input, not possibility, and the guard-aware
panel carries the prediction — while the record layer gates it honestly: a
credit order is not offered `cancel` at all, the desk's "Not offered" panel
names the refusing guard (`refusals_for`), and the storefront says the same
fact in human words.

`admin` stays a route namespace, not a security boundary.

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

Protocol coverage is tracked in [`CATALOG.md`](CATALOG.md) and held by two
CI locks: `script/catalog_check.rb` (two-way catalog ↔ markers) and
`script/readme_drift_check.rb` (the gem README's anchored blocks stay
byte-identical to this app's marked regions).
