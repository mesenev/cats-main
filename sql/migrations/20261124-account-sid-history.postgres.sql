CREATE TABLE account_sid_history (
    sid_hash    CHAR(64) NOT NULL PRIMARY KEY,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    created_at  CATS_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip          VARCHAR(100) DEFAULT ''
);

CREATE INDEX account_sid_history_account_idx
    ON account_sid_history(account_id, created_at);

INSERT INTO account_sid_history (sid_hash, account_id, created_at, ip)
SELECT encode(sha256(sid::bytea), 'hex'), id,
    COALESCE(last_login, CURRENT_TIMESTAMP), last_ip
FROM accounts WHERE sid IS NOT NULL;
