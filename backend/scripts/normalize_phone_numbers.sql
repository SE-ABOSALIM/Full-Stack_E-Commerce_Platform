-- Canonicalize account phone identities before enforcing per-role uniqueness.
-- Run this whole file as one transaction. Any invalid value or normalization
-- collision aborts before data is changed.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.normalize_account_phone(raw_phone text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
    compact text := regexp_replace(raw_phone, '[[:space:]()-]', '', 'g');
BEGIN
    IF compact ~ '^00' THEN
        compact := '+' || substring(compact FROM 3);
    END IF;

    IF compact ~ '^5[0-9]{9}$' THEN
        RETURN '+90' || compact;
    ELSIF compact ~ '^05[0-9]{9}$' THEN
        RETURN '+90' || substring(compact FROM 2);
    ELSIF compact ~ '^\+905[0-9]{9}$' THEN
        RETURN compact;
    ELSIF compact ~ '^\+[1-9][0-9]{7,14}$' THEN
        RETURN compact;
    END IF;

    RETURN NULL;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM users
        WHERE phone_number IS NOT NULL
          AND pg_temp.normalize_account_phone(phone_number) IS NULL
    ) THEN
        RAISE EXCEPTION 'users contains invalid phone numbers';
    END IF;

    IF EXISTS (
        SELECT 1 FROM sellers
        WHERE phone IS NOT NULL
          AND pg_temp.normalize_account_phone(phone) IS NULL
    ) THEN
        RAISE EXCEPTION 'sellers contains invalid phone numbers';
    END IF;

    IF EXISTS (
        SELECT 1 FROM phone_verifications
        WHERE phone_number IS NOT NULL
          AND pg_temp.normalize_account_phone(phone_number) IS NULL
    ) THEN
        RAISE EXCEPTION 'phone_verifications contains invalid phone numbers';
    END IF;

    IF EXISTS (
        SELECT 1 FROM phone_verification_sellers
        WHERE phone_number IS NOT NULL
          AND pg_temp.normalize_account_phone(phone_number) IS NULL
    ) THEN
        RAISE EXCEPTION 'phone_verification_sellers contains invalid phone numbers';
    END IF;

    IF EXISTS (
        SELECT 1 FROM password_reset_verifications
        WHERE phone_number IS NOT NULL
          AND pg_temp.normalize_account_phone(phone_number) IS NULL
    ) THEN
        RAISE EXCEPTION 'password_reset_verifications contains invalid phone numbers';
    END IF;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT pg_temp.normalize_account_phone(phone_number)
        FROM users
        WHERE phone_number IS NOT NULL
        GROUP BY pg_temp.normalize_account_phone(phone_number)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'users contains canonical phone collisions';
    END IF;

    IF EXISTS (
        SELECT pg_temp.normalize_account_phone(phone)
        FROM sellers
        WHERE phone IS NOT NULL
        GROUP BY pg_temp.normalize_account_phone(phone)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'sellers contains canonical phone collisions';
    END IF;

    IF EXISTS (
        SELECT pg_temp.normalize_account_phone(phone_number)
        FROM phone_verifications
        WHERE phone_number IS NOT NULL
        GROUP BY pg_temp.normalize_account_phone(phone_number)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'phone_verifications contains canonical phone collisions';
    END IF;

    IF EXISTS (
        SELECT pg_temp.normalize_account_phone(phone_number)
        FROM phone_verification_sellers
        WHERE phone_number IS NOT NULL
        GROUP BY pg_temp.normalize_account_phone(phone_number)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'phone_verification_sellers contains canonical phone collisions';
    END IF;

    IF EXISTS (
        SELECT pg_temp.normalize_account_phone(phone_number)
        FROM password_reset_verifications
        WHERE phone_number IS NOT NULL
        GROUP BY pg_temp.normalize_account_phone(phone_number)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'password_reset_verifications contains canonical phone collisions';
    END IF;
END;
$$;

UPDATE users
SET phone_number = pg_temp.normalize_account_phone(phone_number)
WHERE phone_number IS NOT NULL
  AND phone_number <> pg_temp.normalize_account_phone(phone_number);

UPDATE sellers
SET phone = pg_temp.normalize_account_phone(phone)
WHERE phone IS NOT NULL
  AND phone <> pg_temp.normalize_account_phone(phone);

UPDATE phone_verifications
SET phone_number = pg_temp.normalize_account_phone(phone_number)
WHERE phone_number IS NOT NULL
  AND phone_number <> pg_temp.normalize_account_phone(phone_number);

UPDATE phone_verification_sellers
SET phone_number = pg_temp.normalize_account_phone(phone_number)
WHERE phone_number IS NOT NULL
  AND phone_number <> pg_temp.normalize_account_phone(phone_number);

UPDATE password_reset_verifications
SET phone_number = pg_temp.normalize_account_phone(phone_number)
WHERE phone_number IS NOT NULL
  AND phone_number <> pg_temp.normalize_account_phone(phone_number);

-- Buyer and seller identities remain separate roles, so uniqueness is scoped
-- to each account table rather than enforced across both tables.
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_number_canonical
    ON users (phone_number);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sellers_phone_canonical
    ON sellers (phone);

COMMIT;
