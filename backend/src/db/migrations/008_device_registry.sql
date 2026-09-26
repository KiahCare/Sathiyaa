-- ---------------------------------------------------------------------
-- 008: a real device registry
-- ---------------------------------------------------------------------
--
-- customers.device_id and service_providers.device_id hold one opaque string
-- each, and that is all we have ever known about the phone an account is tied
-- to. It is enough to refuse a login from a second device, and useless for the
-- thing it was actually wanted for: if something goes wrong on a visit, being
-- able to say which handset it was.
--
-- A table rather than more columns, because the question is not "what device
-- is this account on" but "what devices has this account been on, and when".
-- A single column cannot answer the second, and the second is the one that
-- matters after the fact.
--
-- Nothing here is collected covertly. It is what the handset reports about
-- itself to any installed app -- make, model, OS version -- plus the address
-- the request arrived from. No identifiers that follow a person between apps,
-- no advertising id, no IMEI (Android has not given that out since 10).

CREATE TABLE user_devices (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

  user_type       ENUM('customer','provider','business_agent','admin') NOT NULL,
  user_id         INT UNSIGNED NOT NULL,

  -- The app's own generated id, persisted in the handset's shared preferences.
  -- Survives a restart, does not survive a reinstall -- which is correct: a
  -- reinstall genuinely is a new install, and pretending otherwise is what
  -- hardware identifiers were for.
  device_id       VARCHAR(255) NOT NULL,

  platform        VARCHAR(30)  NULL COMMENT 'android | ios | web',
  manufacturer    VARCHAR(80)  NULL COMMENT 'e.g. Xiaomi',
  model           VARCHAR(120) NULL COMMENT 'e.g. Redmi Note 12',
  os_version      VARCHAR(60)  NULL COMMENT 'e.g. Android 13 (SDK 33)',
  app_version     VARCHAR(40)  NULL COMMENT 'e.g. 1.0.3+12',

  -- False on an emulator. Worth knowing: a provider account that only ever
  -- signs in from an emulator is not a carer standing at somebody's door.
  is_physical     BOOLEAN NULL,

  first_seen_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- 45 characters because an IPv6 address needs them, and mobile networks in
  -- India hand out IPv6 routinely now. VARCHAR(15) would silently truncate.
  last_ip         VARCHAR(45)  NULL,
  last_user_agent VARCHAR(255) NULL,

  -- The device this account is currently bound to. Releasing a device in the
  -- console clears it here as well as on the account row, so the history stays
  -- and the binding goes.
  is_current      BOOLEAN NOT NULL DEFAULT TRUE,

  UNIQUE KEY uniq_user_device (user_type, user_id, device_id),
  INDEX idx_user_devices_owner (user_type, user_id),
  INDEX idx_user_devices_device (device_id),
  INDEX idx_user_devices_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
