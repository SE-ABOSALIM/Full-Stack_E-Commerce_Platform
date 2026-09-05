-- Existing PostgreSQL development DB only. Back up before applying.
-- Run before starting the updated backend. Safe to run again.
BEGIN;

ALTER TABLE address ADD COLUMN IF NOT EXISTS user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE "order" ADD COLUMN IF NOT EXISTS user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS ix_address_user_id ON address(user_id);
CREATE INDEX IF NOT EXISTS ix_order_user_id ON "order"(user_id);

-- Never infer ownership where legacy links disagree or point to a missing user.
UPDATE address AS resource SET user_id = owners.user_id
FROM (
    SELECT address_id, MIN(user_id) AS user_id FROM users_address
    GROUP BY address_id HAVING COUNT(DISTINCT user_id) = 1 AND COUNT(*) = COUNT(user_id)
) AS owners
WHERE resource.id = owners.address_id AND resource.user_id IS NULL
AND EXISTS (SELECT 1 FROM users WHERE id = owners.user_id);

UPDATE "order" AS resource SET user_id = owners.user_id
FROM (
    SELECT order_id, MIN(user_id) AS user_id FROM users_order
    GROUP BY order_id HAVING COUNT(DISTINCT user_id) = 1 AND COUNT(*) = COUNT(user_id)
) AS owners
WHERE resource.id = owners.order_id AND resource.user_id IS NULL
AND EXISTS (SELECT 1 FROM users WHERE id = owners.user_id);

-- Cards already have a direct owner. Only fill missing values, never reassign one.
UPDATE credit_card AS resource SET user_id = owners.user_id
FROM (
    SELECT credit_card_id, MIN(user_id) AS user_id FROM users_credit_card
    GROUP BY credit_card_id HAVING COUNT(DISTINCT user_id) = 1 AND COUNT(*) = COUNT(user_id)
) AS owners
WHERE resource.id = owners.credit_card_id AND resource.user_id IS NULL
AND EXISTS (SELECT 1 FROM users WHERE id = owners.user_id);

CREATE TABLE IF NOT EXISTS password_reset_verifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    phone_number VARCHAR NOT NULL,
    code_hash VARCHAR NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    consumed_at TIMESTAMP
);

-- Legacy follow endpoints used this column via raw SQL, but it was missing from the ORM.
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS followers_count INTEGER NOT NULL DEFAULT 0;
UPDATE sellers SET followers_count = (
    SELECT COUNT(*) FROM users_sellers WHERE seller_id = sellers.id
);

COMMIT;

-- Review these locally: the API deliberately refuses to claim ambiguous/unowned records.
SELECT id FROM address WHERE user_id IS NULL;
SELECT id FROM "order" WHERE user_id IS NULL;
SELECT id FROM credit_card WHERE user_id IS NULL;
SELECT id FROM products WHERE seller_id IS NULL;
