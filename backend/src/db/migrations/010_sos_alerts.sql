-- ---------------------------------------------------------------------
-- 010: emergency alerts
-- ---------------------------------------------------------------------
--
-- The SOS screen has always put the right numbers in front of the customer and
-- said plainly that nothing had been sent, because nothing had. This is the
-- other half: a record of every alert raised, who it went to, and whether the
-- message actually left.
--
-- The row is written even when the SMS provider is a stub. That is deliberate.
-- An alert that was raised and not delivered is precisely the thing somebody
-- needs to be able to find afterwards, and "we have no record" is the worst
-- possible answer to give a family.

CREATE TABLE sos_alerts (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id     INT UNSIGNED NOT NULL,

  -- Where they were when they raised it. Null when the phone would not say —
  -- which happens, and is not a reason to refuse the alert.
  latitude        DECIMAL(10,7) NULL,
  longitude       DECIMAL(10,7) NULL,
  address_text    VARCHAR(500) NULL COMMENT 'the address as the app showed it at the time',

  -- If a visit was under way, the carer is the nearest help there is.
  booking_id      BIGINT UNSIGNED NULL,

  note            VARCHAR(500) NULL COMMENT 'anything the customer typed',

  -- Whether anything actually went out. 'simulated' when no SMS provider is
  -- configured: the alert is real and recorded, the message was not sent.
  delivery        ENUM('sent','partial','failed','simulated') NOT NULL DEFAULT 'simulated',
  notified_count  INT UNSIGNED NOT NULL DEFAULT 0,

  -- Who Sathiyaa tried to reach, and what happened to each. JSON because the
  -- shape is a list of {name, relationship, number, ok, error} and nothing
  -- else queries inside it.
  recipients      JSON NULL,

  -- Closed by staff once somebody has actually spoken to the family.
  acknowledged_at DATETIME NULL,
  acknowledged_by INT UNSIGNED NULL COMMENT 'admin_users.admin_id',
  resolution      VARCHAR(500) NULL,

  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  INDEX idx_sos_customer (customer_id),
  INDEX idx_sos_created (created_at),
  INDEX idx_sos_open (acknowledged_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
