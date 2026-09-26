-- Additive migration: the API contract's provider search filter
-- (`GET /providers/search?...&language=`) needs a language field on
-- service_providers, which the base schema does not have (only
-- customers.preferred_languages exists). Additive, non-breaking.
ALTER TABLE service_providers
  ADD COLUMN languages JSON NULL COMMENT 'array of language codes spoken by the provider' AFTER gender;
