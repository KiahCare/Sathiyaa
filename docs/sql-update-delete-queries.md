# SQL — Update / Delete queries for the Customer health-profile sections

Covers the five sections the Customer App tracks on a customer's profile:
**Vitals, Medications, Surgery history, Allergies, Family (Relatives)**.

Every add, update, and delete on these tables is traced two ways:

1. **Row-level** — each table now carries `created_at`, `updated_at`
   (auto-set `ON UPDATE CURRENT_TIMESTAMP`), and `deleted_at` (soft delete —
   see below).
2. **Transaction-level** — every mutation also writes one row to the shared
   `audit_log` table, which is where **device id, user name, and the
   date/time stamp** the requirement asks for actually live (`deleted_at`
   only proves *that* a row was removed and *when*; `audit_log` proves *who*,
   from *which device*, and *what form/action*).

```sql
CREATE TABLE audit_log (
  id               BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_type        ENUM('customer','provider','business_agent','admin','system') NOT NULL,
  user_id          INT UNSIGNED NULL,
  user_name        VARCHAR(150) NULL,
  device_id        VARCHAR(255) NULL,
  location_id      VARCHAR(100) NULL,
  form_name        VARCHAR(150) NOT NULL,
  action           VARCHAR(100) NOT NULL,   -- CREATE | UPDATE | DELETE | ...
  transaction_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  metadata         JSON NULL,
  INDEX idx_audit_user (user_type, user_id),
  INDEX idx_audit_date (transaction_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Every controller in `backend/src/controllers/customerController.js` calls
`req.audit(formName, action, metadata)` right after the UPDATE/DELETE
succeeds (see `backend/src/middleware/audit.js`). `req.audit` reads
`user_name`/`user_id` from the authenticated JWT, and `device_id` /
`location_id` from the `X-Device-Id` / `X-Location` request headers the app
sends on every call — so the SQL below is always paired with an
`INSERT INTO audit_log ...` in the same request. The `INSERT` pattern is
identical for all five sections, so it's shown once at the end rather than
repeated per table.

**Soft delete.** All five tables use `deleted_at DATETIME NULL` instead of
`DELETE FROM ...`. A "deleted" row is kept — with its full history — and
simply excluded from the customer's active list (`WHERE ... AND deleted_at
IS NULL`). This is what lets the audit trail prove a record existed and was
later removed, by whom, and when — a hard `DELETE` would destroy exactly
the evidence the traceability requirement asks for. Family members are the
one section with a business rule on top: a customer must always have at
least one **active** family member, so the delete first checks the live
(non-deleted) count.

Migration: `backend/src/db/migrations/003_profile_sections_audit.sql`.
Master schema: `docs/schema.sql`.

---

## 1. Vitals (`customer_vitals`)

**Update** — `PUT /api/v1/customers/me/vitals/:id`

```sql
UPDATE customer_vitals
SET value_primary = ?, value_secondary = ?, recorded_at = ?
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```
Only the fields actually sent are included in the `SET` clause (partial
update); `vital_type` can also be corrected the same way. `updated_at`
refreshes automatically (`ON UPDATE CURRENT_TIMESTAMP`).

**Delete (soft)** — `DELETE /api/v1/customers/me/vitals/:id`

```sql
UPDATE customer_vitals
SET deleted_at = NOW()
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Active list** (used by the Add/Edit/Delete screen and the trend chart):

```sql
SELECT * FROM customer_vitals
WHERE customer_id = ? AND deleted_at IS NULL
ORDER BY recorded_at ASC;
```

---

## 2. Medications (`customer_medications`)

**Update** — `PUT /api/v1/customers/me/medications/:id`

```sql
UPDATE customer_medications
SET medicine_name = ?, frequency = ?, prescription_url = ?, active = ?
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Delete (soft)** — `DELETE /api/v1/customers/me/medications/:id`

```sql
UPDATE customer_medications
SET deleted_at = NOW()
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Active list:**

```sql
SELECT * FROM customer_medications
WHERE customer_id = ? AND deleted_at IS NULL
ORDER BY created_at DESC;
```

---

## 3. Surgery history (`customer_surgeries`)

**Update** — `PUT /api/v1/customers/me/surgeries/:id`

```sql
UPDATE customer_surgeries
SET surgery_name = ?, surgery_date = ?
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Delete (soft)** — `DELETE /api/v1/customers/me/surgeries/:id`

```sql
UPDATE customer_surgeries
SET deleted_at = NOW()
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Active list:**

```sql
SELECT * FROM customer_surgeries
WHERE customer_id = ? AND deleted_at IS NULL
ORDER BY surgery_date DESC;
```

