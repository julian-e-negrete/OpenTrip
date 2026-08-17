-- Enables continuous (websocket push, not polling) sync — see
-- apps/mobile/lib/sync/sync_service.dart's _startRealtimeSync. Run this
-- once, after supabase/schema.sql, in the same SQL Editor.
--
-- Wrapped in DO blocks so re-running this file is harmless (Postgres
-- errors on `ALTER PUBLICATION ... ADD TABLE` for a table already in the
-- publication; this catches that specific case and moves on instead of
-- aborting the whole script).
--
-- trip_points is deliberately not included — see the SyncService doc
-- comment for why (a finished trip can push hundreds of point rows at
-- once, which isn't a good fit for individual realtime events; it stays
-- on the existing lazy-pull-per-trip model).

do $$
begin
  alter publication supabase_realtime add table public.vehicles;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.trips;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null;
end $$;
