-- Adds edit/delete traceability to the five customer health-profile
-- sections (Vitals, Medications, Surgeries, Allergies, Family members).
--
-- Every add/edit/delete on these tables is already written to the generic
-- `audit_log` table via req.audit(...) (see backend/src/middleware/audit.js)
-- -- that table already carries user_name, device_id, location_id and
-- transaction_date for every action. This migration adds the row-level
-- columns needed so each record itself also tracks when it was last
-- updated, and supports non-destructive ("soft") delete so a deleted
-- health record's history is never actually lost -- it is just excluded
-- from the customer's active view.

ALTER TABLE customer_vitals
  ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at,
  ADD COLUMN deleted_at DATETIME NULL AFTER updated_at;

ALTER TABLE customer_medications
  ADD COLUMN deleted_at DATETIME NULL AFTER updated_at;

ALTER TABLE customer_surgeries
  ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at,
  ADD COLUMN deleted_at DATETIME NULL AFTER updated_at;

ALTER TABLE customer_allergies
  ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at,
  ADD COLUMN deleted_at DATETIME NULL AFTER updated_at;

ALTER TABLE customer_family_members
  ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at,
  ADD COLUMN deleted_at DATETIME NULL AFTER updated_at;

-- Existing indexes were written assuming every row is live; add deleted_at
-- to the vitals lookup index so filtered list queries stay index-covered.
ALTER TABLE customer_vitals
  DROP INDEX idx_vitals_customer_type_date,
  ADD INDEX idx_vitals_customer_type_date (customer_id, vital_type, recorded_at, deleted_at);
