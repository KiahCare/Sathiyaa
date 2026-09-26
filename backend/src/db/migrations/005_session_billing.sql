-- Session-level billing detail needed by the No Fees / Time Bank and
-- organization-fee-markup billing paths added alongside 004: the customer
-- -facing amount for a session can now differ from the provider payout
-- (`amount`), and a session can be fully donated (No Fees).

ALTER TABLE booking_service_sessions
  ADD COLUMN customer_amount DECIMAL(8,2) NULL COMMENT 'what the customer owes for this session (freelancer customer_rate, org fee+markup, or 0 for No Fees) — feeds bookings.amount_due' AFTER amount,
  ADD COLUMN is_no_fees BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'true when this session was donated (provider.no_fees) — points credited to time_bank_ledger instead of billed' AFTER customer_amount;
