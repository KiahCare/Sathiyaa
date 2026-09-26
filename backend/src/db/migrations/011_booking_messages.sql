-- ---------------------------------------------------------------------
-- 011: messages between a customer and the carer on their booking
-- ---------------------------------------------------------------------
--
-- The reference build has a chat thread with the companion, and there was
-- nothing behind ours. What people actually need it for is small and specific:
-- "I am ten minutes away", "the gate code is 4417", "she has already eaten".
-- Things that are too small for a phone call and too important to leave unsaid.
--
-- Deliberately tied to a booking rather than being an open inbox. A customer
-- can message the carer who is coming to their house, and nobody else; a carer
-- can message the family they are visiting, and nobody else. That is not a
-- limitation to work around later — an open messaging surface between
-- strangers on a care platform is a safeguarding problem, and the booking is
-- the relationship that makes the conversation legitimate.

CREATE TABLE booking_messages (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id    BIGINT UNSIGNED NOT NULL,

  -- Who wrote it. 'system' is for the app's own notes in the thread — "visit
  -- started", "running late" — so the history reads as one sequence rather
  -- than needing to be merged with events from somewhere else.
  sender_type   ENUM('customer','provider','system') NOT NULL,
  sender_id     INT UNSIGNED NULL COMMENT 'null for system messages',

  body          VARCHAR(1000) NOT NULL,

  -- When the other side read it. Null means unread, which is what drives the
  -- badge on both apps.
  read_at       DATETIME NULL,

  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  INDEX idx_messages_booking (booking_id, created_at),
  INDEX idx_messages_unread (booking_id, sender_type, read_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
