-- =============================================================================
-- schema.sql  –  Reštauračný systém
-- DBS / Databázové technológie  –  Zadanie 3
-- Autori: Dávid Boldog, Tomáš Bubeník
-- =============================================================================

-- Spustenie na čistej PostgreSQL inštancii:
--   psql -U postgres -d restauracia -f schema.sql

-- =============================================================================
-- 0. Čistenie (pre opakované spustenie)
-- =============================================================================

DROP TABLE IF EXISTS Recenzia           CASCADE;
DROP TABLE IF EXISTS Faktura            CASCADE;
DROP TABLE IF EXISTS ObjednavkaPolozka  CASCADE;
DROP TABLE IF EXISTS DeliveryObjednavka CASCADE;
DROP TABLE IF EXISTS DineInObjednavka   CASCADE;
DROP TABLE IF EXISTS Objednavka         CASCADE;
DROP TABLE IF EXISTS Rezervacia         CASCADE;
DROP TABLE IF EXISTS PolozkaMenu        CASCADE;
DROP TABLE IF EXISTS Zakaznik           CASCADE;
DROP TABLE IF EXISTS Zamestnanec        CASCADE;

DROP TYPE IF EXISTS typ_zamestnanca  CASCADE;
DROP TYPE IF EXISTS stav_objednavky  CASCADE;
DROP TYPE IF EXISTS stav_polozky     CASCADE;
DROP TYPE IF EXISTS stav_rezervacie  CASCADE;
DROP TYPE IF EXISTS kategoria_menu   CASCADE;
DROP TYPE IF EXISTS sposob_platby    CASCADE;

-- =============================================================================
-- 1. ENUM typy
-- =============================================================================

CREATE TYPE typ_zamestnanca AS ENUM (
    'casnik',
    'kuchar',
    'kurier',
    'manazer'
);

-- Stavový automat objednávky:
--   nova → pripravuje_sa → hotova → zaplatena   (dine-in)
--   nova → pripravuje_sa → dorucuje_sa → dorucena (delivery)
--   * → zrusena  (zrušenie z ľubovoľného stavu pred dokončením)
CREATE TYPE stav_objednavky AS ENUM (
    'nova',
    'pripravuje_sa',
    'hotova',
    'zaplatena',
    'dorucuje_sa',
    'dorucena',
    'zrusena'
);

-- Individuálny stav každej položky objednávky (sleduje kuchár / čašník)
CREATE TYPE stav_polozky AS ENUM (
    'nova',
    'pripravuje_sa',
    'dorucena',
    'zrusena'
);

CREATE TYPE stav_rezervacie AS ENUM (
    'potvrdena',   -- vytvorená zákazníkom, čaká na príchod
    'aktivna',     -- zákazník prišiel, stôl je obsadený
    'ukoncena',    -- zákazník odišiel
    'zrusena'      -- rezervácia zrušená
);

CREATE TYPE kategoria_menu AS ENUM (
    'jedlo',
    'napoj',
    'dezert'
);

CREATE TYPE sposob_platby AS ENUM (
    'hotovost',
    'karta',
    'online'
);

