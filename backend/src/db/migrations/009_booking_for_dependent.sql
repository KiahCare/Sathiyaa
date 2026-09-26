-- ---------------------------------------------------------------------
-- 009: who the visit is actually for
-- ---------------------------------------------------------------------
--
-- Every booking so far has been implicitly for the person who made it. That is
-- wrong for the commonest case this app exists to serve: an adult child in
-- another city arranging care for a parent. They hold the account, they pay,
-- they get the updates -- and the carer is visiting somebody else entirely.
--
-- Without this the provider arrives asking for the wrong name, and the health
-- record on screen belongs to the wrong person. Both are the kind of mistake
-- that ends a relationship with a family.
--
-- NULL means "for the account holder", which keeps every existing row correct
-- without a backfill.

ALTER TABLE bookings
  ADD COLUMN for_family_member_id BIGINT UNSIGNED NULL
    COMMENT 'customer_family_members.id; NULL means the booking is for the account holder'
    AFTER customer_id;

ALTER TABLE bookings
  ADD CONSTRAINT fk_bookings_for_family_member
    FOREIGN KEY (for_family_member_id) REFERENCES customer_family_members(id)
    ON DELETE SET NULL;

-- The carer needs to know how old the person they are visiting is, and a
-- family member row only had a name, a relationship and a number.
ALTER TABLE customer_family_members
  ADD COLUMN date_of_birth DATE NULL AFTER relationship;

ALTER TABLE customer_family_members
  ADD COLUMN notes VARCHAR(500) NULL
    COMMENT 'anything a visiting carer should know before they knock'
    AFTER contact_number;
