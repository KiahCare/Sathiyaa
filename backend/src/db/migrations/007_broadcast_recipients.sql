-- How many people a broadcast reached.
--
-- The count was computed when the broadcast was sent, reported once in the
-- response, and then thrown away. The console's history list reads it back --
-- `recipient_count.toLocaleString(...)` -- so the first broadcast anyone sent
-- turned the whole admin console blank, because the field was not there to
-- read. Nobody noticed while the list was empty.
ALTER TABLE broadcast_messages
  ADD COLUMN recipient_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER sent_by,
  ADD COLUMN delivered_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER recipient_count;
