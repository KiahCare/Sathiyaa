-- Broadcasts that reach somebody, and that can be aimed.
--
-- Two problems, one migration.
--
-- 1. A broadcast reached nobody. It was written to broadcast_messages, counted,
--    and handed to the push adapter -- which is a stub that logs a line and
--    returns sent:false. No app could read it back either: there was no
--    endpoint for a customer or provider to ask what had been sent to them. So
--    every broadcast ever sent had delivered_count = 0, correctly.
--
--    broadcast_recipients fixes that without needing FCM, an SMS bill or any
--    account anywhere: the message is stored against each person it is for,
--    and their app reads its own row. Push, when it is switched on, becomes a
--    second delivery channel for the same row rather than the only one.
--
-- 2. It could only be aimed at "customers", "providers" or "both". The columns
--    below record what was actually asked for, so the history can say "sent to
--    Bengaluru" rather than "sent to customers" a month later.

CREATE TABLE IF NOT EXISTS broadcast_recipients (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  broadcast_id  BIGINT UNSIGNED NOT NULL,
  user_type     ENUM('customer','provider') NOT NULL,
  user_id       INT UNSIGNED NOT NULL,
  read_at       DATETIME NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (broadcast_id) REFERENCES broadcast_messages(id) ON DELETE CASCADE,
  -- One row per person per broadcast. Re-sending is a new broadcast, not a
  -- duplicate row on the old one.
  UNIQUE KEY uq_broadcast_recipient (broadcast_id, user_type, user_id),
  -- The app's own query: "what has been sent to me, newest first".
  INDEX idx_broadcast_for_user (user_type, user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- What the broadcast was aimed at, kept for the history list.
--
-- JSON rather than a join table: these are a handful of strings written once
-- and only ever read back whole, for display. A cities_broadcast table would
-- be three more joins for no question anybody asks.
ALTER TABLE broadcast_messages
  ADD COLUMN target_cities   JSON NULL AFTER target_audience,
  ADD COLUMN target_pincodes JSON NULL AFTER target_cities,
  ADD COLUMN target_explicit TINYINT(1) NOT NULL DEFAULT 0 AFTER target_pincodes;
