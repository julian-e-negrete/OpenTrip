# Setting up cloud sync

Cloud sync needs tables that don't exist in your Supabase project yet —
this is the one step only you can do; I can't run SQL against your
project without direct database credentials. Everything else (the app
code, the push/pull logic) is already wired up and does nothing harmful
if you skip this — it just fails quietly and your data stays local-only,
exactly like today.

## 1. Run the schema

1. Supabase Dashboard → your project → **SQL Editor** → **New query**.
2. Paste the contents of [`supabase/schema.sql`](../supabase/schema.sql)
   from this repo.
3. **Run**.

That creates four tables (`vehicles`, `trips`, `trip_points`, `profiles`),
each with row-level security scoped to `auth.uid()` — a user can only
ever read/write their own rows, enforced by Postgres itself, not just app
code.

## 2. That's it

No new dart-defines, no new secrets. The app already has everything it
needs (the same `SUPABASE_URL`/`SUPABASE_ANON_KEY` used for login). Once
the tables exist:

- Signing in pulls any existing cloud data for that account onto the
  device automatically.
- Adding/editing/deleting a vehicle or finishing a trip pushes it in the
  background — no button needed. There's also a manual **"Sync now"**
  button on the Account tab if you want to force it or check status.
- Guest mode (no account) stays local-only, on purpose — there's no
  Supabase session to authenticate a sync write with.

## What doesn't sync (yet)

- **Photos** (vehicle photos, your avatar) — these are local file paths.
  Syncing them needs a Supabase Storage bucket and its own policies,
  which is a separate piece of setup not included here.
- **Real-time / multi-device live updates** — sync is "pull once at
  sign-in, push after each local change," not a continuous background
  subscription. If you use the app on two devices at once, the second
  device won't see the first device's changes until you sign in again or
  tap "Sync now."
- **Conflict resolution** — if the same row is somehow edited on two
  devices, whichever pushes/pulls last simply overwrites the other. No
  merge logic. Unlikely to matter for one person's own vehicles/trips,
  but worth knowing.
- **Deleting a vehicle while offline** removes it locally immediately,
  and the remote delete is attempted best-effort — if that fails (no
  network), the remote copy can resurrect on your next pull. Deleting
  again once you're back online clears it for good.

See `docs/ROADMAP.md` for what's still open around this.
