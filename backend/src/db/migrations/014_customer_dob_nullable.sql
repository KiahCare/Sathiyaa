-- "Unknown" is not 1 January 1970.
--
-- customers.dob and customers.gender were NOT NULL, and registration only
-- collects a name and a mobile number, so the INSERT had to put something in
-- them. It put '1970-01-01' and 'other'. Those are not placeholders once they
-- are in the table -- they are data. The app read them back and pre-filled
-- the Basic Details form with a date of birth of 1 Jan 1970 and an age of 56,
-- for every customer who had never entered one, and the form had no way to
-- tell that apart from somebody genuinely born in 1970.
--
-- photo_url has the same shape of problem: NOT NULL, filled with '', so
-- "has no photo" and "has a photo stored as an empty string" are the same row.
--
-- Making all three nullable lets the absence of an answer be recorded as an
-- absence. The app already treats null as "not set" -- that is what the
-- required-field markers on the profile are for.

ALTER TABLE customers
  MODIFY COLUMN dob DATE NULL,
  MODIFY COLUMN gender ENUM('male','female','other') NULL,
  MODIFY COLUMN photo_url VARCHAR(500) NULL;

-- Clear the sentinels already written by earlier registrations. Anyone who
-- genuinely entered 1 Jan 1970 would have done it through the profile form,
-- which also sets gender and a photo -- so the three-way match is what
-- identifies a row nobody ever filled in.
UPDATE customers
   SET dob = NULL
 WHERE dob = '1970-01-01'
   AND gender = 'other'
   AND (photo_url IS NULL OR photo_url = '');

UPDATE customers
   SET gender = NULL
 WHERE dob IS NULL
   AND gender = 'other'
   AND (photo_url IS NULL OR photo_url = '');

UPDATE customers SET photo_url = NULL WHERE photo_url = '';
