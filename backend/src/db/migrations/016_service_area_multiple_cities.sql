-- Gandhinagar joins the service area.
--
-- `service_area_city` held one city because Sathiyaa launched in one. The
-- twin-city case arrived immediately: Gandhinagar is 25 km from Ahmedabad and
-- full of families a carer can reach.
--
-- It was already inside the area *by distance* -- 30 km against a 35 km radius
-- -- so anybody registering there with working location services got in. The
-- gap was the other route: a phone that refuses the location prompt, or gives
-- a bad indoor fix, falls back to the city name, and "Gandhinagar" matched
-- nothing. Those people were turned away from a city we serve.
--
-- The value is now a comma-separated list, and `serviceArea.js` matches any
-- entry in it. A single-city value stays valid, so this changes data and not
-- shape: no column changes, and an older value keeps working.
--
-- Opening a third city is this one row, edited in the console. It is not a
-- deployment.

-- One statement rather than an UPDATE and an INSERT, because `config_key` is
-- UNIQUE. Migration 015 creates this row, so the UPDATE branch is the one that
-- runs on any real database; the INSERT branch covers a database rebuilt in
-- some other order, and keeps this file safe to run twice.
-- The row alias, not the older VALUES() function, which MySQL deprecated in
-- 8.0.20 and warns about on the 8.4 server this runs against.
INSERT INTO app_configuration (config_key, config_value, description)
VALUES ('service_area_city', 'Ahmedabad, Gandhinagar',
        'Cities Sathiyaa operates in, comma separated') AS incoming
ON DUPLICATE KEY UPDATE
  config_value = incoming.config_value,
  description  = incoming.description;