---

## 4. Allergies (`customer_allergies`)

**Update** — `PUT /api/v1/customers/me/allergies/:id`

```sql
UPDATE customer_allergies
SET allergy_name = ?, onset_date = ?, status = ?
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Delete (soft)** — `DELETE /api/v1/customers/me/allergies/:id`

```sql
UPDATE customer_allergies
SET deleted_at = NOW()
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Active list:**

```sql
SELECT * FROM customer_allergies
WHERE customer_id = ? AND deleted_at IS NULL
ORDER BY created_at DESC;
```

---

## 5. Family / Relatives (`customer_family_members`)

**Update** — `PUT /api/v1/customers/me/family/:id`

```sql
UPDATE customer_family_members
SET name = ?, relationship = ?, contact_number = ?
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Delete (soft, with the minimum-1-member rule)** —
`DELETE /api/v1/customers/me/family/:id`

```sql
-- 1. Count only the LIVE (non-deleted) family members first
SELECT COUNT(*) AS c FROM customer_family_members
WHERE customer_id = ? AND deleted_at IS NULL;
-- if c <= 1, reject the delete (MIN_FAMILY_MEMBER) and stop here

-- 2. Otherwise soft-delete the row
UPDATE customer_family_members
SET deleted_at = NOW()
WHERE id = ? AND customer_id = ? AND deleted_at IS NULL;
```

**Active list:**

```sql
SELECT * FROM customer_family_members
WHERE customer_id = ? AND deleted_at IS NULL
ORDER BY created_at ASC;
```

---

## Audit trail insert (identical shape for all five sections)

Written automatically by `req.audit(formName, action, metadata)` right
after the `UPDATE` above succeeds — never hand-written per controller:

```sql
INSERT INTO audit_log
  (user_type, user_id, user_name, device_id, location_id, form_name, action, metadata)
VALUES
  (?, ?, ?, ?, ?, ?, ?, ?);
-- user_type/user_id/user_name  <- from the customer's JWT session
-- device_id                    <- 'X-Device-Id' request header
-- location_id                  <- 'X-Location' request header (lat,lng)
-- form_name                    <- 'CustomerVitals' | 'CustomerMedications' |
--                                  'CustomerSurgeries' | 'CustomerAllergies' |
--                                  'CustomerFamily'
-- action                       <- 'CREATE' | 'UPDATE' | 'DELETE'
-- transaction_date             <- defaults to NOW(), i.e. the date & time stamp
```

Sample rows produced by a create → update → delete cycle on one vitals
reading (captured while verifying this build):

| user_name  | device_id     | form_name       | action | transaction_date     |
|------------|---------------|------------------|--------|-----------------------|
| Test Audit | WEB-TESTDEV1  | CustomerVitals   | CREATE | 2026-08-31 15:00:13   |
| Test Audit | WEB-TESTDEV1  | CustomerVitals   | UPDATE | 2026-08-31 15:00:13   |
| Test Audit | WEB-TESTDEV1  | CustomerVitals   | DELETE | 2026-08-31 15:00:13   |

To see everything filed against one customer:

```sql
SELECT user_name, device_id, form_name, action, transaction_date
FROM audit_log
WHERE user_type = 'customer' AND user_id = ?
ORDER BY id ASC;
```

---

## REST endpoints added

| Section     | Add                          | Edit                              | Delete                             |
|-------------|-------------------------------|-------------------------------------|--------------------------------------|
| Vitals      | `POST /customers/me/vitals`      | `PUT /customers/me/vitals/:id`      | `DELETE /customers/me/vitals/:id`      |
| Medications | `POST /customers/me/medications` | `PUT /customers/me/medications/:id` | `DELETE /customers/me/medications/:id` |
| Surgery     | `POST /customers/me/surgeries`   | `PUT /customers/me/surgeries/:id`   | `DELETE /customers/me/surgeries/:id`   |
| Allergies   | `POST /customers/me/allergies`   | `PUT /customers/me/allergies/:id`   | `DELETE /customers/me/allergies/:id`   |
| Family      | `POST /customers/me/family`      | `PUT /customers/me/family/:id`      | `DELETE /customers/me/family/:id`      |

All under `/api/v1`, all requiring `Authorization: Bearer <customer JWT>` and
sending `X-Device-Id` (and, where available, `X-Location`) on every call so
the audit row is complete. `PUT` bodies accept any subset of the entity's
fields (partial update). `POST`/`PUT`/`DELETE` on Medications, Surgery,
Allergies, and Family were newly added in this update — Vitals previously
had neither edit nor delete at all.
