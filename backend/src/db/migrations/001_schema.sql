-- =====================================================================
-- Sathiyaa Platform — MySQL 8.x Schema
-- Covers: Customer, Service Provider (Freelancer/Organization), Business
-- Agent, Admin, Bookings, Configuration, Reporting, Audit.
-- Character set utf8mb4 throughout (encryption-at-rest handled at the
-- storage/volume layer + application-layer field encryption for PII —
-- see docs/security.md).
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- ADMIN & PLATFORM USERS
-- ---------------------------------------------------------------------
CREATE TABLE admin_users (
  admin_id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name            VARCHAR(120) NOT NULL,
  email           VARCHAR(150) NOT NULL UNIQUE,
  password_hash   VARCHAR(255) NOT NULL,
  role            ENUM('super_admin','ops_admin','support') NOT NULL DEFAULT 'ops_admin',
  status          ENUM('active','blocked') NOT NULL DEFAULT 'active',
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- CUSTOMERS
-- ---------------------------------------------------------------------
CREATE TABLE customers (
  customer_id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  display_id            VARCHAR(20) NOT NULL UNIQUE COMMENT 'e.g. CUST-000001, generated from customer_id',
  name                  VARCHAR(120) NOT NULL,
  photo_url             VARCHAR(500) NOT NULL,
  dob                   DATE NOT NULL,
  gender                ENUM('male','female','other') NOT NULL,
  blood_group           ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-','unknown') DEFAULT 'unknown',
  email                 VARCHAR(150) NULL,
  mobile_number         VARCHAR(20) NOT NULL UNIQUE,
  otp_hash              VARCHAR(255) NULL,
  otp_expires_at        DATETIME NULL,
  preferred_languages   JSON NULL COMMENT 'array of language codes',
  height_cm             DECIMAL(5,2) NULL,
  weight_kg             DECIMAL(5,2) NULL,
  bmi                   DECIMAL(5,2) GENERATED ALWAYS AS (
                            CASE WHEN height_cm IS NOT NULL AND weight_kg IS NOT NULL AND height_cm > 0
                            THEN ROUND(weight_kg / POWER(height_cm/100, 2), 2) ELSE NULL END
                        ) STORED,
  preferred_comm_mode      SET('email','call','sms') NULL,  -- multiple choice: the profile screen offers all three as checkboxes
  preferred_comm_timeframe VARCHAR(50) NULL COMMENT 'e.g. 9am-12pm',
  referred_by_code       VARCHAR(30) NULL COMMENT 'business agent reference code entered at registration',
  registration_fee_paid  BOOLEAN NOT NULL DEFAULT FALSE,
  registration_txn_id    BIGINT UNSIGNED NULL,
  status                 ENUM('pending_payment','active','blocked') NOT NULL DEFAULT 'pending_payment',
  device_id              VARCHAR(255) NULL COMMENT 'binds account to one mobile device',
  created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_customers_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_addresses (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id   INT UNSIGNED NOT NULL,
  address_type  ENUM('primary','secondary') NOT NULL,
  line1         VARCHAR(255) NOT NULL,
  line2         VARCHAR(255) NULL,
  city          VARCHAR(100) NULL,
  state         VARCHAR(100) NULL,
  pincode       VARCHAR(12) NULL,
  latitude      DECIMAL(10,7) NULL,
  longitude     DECIMAL(10,7) NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  UNIQUE KEY uq_customer_addr_type (customer_id, address_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_vitals (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id   INT UNSIGNED NOT NULL,
  vital_type    ENUM('bp','spo2','pulse','glucose') NOT NULL,
  value_primary   DECIMAL(6,2) NOT NULL COMMENT 'systolic for BP, value for others',
  value_secondary DECIMAL(6,2) NULL COMMENT 'diastolic for BP only',
  recorded_at   DATETIME NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  INDEX idx_vitals_customer_type_date (customer_id, vital_type, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_medications (
  id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id       INT UNSIGNED NOT NULL,
  medicine_name     VARCHAR(150) NOT NULL,
  frequency         VARCHAR(100) NOT NULL,
  prescription_url  VARCHAR(500) NULL,
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_surgeries (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id   INT UNSIGNED NOT NULL,
  surgery_name  VARCHAR(150) NOT NULL,
  surgery_date  DATE NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_allergies (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id   INT UNSIGNED NOT NULL,
  allergy_name  VARCHAR(150) NOT NULL,
  onset_date    DATE NULL,
  status        ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_insurance (
  id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id    INT UNSIGNED NOT NULL,
  insured_with   VARCHAR(150) NOT NULL,
  policy_number  VARCHAR(100) NOT NULL,
  start_date     DATE NOT NULL,
  end_date       DATE NOT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE customer_family_members (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id     INT UNSIGNED NOT NULL,
  name            VARCHAR(120) NOT NULL,
  relationship    VARCHAR(60) NOT NULL,
  contact_number  VARCHAR(20) NOT NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- SERVICE PROVIDERS (Freelancer or Organization; org employees are
-- providers with organization_id pointing at the org's own provider row)
-- ---------------------------------------------------------------------
CREATE TABLE service_providers (
  provider_id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  display_id              VARCHAR(20) NOT NULL UNIQUE COMMENT 'e.g. SP-000001',
  provider_kind           ENUM('freelancer','organization','org_employee') NOT NULL,
  organization_id         INT UNSIGNED NULL COMMENT 'set when provider_kind = org_employee',
  name                    VARCHAR(150) NOT NULL COMMENT 'person name or organization name',
  photo_url               VARCHAR(500) NULL,
  gender                  ENUM('male','female','other') NULL,
  dob                     DATE NULL,
  mobile_number           VARCHAR(20) NOT NULL UNIQUE,
  email                   VARCHAR(150) NULL,
  pin_hash                VARCHAR(255) NULL COMMENT '6-digit login PIN, hashed',
  hourly_rate             DECIMAL(8,2) NOT NULL DEFAULT 0,
  aadhar_doc_url          VARCHAR(500) NULL,
  police_verification_url VARCHAR(500) NULL,
  work_certificate_url    VARCHAR(500) NULL,
  approval_status         ENUM('pending','approved','hold','rejected') NOT NULL DEFAULT 'pending',
  approval_notes          VARCHAR(500) NULL,
  approved_by             INT UNSIGNED NULL COMMENT 'admin_users.admin_id',
  approved_at             DATETIME NULL,
  status                  ENUM('active','blocked') NOT NULL DEFAULT 'active',
  registration_fee_paid   BOOLEAN NOT NULL DEFAULT FALSE,
  registration_txn_id     BIGINT UNSIGNED NULL,
  device_id               VARCHAR(255) NULL COMMENT 'binds account to one mobile device',
  location_on             BOOLEAN NOT NULL DEFAULT FALSE,
  current_latitude        DECIMAL(10,7) NULL,
  current_longitude       DECIMAL(10,7) NULL,
  current_location_at     DATETIME NULL,
  distance_from_home_pref_km    DECIMAL(6,2) NULL,
  distance_from_office_pref_km  DECIMAL(6,2) NULL,
  rating_avg               DECIMAL(3,2) NOT NULL DEFAULT 0,
  rating_count              INT UNSIGNED NOT NULL DEFAULT 0,
  created_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES service_providers(provider_id) ON DELETE SET NULL,
  INDEX idx_providers_approval_status (approval_status, status),
  INDEX idx_providers_location (current_latitude, current_longitude)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE service_provider_addresses (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id   INT UNSIGNED NOT NULL,
  address_type  ENUM('home','office') NOT NULL DEFAULT 'home',
  line1         VARCHAR(255) NOT NULL,
  line2         VARCHAR(255) NULL,
  city          VARCHAR(100) NULL,
  state         VARCHAR(100) NULL,
  pincode       VARCHAR(12) NULL,
  latitude      DECIMAL(10,7) NULL,
  longitude     DECIMAL(10,7) NULL,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE service_provider_work_hours (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id   INT UNSIGNED NOT NULL,
  day_of_week   ENUM('sun','mon','tue','wed','thu','fri','sat') NOT NULL,
  start_time    TIME NOT NULL,
  end_time      TIME NOT NULL,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  UNIQUE KEY uq_provider_day (provider_id, day_of_week)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE service_provider_expertise (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id    INT UNSIGNED NOT NULL,
  service_type   ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  years_experience DECIMAL(4,1) NULL,
  notes          VARCHAR(500) NULL,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  UNIQUE KEY uq_provider_service (provider_id, service_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE service_provider_calendar_blocks (
  id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id    INT UNSIGNED NOT NULL,
  block_start    DATETIME NOT NULL,
  block_end      DATETIME NOT NULL,
  reason         VARCHAR(255) NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  INDEX idx_block_provider_range (provider_id, block_start, block_end)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- BUSINESS AGENTS (Business Partners)
-- ---------------------------------------------------------------------
CREATE TABLE business_agents (
  business_partner_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  display_id            VARCHAR(20) NOT NULL UNIQUE COMMENT 'e.g. BP-000001',
  entity_name            VARCHAR(150) NOT NULL,
  partner_name           VARCHAR(150) NOT NULL,
  contact_number_1       VARCHAR(20) NOT NULL,
  contact_number_2       VARCHAR(20) NULL,
  email                  VARCHAR(150) NULL,
  address                VARCHAR(255) NULL,
  password_hash          VARCHAR(255) NULL,
  otp_hash                VARCHAR(255) NULL,
  otp_expires_at          DATETIME NULL,
  referral_code           VARCHAR(30) NOT NULL UNIQUE,
  status                  ENUM('active','blocked') NOT NULL DEFAULT 'active',
  created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE business_agent_referrals (
  id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  business_partner_id INT UNSIGNED NOT NULL,
  customer_id         INT UNSIGNED NULL COMMENT 'linked once the referred customer registers',
  customer_name        VARCHAR(120) NOT NULL,
  gender                ENUM('male','female','other') NULL,
  service_type          ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  duration_start         DATE NOT NULL,
  duration_end            DATE NOT NULL,
  time_from                TIME NOT NULL,
  time_to                   TIME NOT NULL,
  mobile_number             VARCHAR(20) NOT NULL,
  address                    VARCHAR(255) NULL,
  status                     ENUM('pending','booked','completed','cancelled') NOT NULL DEFAULT 'pending',
  created_at                 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (business_partner_id) REFERENCES business_agents(business_partner_id) ON DELETE CASCADE,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- BOOKINGS
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
  booking_id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  display_id           VARCHAR(24) NOT NULL UNIQUE,
  customer_id           INT UNSIGNED NOT NULL,
  service_type           ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  address_id              INT UNSIGNED NULL,
  latitude                DECIMAL(10,7) NULL,
  longitude                DECIMAL(10,7) NULL,
  start_date                DATE NOT NULL,
  end_date                   DATE NOT NULL,
  time_from                    TIME NOT NULL,
  time_to                       TIME NOT NULL,
  gender_preference              ENUM('male','female','other','any') NOT NULL DEFAULT 'any',
  language_preference             VARCHAR(50) NULL,
  referral_code                    VARCHAR(30) NULL,
  status                            ENUM('searching','pending_payment','confirmed','in_progress','completed','cancelled','expired')
                                     NOT NULL DEFAULT 'searching',
  confirmed_provider_id              INT UNSIGNED NULL,
  booking_charge_amount               DECIMAL(8,2) NOT NULL DEFAULT 0,
  booking_charge_paid                  BOOLEAN NOT NULL DEFAULT FALSE,
  booking_charge_txn_id                 BIGINT UNSIGNED NULL,
  payment_deadline_at                    DATETIME NULL COMMENT 'confirmation lapses 15 min after a provider accepts',
  created_at                              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  FOREIGN KEY (address_id) REFERENCES customer_addresses(id),
  FOREIGN KEY (confirmed_provider_id) REFERENCES service_providers(provider_id),
  INDEX idx_bookings_customer (customer_id),
  INDEX idx_bookings_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE booking_requests (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id    BIGINT UNSIGNED NOT NULL,
  provider_id   INT UNSIGNED NOT NULL,
  status        ENUM('pending','accepted','rejected','invalidated','expired') NOT NULL DEFAULT 'pending',
  sent_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responded_at  DATETIME NULL,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id),
  UNIQUE KEY uq_booking_provider (booking_id, provider_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE booking_transfers (
  id               BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id       BIGINT UNSIGNED NOT NULL,
  from_provider_id INT UNSIGNED NOT NULL,
  to_provider_id   INT UNSIGNED NOT NULL,
  status           ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'pending',
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responded_at     DATETIME NULL,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  FOREIGN KEY (from_provider_id) REFERENCES service_providers(provider_id),
  FOREIGN KEY (to_provider_id) REFERENCES service_providers(provider_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE booking_service_sessions (
  id                        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id                BIGINT UNSIGNED NOT NULL,
  provider_id                INT UNSIGNED NOT NULL,
  session_date                 DATE NOT NULL,
  otp_code                       VARCHAR(10) NULL,
  otp_verified_at                 DATETIME NULL,
  facial_recognition_verified      BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'stub — integration point, see docs/api-contract.md',
  start_time_actual                 DATETIME NULL,
  end_time_actual                    DATETIME NULL,
  total_hours                          DECIMAL(5,2) NULL,
  amount                                 DECIMAL(8,2) NULL,
  created_at                             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id),
  UNIQUE KEY uq_booking_session_date (booking_id, session_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE booking_cancellations (
  id                    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id             BIGINT UNSIGNED NOT NULL,
  cancelled_by_type       ENUM('customer','provider','admin') NOT NULL,
  cancelled_by_id           INT UNSIGNED NOT NULL,
  reason                     VARCHAR(500) NULL,
  hours_before_start          DECIMAL(6,2) NOT NULL,
  cancellation_fee_amount       DECIMAL(8,2) NOT NULL DEFAULT 0,
  refund_amount                  DECIMAL(8,2) NOT NULL DEFAULT 0,
  created_at                       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ratings (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id    BIGINT UNSIGNED NOT NULL,
  customer_id   INT UNSIGNED NOT NULL,
  provider_id   INT UNSIGNED NOT NULL,
  rating        TINYINT UNSIGNED NOT NULL COMMENT '1-5',
  comments      VARCHAR(1000) NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id),
  UNIQUE KEY uq_rating_booking (booking_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE provider_location_log (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id   INT UNSIGNED NOT NULL,
  latitude      DECIMAL(10,7) NOT NULL,
  longitude     DECIMAL(10,7) NOT NULL,
  recorded_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (provider_id) REFERENCES service_providers(provider_id) ON DELETE CASCADE,
  INDEX idx_loc_provider_time (provider_id, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- CONFIGURATION & REVENUE SHARING
-- ---------------------------------------------------------------------
CREATE TABLE app_configuration (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  config_key    VARCHAR(100) NOT NULL UNIQUE,
  config_value  VARCHAR(255) NOT NULL,
  description   VARCHAR(255) NULL,
  updated_by    INT UNSIGNED NULL,
  updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- seeded keys: customer_booking_amount, customer_annual_fee_new, customer_annual_fee_existing,
--              provider_annual_fee_new, provider_annual_fee_existing

CREATE TABLE revenue_sharing_config (
  id                              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  service_type                    ENUM('companion','medical_companion','nurse','physiotherapy') NOT NULL,
  customer_rate_per_hour           DECIMAL(8,2) NOT NULL,
  provider_rate_per_hour             DECIMAL(8,2) NOT NULL,
  business_partner_flat_per_hour       DECIMAL(8,2) NOT NULL DEFAULT 0,
  effective_from                         DATE NOT NULL,
  created_at                               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_revshare_service_date (service_type, effective_from)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- BROADCAST MESSAGING
-- ---------------------------------------------------------------------
CREATE TABLE broadcast_messages (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title           VARCHAR(200) NOT NULL,
  message_text    VARCHAR(2000) NOT NULL,
  image_url       VARCHAR(500) NULL,
  target_audience ENUM('customers','providers','both') NOT NULL,
  sent_by         INT UNSIGNED NOT NULL,
  recipient_count INT UNSIGNED NOT NULL DEFAULT 0,
  delivered_count INT UNSIGNED NOT NULL DEFAULT 0,
  sent_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (sent_by) REFERENCES admin_users(admin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- PAYMENTS / TRANSACTIONS (payment-gateway stub — see docs/api-contract.md)
-- ---------------------------------------------------------------------
CREATE TABLE transactions (
  transaction_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaction_type   ENUM('customer_registration','provider_registration','booking_charge',
                           'cancellation_fee','annual_renewal_customer','annual_renewal_provider') NOT NULL,
  reference_type      ENUM('customer','provider','booking') NOT NULL,
  reference_id          BIGINT UNSIGNED NOT NULL,
  amount                  DECIMAL(10,2) NOT NULL,
  currency                 CHAR(3) NOT NULL DEFAULT 'INR',
  gateway                    VARCHAR(50) NULL COMMENT 'e.g. razorpay, stripe — stub',
  gateway_ref_id               VARCHAR(120) NULL,
  status                        ENUM('created','pending','success','failed','refunded') NOT NULL DEFAULT 'created',
  created_at                      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_txn_reference (reference_type, reference_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- NON-FUNCTIONAL: AUDIT LOG
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
  id               BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_type        ENUM('customer','provider','business_agent','admin','system') NOT NULL,
  user_id          INT UNSIGNED NULL,
  user_name        VARCHAR(150) NULL,
  device_id        VARCHAR(255) NULL,
  location_id      VARCHAR(100) NULL COMMENT 'lat,lng or place id captured at time of transaction',
  form_name        VARCHAR(150) NOT NULL,
  action           VARCHAR(100) NOT NULL,
  transaction_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  metadata         JSON NULL,
  INDEX idx_audit_user (user_type, user_id),
  INDEX idx_audit_date (transaction_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE otp_log (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_type     ENUM('customer','provider','business_agent') NOT NULL,
  user_id       INT UNSIGNED NOT NULL,
  purpose       ENUM('login','reset') NOT NULL,
  otp_hash      VARCHAR(255) NOT NULL,
  expires_at    DATETIME NOT NULL,
  verified_at   DATETIME NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_otp_user (user_type, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Call-masking (non-functional requirement): number to be looked up by
-- the backend to bridge Customer <-> Provider calls via a virtual
-- Sathiyaa number rather than exposing either party's real number.
CREATE TABLE masked_call_sessions (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  booking_id    BIGINT UNSIGNED NOT NULL,
  virtual_number VARCHAR(20) NOT NULL,
  expires_at    DATETIME NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;
