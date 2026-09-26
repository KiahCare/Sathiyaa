-- What an organisation is, as opposed to a carer.
--
-- The provider table was built around one person: gender, date of birth, an
-- Aadhaar card, a police verification. An agency has none of those. It was
-- registering through the same form and the same columns, which produced rows
-- saying a company was female, born in 1994, and police-verified -- and that
-- last one is not a harmless oddity, because an admin approving the agency
-- would be approving one director's police check on behalf of every carer the
-- agency later adds.
--
-- So: three columns for what an organisation actually has.
--
--   org_registration_url  certificate of incorporation, shops and
--                         establishment licence, society or trust
--                         registration -- whatever it is registered as
--   gst_number            optional; many are below the threshold
--   contact_person        an organisation has no date of birth, but it does
--                         have somebody who answers the phone
--
-- The carers' own documents are unaffected: an org employee is a row in this
-- same table, so aadhar_doc_url and police_verification_url are collected per
-- carer on the screen that adds them.

ALTER TABLE service_providers
  ADD COLUMN org_registration_url VARCHAR(500) NULL
    COMMENT 'organisations only: proof of registration'
    AFTER work_certificate_url,
  ADD COLUMN gst_number VARCHAR(20) NULL
    COMMENT 'organisations only, optional'
    AFTER org_registration_url,
  ADD COLUMN contact_person VARCHAR(150) NULL
    COMMENT 'organisations only: who Sathiyaa speaks to'
    AFTER gst_number;
