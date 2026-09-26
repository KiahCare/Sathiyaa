-- Where somebody signed up from, and where Sathiyaa actually operates.
--
-- Sathiyaa launches in Ahmedabad. Nothing in the product said so: anybody
-- anywhere could register, search, find nobody, and conclude the app was
-- broken. Worse, the fact that they tried was lost -- which is the single
-- most useful number a business launching city by city can have.
--
-- Two halves.
--
-- 1. THE SERVICE AREA, in app_configuration rather than in the APK. A city is
--    a business decision that changes faster than an app release, and having
--    it here means opening Surat is a number typed into the admin console
--    instead of a new build sitting in Play Store review for three days.
--
-- 2. WHERE EACH SIGN-UP CAME FROM, on the row itself. Not the address they
--    later type -- the coordinates their phone reported the day they
--    registered, reverse-geocoded to a city. Somebody in Rajkot who registers
--    and is turned away is a row that says "Rajkot, outside", and fifty of
--    those rows are the case for opening Rajkot.
--
-- Deliberately NOT a foreign key to a cities table. The city is whatever the
-- geocoder said, including spellings we have never seen, and normalising that
-- into a reference table would mean dropping the rows that do not fit -- which
-- are exactly the interesting ones.

ALTER TABLE customers
  ADD COLUMN signup_latitude  DECIMAL(10,7) NULL COMMENT 'where the phone was when they registered',
  ADD COLUMN signup_longitude DECIMAL(10,7) NULL,
  ADD COLUMN signup_city      VARCHAR(100) NULL COMMENT 'reverse-geocoded, as the geocoder spelled it',
  ADD COLUMN signup_state     VARCHAR(100) NULL,
  ADD COLUMN signup_pincode   VARCHAR(12) NULL,
  ADD COLUMN signup_in_service_area BOOLEAN NULL COMMENT 'NULL = never asked or refused; the server decides this, not the app',
  ADD COLUMN signup_place_at  DATETIME NULL;

ALTER TABLE service_providers
  ADD COLUMN signup_latitude  DECIMAL(10,7) NULL,
  ADD COLUMN signup_longitude DECIMAL(10,7) NULL,
  ADD COLUMN signup_city      VARCHAR(100) NULL,
  ADD COLUMN signup_state     VARCHAR(100) NULL,
  ADD COLUMN signup_pincode   VARCHAR(12) NULL,
  ADD COLUMN signup_in_service_area BOOLEAN NULL,
  ADD COLUMN signup_place_at  DATETIME NULL;

-- Whether a carer has actually answered the language question, as opposed to
-- sitting on the English-only default nobody chose.
--
-- The picker came off the registration form -- every field there costs
-- somebody halfway through -- so the profile screen asks instead, and it has
-- to know when to stop asking. Without this, somebody who genuinely speaks
-- only English would be nagged forever, because "English only" and "never
-- answered" are the same list.
ALTER TABLE service_providers
  ADD COLUMN languages_confirmed_at DATETIME NULL COMMENT 'set the first time the carer saves their own languages';

ALTER TABLE customers ADD INDEX idx_customers_signup_city (signup_city);
ALTER TABLE service_providers ADD INDEX idx_providers_signup_city (signup_city);

-- The launch city. Centre is Bhadra Fort, near enough the middle of the old
-- city; 35 km reaches Gandhinagar, Sanand and the SG Highway sprawl, all of
-- which are a reasonable drive for a carer and all of which people would call
-- "Ahmedabad" when asked.
--
-- The radius is generous on purpose. Turning away somebody who is genuinely
-- in the catchment costs a customer for good. Letting in somebody thirty
-- kilometres out costs one search that finds nobody nearby.
-- ON DUPLICATE KEY UPDATE, not a plain INSERT: re-running migrations must not
-- move the service area back to Ahmedabad after somebody has opened Surat
-- from the console. Assigning the key to itself is the no-op that says
-- "leave whatever is already there alone".
INSERT INTO app_configuration (config_key, config_value, description) VALUES
  ('service_area_enabled', 'true', 'Whether registration is restricted to the launch city at all'),
  ('service_area_city', 'Ahmedabad', 'The city Sathiyaa currently operates in'),
  ('service_area_state', 'Gujarat', 'Its state, used when the geocoder gives no city'),
  ('service_area_lat', '23.0225', 'Centre of the service area'),
  ('service_area_lng', '72.5714', 'Centre of the service area'),
  ('service_area_radius_km', '35', 'How far from that centre still counts as inside')
ON DUPLICATE KEY UPDATE config_key = config_key;