-- =============================================================================
-- 2. Tabuľky
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 2.1  Zamestnanec
--      Všetci pracovníci reštaurácie (čašník, kuchár, kuriér, manažér).
--      Rola je atribút – nie samostatné tabuľky.
-- -----------------------------------------------------------------------------
CREATE TABLE Zamestnanec (
    id                 SERIAL          PRIMARY KEY,
    meno               VARCHAR(50)     NOT NULL,
    priezvisko         VARCHAR(50)     NOT NULL,
    typ                typ_zamestnanca NOT NULL,
    hodinova_mzda      DECIMAL(8,2)    NOT NULL CHECK (hodinova_mzda > 0),
    odpracovany_cas    DECIMAL(8,2)    NOT NULL DEFAULT 0
                                       CHECK (odpracovany_cas >= 0),
    email              VARCHAR(100)    NOT NULL UNIQUE,
    tel                VARCHAR(20)     NOT NULL UNIQUE,
    heslo              VARCHAR(64)     NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2.2  Zakaznik
--      Registrovaný zákazník – potrebný pre delivery a rezervácie.
-- -----------------------------------------------------------------------------
CREATE TABLE Zakaznik (
    id         SERIAL       PRIMARY KEY,
    meno       VARCHAR(50)  NOT NULL,
    priezvisko VARCHAR(50)  NOT NULL,
    email      VARCHAR(100) NOT NULL UNIQUE,
    tel        VARCHAR(20)  NOT NULL UNIQUE,
    heslo      VARCHAR(64)  NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2.3  PolozkaMenu
--      Ponuka reštaurácie. aktualna_cena je vždy aktuálna;
--      historická cena sa snímkuje do ObjednavkaPolozka.cena_v_case_objednavky.
-- -----------------------------------------------------------------------------
CREATE TABLE PolozkaMenu (
    id            SERIAL        PRIMARY KEY,
    nazov         VARCHAR(100)  NOT NULL,
    popis         TEXT,
    aktualna_cena DECIMAL(8,2)  NOT NULL CHECK (aktualna_cena > 0),
    kategoria     kategoria_menu NOT NULL,
    je_dostupna   BOOLEAN       NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- 2.4  Objednavka
--      Centrálna entita. Každá objednávka (dine-in aj delivery) má tu 1 riadok.
--      Typ sa rozlišuje existenciou záznamu v DineInObjednavka / DeliveryObjednavka.
-- -----------------------------------------------------------------------------
CREATE TABLE Objednavka (
    id              SERIAL           PRIMARY KEY,
    stav            stav_objednavky  NOT NULL DEFAULT 'nova',
    cas_vytvorenia  TIMESTAMP        NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 2.5  DineInObjednavka
--      Špecializácia pre objednávky pri stole.
--      Zdieľa PK s Objednavka (1:1).
-- -----------------------------------------------------------------------------
CREATE TABLE DineInObjednavka (
    id           INT  PRIMARY KEY
                      REFERENCES Objednavka(id) ON DELETE CASCADE,
    id_zakaznika INT  REFERENCES Zakaznik(id)    ON DELETE RESTRICT,
    cislo_stola  INT  NOT NULL,
    id_casnika   INT  REFERENCES Zamestnanec(id)  ON DELETE SET NULL
);

-- -----------------------------------------------------------------------------
-- 2.6  DeliveryObjednavka
--      Špecializácia pre donáškové objednávky.
--      id_kuriera je NULL až do pridelenia kuriéra.
-- -----------------------------------------------------------------------------
CREATE TABLE DeliveryObjednavka (
    id           INT          PRIMARY KEY
                               REFERENCES Objednavka(id) ON DELETE CASCADE,
    id_zakaznika INT          NOT NULL
                               REFERENCES Zakaznik(id)   ON DELETE RESTRICT,
    id_kuriera   INT          REFERENCES Zamestnanec(id)  ON DELETE SET NULL,
    mesto        VARCHAR(100) NOT NULL,
    ulica        VARCHAR(100) NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2.7  ObjednavkaPolozka
--      Realizuje M:N medzi Objednavka a PolozkaMenu.
--      Ukladá snímku ceny a individuálny stav každej položky.
-- -----------------------------------------------------------------------------
CREATE TABLE ObjednavkaPolozka (
    id                        SERIAL         PRIMARY KEY,
    id_objednavky             INT            NOT NULL
                                              REFERENCES Objednavka(id)  ON DELETE CASCADE,
    id_polozky                INT            NOT NULL
                                              REFERENCES PolozkaMenu(id) ON DELETE RESTRICT,
    mnozstvo                  INT            NOT NULL CHECK (mnozstvo > 0),
    stav                      stav_polozky   NOT NULL DEFAULT 'nova',
    cena_v_case_objednavky    DECIMAL(8,2)   NOT NULL
                                              CHECK (cena_v_case_objednavky > 0)
);

-- -----------------------------------------------------------------------------
-- 2.8  Rezervacia
--      Rezervácia stola na časový interval. Prekrývania sa kontrolujú
--      v operačnom procese pomocou dotazu (SQL CHECK neumožňuje medziriadkové
--      porovnania, preto je kontrola implementovaná v SQL transakčnom bloku).
-- -----------------------------------------------------------------------------
CREATE TABLE Rezervacia (
    id            SERIAL          PRIMARY KEY,
    id_zakaznika  INT             REFERENCES Zakaznik(id) ON DELETE SET NULL,
    cislo_stola   INT             NOT NULL,
    datum         DATE            NOT NULL,
    cas_zaciatku  TIME            NOT NULL,
    cas_konca     TIME            NOT NULL,
    pocet_osob    INT             NOT NULL CHECK (pocet_osob > 0),
    stav          stav_rezervacie NOT NULL DEFAULT 'potvrdena',

    -- Koniec rezervácie musí byť po jej začiatku
    CONSTRAINT ck_rezervacia_cas CHECK (cas_konca > cas_zaciatku)
);

-- -----------------------------------------------------------------------------
-- 2.9  Faktura
--      Platobný doklad ku konkrétnej objednávke (1:1 s Objednavka).
--      UNIQUE na id_objednavky zabraňuje dvom faktúram pre tú istú objednávku.
-- -----------------------------------------------------------------------------
CREATE TABLE Faktura (
    id             SERIAL        PRIMARY KEY,
    id_objednavky  INT           NOT NULL UNIQUE
                                  REFERENCES Objednavka(id) ON DELETE RESTRICT,
    je_zaplatena   BOOLEAN       NOT NULL DEFAULT FALSE,
    sposob_platby  sposob_platby NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2.10 Recenzia
--      Hodnotenie zákazníka po dokončení objednávky (1:1 s Objednavka).
--      UNIQUE na id_objednavky zabraňuje viacnásobnému hodnoteniu.
-- -----------------------------------------------------------------------------
CREATE TABLE Recenzia (
    id             SERIAL    PRIMARY KEY,
    id_objednavky  INT       NOT NULL UNIQUE
                              REFERENCES Objednavka(id) ON DELETE RESTRICT,
    hodnotenie     INT       NOT NULL CHECK (hodnotenie BETWEEN 1 AND 5),
    komentar       TEXT,
    cas            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- 3. Indexy (nad rámec PK a UNIQUE – pre procesy definované v queries.sql)
-- =============================================================================

-- Proces 1 (operačný) – overenie aktívnej rezervácie pre stôl a dátum
CREATE INDEX idx_rezervacia_stol_datum
    ON Rezervacia (cislo_stola, datum, stav);

-- Proces 1 – validácia, či je položka dostupná (filtrovanie menu)
CREATE INDEX idx_polozka_dostupna
    ON PolozkaMenu (je_dostupna);

-- Proces 1 + Proces 2 – načítanie položiek konkrétnej objednávky
CREATE INDEX idx_objednavkapolozka_objednavka
    ON ObjednavkaPolozka (id_objednavky);

-- Proces 2 (analytický) – agregácia tržieb podľa dátumu vytvorenia objednávky
CREATE INDEX idx_objednavka_cas_vytvorenia
    ON Objednavka (cas_vytvorenia);

-- Proces 2 – join Faktura → Objednavka pri filtrovaní zaplatených objednávok
CREATE INDEX idx_faktura_zaplatena
    ON Faktura (je_zaplatena);

-- =============================================================================
-- Koniec schema.sql
-- =============================================================================