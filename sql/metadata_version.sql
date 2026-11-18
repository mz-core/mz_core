-- Run manually only after stopping all writers and taking a verified backup.
-- Do not apply while older Core versions or other metadata writers are active.
ALTER TABLE mz_players
  ADD COLUMN metadata_version BIGINT UNSIGNED NOT NULL DEFAULT 0;
