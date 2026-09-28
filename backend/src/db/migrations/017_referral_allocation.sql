-- Remember which carer a referral was allocated to.
--
-- `POST /admin/business-agents/referrals/:id/allocate` picks a matching carer,
-- sets the referral to 'booked', returns that carer's name -- and stores
-- nothing. The name went back in one HTTP response and was gone. Reopen the
-- partner a minute later and the referral says 'booked' with no way to find out
-- who was sent, which is the first question anybody asks about a referral.
--
-- Reported by the client as "where do I check their allocation". The allocation
-- was not hidden; it was never written down.
--
-- Nullable because every existing row predates this and genuinely has no
-- allocation. ON DELETE SET NULL rather than CASCADE: deleting a carer's
-- account must not delete the partner's referral, which is a separate business
-- record and the basis of what that partner gets paid.

ALTER TABLE business_agent_referrals
  ADD COLUMN allocated_provider_id INT UNSIGNED NULL
    COMMENT 'the carer this referral was allocated to, once an admin allocates it'
    AFTER customer_id,
  ADD COLUMN allocated_at DATETIME NULL
    COMMENT 'when the allocation happened'
    AFTER allocated_provider_id,
  ADD COLUMN allocated_by INT UNSIGNED NULL
    COMMENT 'the admin who allocated it'
    AFTER allocated_at;

ALTER TABLE business_agent_referrals
  ADD CONSTRAINT fk_referral_allocated_provider
    FOREIGN KEY (allocated_provider_id) REFERENCES service_providers(provider_id)
    ON DELETE SET NULL;

-- The partner detail view filters by partner and reads the allocation, and the
-- admin referral queue will want "everything still unallocated" across all
-- partners.
CREATE INDEX idx_referral_allocation
  ON business_agent_referrals (status, allocated_provider_id);
