-- Adds the "additional requirements" batch: T&C/Privacy acceptance,
-- customer<->provider linking (favorites, capped at 10 app-side), provider
-- verification document date ranges, No Fees / Time Bank, manual payment
-- tracking with partial payments + reminders, provider feedback on the
-- customer, organization employee allocation routing, and organization
-- service fees + Sathiyaa's revenue-share markup on organization bookings.

ALTER TABLE customers
  ADD COLUMN terms_privacy_accepted_at DATETIME NULL COMMENT 'set when the customer ticks "I agree to the T&C and Privacy Policy" before Continue' AFTER device_id,
  ADD COLUMN rating_avg   DECIMAL(3,2) NOT NULL DEFAULT 0 COMMENT 'average of provider feedback on this customer' AFTER terms_privacy_accepted_at,
  ADD COLUMN rating_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER rating_avg;

ALTER TABLE service_providers
  ADD COLUMN no_fees BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'volunteer/donated service — hourly_rate ignored, hours credited to Time Bank instead' AFTER hourly_rate,
  ADD COLUMN police_verification_valid_from DATE NULL AFTER police_verification_url,
  ADD COLUMN police_verification_valid_to   DATE NULL AFTER police_verification_valid_from,
  ADD COLUMN medical_certificate_url        VARCHAR(500) NULL AFTER police_verification_valid_to,
  ADD COLUMN medical_certificate_valid_from DATE NULL AFTER medical_certificate_url,
  ADD COLUMN medical_certificate_valid_to   DATE NULL AFTER medical_certificate_valid_from,
  ADD COLUMN allocate_via_org BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'organization rows only — when true, search shows the org (not individual employees) and bookings route to the org for allocation' AFTER work_certificate_url;

ALTER TABLE bookings
  ADD COLUMN assigned_employee_id INT UNSIGNED NULL COMMENT 'org_employee actually performing the service, set by the org admin when confirmed_provider_id is an organization' AFTER confirmed_provider_id,
  ADD COLUMN amount_due DECIMAL(10,2) NULL COMMENT 'total service amount owed by the customer, set once the session amount is computed' AFTER payment_deadline_at,
  ADD COLUMN amount_received DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT 'sum of booking_payments recorded by the provider' AFTER amount_due,
  ADD COLUMN payment_status ENUM('pending','partial','paid') NOT NULL DEFAULT 'pending' AFTER amount_received,
  ADD COLUMN last_payment_reminder_at DATETIME NULL AFTER payment_status,
  ADD CONSTRAINT fk_bookings_assigned_employee FOREIGN KEY (assigned_employee_id) REFERENCES service_providers(provider_id);

CREATE TABLE customer_ratings (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id    BIGINT UNSIGNED NOT NULL,
  provider_id   INT UNSIGNED NOT NULL COMMENT 'the provider giving feedback',
  customer_id   INT UNSIGNED NOT NULL COMMENT 'the customer being rated',
  rating        TINYINT UNSIGNED NOT NULL COMMENT '1-5',
  comments      VARCHAR(1000) NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  UNIQUE KEY uq_customer_rating_booking (booking_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_provider_links (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id   INT UNSIGNED NOT NULL,
  provider_id   INT UNSIGNED NOT NULL COMMENT 'a preferred/regular caretaker — app layer caps this at 10 per customer',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  UNIQUE KEY uq_customer_provider_link (customer_id, provider_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE booking_payments (
  id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id     BIGINT UNSIGNED NOT NULL,
  amount         DECIMAL(10,2) NOT NULL,
  payment_type   ENUM('full','part') NOT NULL,
  recorded_by    INT UNSIGNED NOT NULL COMMENT 'service_providers.provider_id who marked the payment',
  recorded_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  note           VARCHAR(255) NULL,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  INDEX idx_booking_payments_booking (booking_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE time_bank_config (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  service_type      ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  points_per_hour   DECIMAL(8,2) NOT NULL COMMENT 'points credited per donated (No Fees) hour of this service, for the given application_year',
  application_year  YEAR NOT NULL,
  updated_by        INT UNSIGNED NULL COMMENT 'admin_users.admin_id',
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_timebank_service_year (service_type, application_year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE time_bank_ledger (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id   INT UNSIGNED NOT NULL,
  booking_id    BIGINT UNSIGNED NOT NULL,
  service_type  ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  hours         DECIMAL(6,2) NOT NULL,
  points_earned DECIMAL(10,2) NOT NULL,
  recorded_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  INDEX idx_timebank_ledger_provider (provider_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE organization_service_fees (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  organization_id INT UNSIGNED NOT NULL COMMENT 'service_providers.provider_id where provider_kind = organization',
  service_type    ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  fee_per_hour    DECIMAL(8,2) NOT NULL COMMENT 'overrides each employee''s own hourly_rate for this service when set',
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  UNIQUE KEY uq_org_service_fee (organization_id, service_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
