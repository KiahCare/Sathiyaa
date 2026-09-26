-- Preferred contact modes are a multiple choice, not a single one.
--
-- The profile screen offers Email / Call / SMS as checkboxes and the app sends
-- back whatever is ticked, comma-joined. The column was ENUM('email','call',
-- 'sms'), which accepts exactly one of those strings, so ticking two or three
-- sent 'email,call,sms' into a column that had no such member. MySQL rejected
-- the write and the app reported "something went wrong" -- with the confusing
-- symptom that ticking a single box worked fine.
--
-- SET is the MySQL type for "any combination of these", and it reads and
-- writes the same comma-joined form the app already sends. Existing single
-- values convert across unchanged.
ALTER TABLE customers
  MODIFY COLUMN preferred_comm_mode SET('email','call','sms') NULL;
