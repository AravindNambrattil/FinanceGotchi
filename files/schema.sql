PRAGMA foreign_keys = ON;

-- One row per physical/virtual pet
CREATE TABLE IF NOT EXISTS pets (
    id             TEXT PRIMARY KEY,               -- 'mochi'
    name           TEXT NOT NULL,
    mood           INTEGER NOT NULL DEFAULT 80 CHECK (mood BETWEEN 0 AND 100),
    needs          INTEGER NOT NULL DEFAULT 80 CHECK (needs BETWEEN 0 AND 100),
    energy         INTEGER NOT NULL DEFAULT 80 CHECK (energy BETWEEN 0 AND 100),
    savings_score  INTEGER NOT NULL DEFAULT 50 CHECK (savings_score BETWEEN 0 AND 100),
    streak_days    INTEGER NOT NULL DEFAULT 0,
    last_save_date TEXT,                           -- YYYY-MM-DD, for streaks
    connected      INTEGER NOT NULL DEFAULT 0,     -- BLE status (0/1)
    last_sync      TEXT,
    -- Nessie links
    nessie_customer_id  TEXT,
    nessie_checking_id  TEXT,
    nessie_savings_id   TEXT,
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Long-term goals (one 'custom' + one 'emergency' per pet)
CREATE TABLE IF NOT EXISTS goals (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id     TEXT NOT NULL REFERENCES pets(id),
    kind       TEXT NOT NULL DEFAULT 'custom' CHECK (kind IN ('custom','emergency')),
    name       TEXT NOT NULL,                      -- 'Laptop'
    current    REAL NOT NULL DEFAULT 0,
    target     REAL NOT NULL,
    status     TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','done')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- "Mochi wants new headphones" prompts shown on the phone
CREATE TABLE IF NOT EXISTS offers (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id    TEXT NOT NULL REFERENCES pets(id),
    title     TEXT NOT NULL,
    cost      REAL NOT NULL,
    category  TEXT NOT NULL CHECK (category IN ('essential','want')),
    status    TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','resolved','later')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Every user choice + the effect it had (powers History screen)
CREATE TABLE IF NOT EXISTS decisions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id      TEXT NOT NULL REFERENCES pets(id),
    offer_id    INTEGER REFERENCES offers(id),
    choice      TEXT NOT NULL CHECK (choice IN ('buy','save','later')),
    amount      REAL NOT NULL DEFAULT 0,
    mood_delta     INTEGER NOT NULL DEFAULT 0,
    needs_delta    INTEGER NOT NULL DEFAULT 0,
    savings_delta  INTEGER NOT NULL DEFAULT 0,
    message     TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Unexpected expenses (bike repair etc.)
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id      TEXT NOT NULL REFERENCES pets(id),
    title       TEXT NOT NULL,
    amount      REAL NOT NULL,
    covered     INTEGER NOT NULL DEFAULT 0,        -- emergency fund covered it?
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Local mirror of Nessie activity (Recent activity list + offline demo fallback)
CREATE TABLE IF NOT EXISTS transactions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id      TEXT NOT NULL REFERENCES pets(id),
    nessie_id   TEXT,                              -- id returned by Nessie
    category    TEXT NOT NULL,                     -- groceries, dining, savings...
    amount      REAL NOT NULL,                     -- negative = spent, positive = saved/deposit
    description TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Money we've actually posted to Nessie. Nessie's sandbox records transactions but never
-- updates account balances, so balance = Nessie's starting balance + the sum of this table.
CREATE TABLE IF NOT EXISTS ledger (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id      TEXT NOT NULL REFERENCES pets(id),
    account     TEXT NOT NULL CHECK (account IN ('checking','savings')),
    amount      REAL NOT NULL,                     -- negative = money out, positive = money in
    nessie_id   TEXT,
    description TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Bonus: two-pet meetings
CREATE TABLE IF NOT EXISTS encounters (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    pet_id       TEXT NOT NULL REFERENCES pets(id),
    other_pet_id TEXT NOT NULL,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_decisions_pet ON decisions(pet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_pet        ON transactions(pet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offers_pet    ON offers(pet_id, status);
