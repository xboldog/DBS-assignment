-- =============================================================================
-- queries.sql  -  Restauracny system
-- DBS / Databazove technologie  -  Zadanie 3
-- Autori: David Boldog, Tomas Bubenik
-- =============================================================================
-- Obsah:
--   PROCES 1  - Vytvorenie dine-in objednavky       (operacny / transakny)
--   PROCES 2  - Vykonnostny report casnikov          (analyticky)
-- =============================================================================


-- =============================================================================
-- KONFIGURACNE PARAMETRE  (obdoba #define v C)
-- Upravte hodnoty tu - zvysok suboru sa nemeni.
-- =============================================================================

-- ── Proces 1 ─────────────────────────────────────────────────────────────────

-- Cislo stola pre ktory sa vytvara objednavka (1-20)
SET myapp.p_cislo_stola  = '3';

-- ID zakaznika ktory objednava
SET myapp.p_id_zakaznika = '1';

-- ID casnika ktory obsluhuje (0 = automaticky vyber prveho dostupneho casnika)
SET myapp.p_id_casnika   = '0';

-- Datum a cas pre ktory sa hlada aktivna rezervacia.
-- Prazdny retazec = automaticky najdi aktivnu rezervaciu pre dany stol v seede.
-- Priklad rucneho zadania: SET myapp.p_datum = '2024-06-15';
SET myapp.p_datum = '';
SET myapp.p_cas   = '';

-- Polozky ktore zakaznik objednava - format: 'id:mnozstvo,id:mnozstvo,...'
-- Priklad: '2:2,7:1,3:1' znamena polozka 2 (qty 2), polozka 7 (qty 1), polozka 3 (qty 1)
-- '0' = automaticky vyber prve 3 dostupne polozky z menu
SET myapp.p_polozky = '0';

-- ── Proces 2 ─────────────────────────────────────────────────────────────────

-- Rok pre ktory sa generuje report casnikov
SET myapp.p_rok = '2024';


-- =============================================================================
-- ZDIELANE VIEWS (pouzivane v oboch procesoch)
-- =============================================================================

-- Dostupne polozky menu
CREATE OR REPLACE VIEW v_dostupne_polozky AS
SELECT id, nazov, aktualna_cena, kategoria
FROM   PolozkaMenu
WHERE  je_dostupna = TRUE;

-- Aktivne rezervacie pre zadany datum a casove okno
-- (datum a cas sa dosadzuju z parametrov v ramci DO bloku)
CREATE OR REPLACE VIEW v_aktivne_stoly AS
SELECT DISTINCT
    r.cislo_stola,
    r.id           AS id_rezervacie,
    r.datum,
    r.cas_zaciatku,
    r.cas_konca
FROM Rezervacia r
WHERE r.stav = 'aktivna';


-- =============================================================================
-- PROCES 1: Vytvorenie dine-in objednavky
-- =============================================================================
--
-- Popis:
--   Zakaznik si pri stole objedna jedla. Pred samotnym INSERTom system overi:
--     (1) ze pre dany stol existuje aktivna rezervacia v zadanom case
--         -> tabulka Rezervacia
--     (2) ze vsetky objednavane polozky su dostupne
--         -> tabulka PolozkaMenu
--   Vsetky chyby su hlasene cez RAISE NOTICE - proces nespadne,
--   len vypise co je zle a skonci bez vytvorenia objednavky.
--
-- Tabulky (5):
--   Rezervacia, PolozkaMenu, Objednavka, DineInObjednavka, ObjednavkaPolozka
-- =============================================================================

DO $$
DECLARE
    -- Nacitanie konfiguracnych parametrov
    p_cislo_stola    INT     := current_setting('myapp.p_cislo_stola')::INT;
    p_id_zakaznika   INT     := current_setting('myapp.p_id_zakaznika')::INT;
    p_id_casnika     INT     := current_setting('myapp.p_id_casnika')::INT;
    p_pol1           INT     := current_setting('myapp.p_pol1')::INT;
    p_pol2           INT     := current_setting('myapp.p_pol2')::INT;
    p_datum_str      TEXT    := current_setting('myapp.p_datum');
    p_cas_str        TEXT    := current_setting('myapp.p_cas');

    -- Interne premenne
    v_datum          DATE;
    v_cas            TIME;
    v_id_objednavky  INT;
    v_rez            RECORD;
    v_pol1_nazov     TEXT;
    v_pol2_nazov     TEXT;
    v_casnik_nazov   TEXT;
BEGIN

    -- ── Krok 1: Resolved datum a cas ─────────────────────────────────────────
    -- Ak su parametre prazdne, automaticky najdi aktivnu rezervaciu pre stol
    IF p_datum_str = '' THEN
        SELECT r.datum, r.cas_zaciatku
        INTO   v_datum, v_cas
        FROM   Rezervacia r
        WHERE  r.cislo_stola = p_cislo_stola
          AND  r.stav        = 'aktivna'
        ORDER  BY r.datum DESC
        LIMIT  1;

        IF NOT FOUND THEN
            RAISE NOTICE
                '[CHYBA] Stol c. % nema ziadnu aktivnu rezervaciu v databaze.', p_cislo_stola;
            RETURN;
        END IF;

        RAISE NOTICE '[INFO] Automaticky najdena rezervacia: datum=%, cas=%', v_datum, v_cas;
    ELSE
        v_datum := p_datum_str::DATE;
        v_cas   := p_cas_str::TIME;
    END IF;

    -- ── Krok 2: Validacia rezervacie pre stol, datum a cas ───────────────────
    SELECT * INTO v_rez
    FROM   v_aktivne_stoly
    WHERE  cislo_stola  = p_cislo_stola
      AND  datum        = v_datum
      AND  cas_zaciatku <= v_cas
      AND  cas_konca    >= v_cas;

    IF NOT FOUND THEN
        RAISE NOTICE
            '[CHYBA] Stol c. % nema aktivnu rezervaciu na datum % o %. '
            'Skontrolujte parametre p_datum a p_cas.',
            p_cislo_stola, v_datum, v_cas;
        RETURN;
    END IF;

    -- ── Krok 3: Resolved casnik ───────────────────────────────────────────────
    IF p_id_casnika = 0 THEN
        SELECT id INTO p_id_casnika
        FROM   Zamestnanec
        WHERE  typ = 'casnik'
        ORDER  BY id LIMIT 1;

        RAISE NOTICE '[INFO] Automaticky vybrany casnik id=%', p_id_casnika;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM Zamestnanec
            WHERE id = p_id_casnika AND typ = 'casnik'
        ) THEN
            RAISE NOTICE
                '[CHYBA] Zamestnanec id=% nie je casnik alebo neexistuje.', p_id_casnika;
            RETURN;
        END IF;
    END IF;

    SELECT meno || ' ' || priezvisko INTO v_casnik_nazov
    FROM   Zamestnanec WHERE id = p_id_casnika;

    -- ── Krok 4: Resolved polozky menu ────────────────────────────────────────
    IF p_pol1 = 0 THEN
        SELECT id INTO p_pol1 FROM PolozkaMenu
        WHERE  je_dostupna = TRUE ORDER BY id LIMIT 1;
        RAISE NOTICE '[INFO] Automaticky vybrana polozka 1: id=%', p_pol1;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM PolozkaMenu WHERE id = p_pol1 AND je_dostupna = TRUE) THEN
            RAISE NOTICE
                '[CHYBA] Polozka menu id=% nie je dostupna alebo neexistuje.', p_pol1;
            RETURN;
        END IF;
    END IF;

    IF p_pol2 = 0 THEN
        SELECT id INTO p_pol2 FROM PolozkaMenu
        WHERE  je_dostupna = TRUE AND id <> p_pol1 ORDER BY id LIMIT 1;
        RAISE NOTICE '[INFO] Automaticky vybrana polozka 2: id=%', p_pol2;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM PolozkaMenu WHERE id = p_pol2 AND je_dostupna = TRUE) THEN
            RAISE NOTICE
                '[CHYBA] Polozka menu id=% nie je dostupna alebo neexistuje.', p_pol2;
            RETURN;
        END IF;
    END IF;

    IF p_pol1 = p_pol2 THEN
        RAISE NOTICE '[CHYBA] p_pol1 a p_pol2 musia byt rozne polozky.';
        RETURN;
    END IF;

    SELECT nazov INTO v_pol1_nazov FROM PolozkaMenu WHERE id = p_pol1;
    SELECT nazov INTO v_pol2_nazov FROM PolozkaMenu WHERE id = p_pol2;

    -- ── Krok 5: Validacia zakaznika ───────────────────────────────────────────
    IF NOT EXISTS (SELECT 1 FROM Zakaznik WHERE id = p_id_zakaznika) THEN
        RAISE NOTICE '[CHYBA] Zakaznik id=% neexistuje.', p_id_zakaznika;
        RETURN;
    END IF;

    -- ── Vsetky validacie presli - vytvarame objednavku ────────────────────────
    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'Vytvarame objednavku: stol=%, casnik=%, datum=%, cas=%',
        p_cislo_stola, v_casnik_nazov, v_datum, v_cas;
    RAISE NOTICE 'Polozky: % (x2), % (x1)', v_pol1_nazov, v_pol2_nazov;
    RAISE NOTICE '------------------------------------------------------------';

    -- INSERT 1: hlavny zaznam -> Objednavka
    INSERT INTO Objednavka (stav, cas_vytvorenia)
    VALUES ('nova', NOW())
    RETURNING id INTO v_id_objednavky;

    -- INSERT 2: dine-in specializacia -> DineInObjednavka
    INSERT INTO DineInObjednavka (id, id_zakaznika, cislo_stola, id_casnika)
    VALUES (v_id_objednavky, p_id_zakaznika, p_cislo_stola, p_id_casnika);

    -- INSERT 3: polozky so snimkou ceny -> ObjednavkaPolozka
    -- JOIN na PolozkaMenu dotahne aktualnu cenu - snimka zachovava historicku konzistenciu.
    INSERT INTO ObjednavkaPolozka
        (id_objednavky, id_polozky, mnozstvo, stav, cena_v_case_objednavky)
    SELECT
        v_id_objednavky,
        p.id,
        req.mnozstvo,
        'nova',
        p.aktualna_cena
    FROM (VALUES (p_pol1, 2), (p_pol2, 1)) AS req(id_pol, mnozstvo)
    JOIN PolozkaMenu p ON p.id = req.id_pol
    WHERE p.je_dostupna = TRUE;

    RAISE NOTICE '[OK] Objednavka id=% uspesne vytvorena.', v_id_objednavky;

END $$;

-- ── Vystup: detail novo vytvorenej objednavky ─────────────────────────────────
SELECT
    o.id                                        AS id_objednavky,
    o.stav,
    o.cas_vytvorenia,
    d.cislo_stola,
    z.meno || ' ' || z.priezvisko              AS casnik,
    pm.nazov                                    AS polozka,
    op.mnozstvo,
    op.cena_v_case_objednavky                   AS cena_za_kus,
    op.mnozstvo * op.cena_v_case_objednavky     AS subtotal
FROM Objednavka         o
JOIN DineInObjednavka   d  ON d.id             = o.id
JOIN ObjednavkaPolozka  op ON op.id_objednavky = o.id
JOIN PolozkaMenu        pm ON pm.id            = op.id_polozky
LEFT JOIN Zamestnanec   z  ON z.id             = d.id_casnika
WHERE o.id = (SELECT MAX(id) FROM Objednavka WHERE stav = 'nova')
ORDER BY pm.nazov;


-- =============================================================================
-- PROCES 2: Vykonnostny report casnikov
-- =============================================================================
--
-- Popis:
--   Manazer chce za zvoleny rok vidiet vykonnostny prehlad kazdeho casnika:
--     - celkova trzba ktoru obsluzil
--     - pocet objednavok a priemerna hodnota objednavky
--     - priemerne hodnotenie zakaznikov (z recenzii)
--     - poradie casnika podla trzby medzi vsetkymi casnikmi  -> RANK()
--     - percentualny podiel casnika na celkovych trzboch     -> SUM() OVER()
--     - kumulativna trzba podla poradia                      -> SUM() OVER()
--
-- Tabulky (6):
--   Zamestnanec, DineInObjednavka, Objednavka,
--   ObjednavkaPolozka, Faktura, Recenzia
-- =============================================================================

-- ── VIEW: zaplatene dine-in objednavky s trzbami ─────────────────────────────
-- Spaja Objednavka, DineInObjednavka, ObjednavkaPolozka a Faktura.
-- Zrusene polozky (stav = 'zrusena') do trzby nevstupuju.
CREATE OR REPLACE VIEW v_dine_in_trzby AS
SELECT
    o.id                                             AS id_objednavky,
    o.cas_vytvorenia,
    EXTRACT(YEAR FROM o.cas_vytvorenia)::INT         AS rok,
    d.id_casnika,
    SUM(op.mnozstvo * op.cena_v_case_objednavky)     AS trzba_objednavky
FROM Objednavka         o
JOIN DineInObjednavka   d  ON d.id             = o.id
JOIN ObjednavkaPolozka  op ON op.id_objednavky = o.id
                           AND op.stav        <> 'zrusena'
JOIN Faktura            f  ON f.id_objednavky  = o.id
                           AND f.je_zaplatena  = TRUE
GROUP BY o.id, o.cas_vytvorenia, d.id_casnika;

-- ── Hlavny analyticky dopyt ───────────────────────────────────────────────────
WITH
-- Krok 1: agregacia trzby a poctu objednavok na uroven casnika za rok
casnik_stats AS (
    SELECT
        t.id_casnika,
        COUNT(*)                                AS pocet_objednavok,
        ROUND(SUM(t.trzba_objednavky), 2)       AS celkova_trzba,
        ROUND(AVG(t.trzba_objednavky), 2)       AS avg_hodnota_objednavky
    FROM v_dine_in_trzby t
    WHERE t.rok = current_setting('myapp.p_rok')::INT
    GROUP BY t.id_casnika
),

-- Krok 2: priemerne hodnotenie recenzii pre kazdeho casnika
-- Recenzia -> Objednavka -> DineInObjednavka -> casnik
casnik_hodnotenia AS (
    SELECT
        d.id_casnika,
        ROUND(AVG(r.hodnotenie), 2)             AS avg_hodnotenie,
        COUNT(r.id)                             AS pocet_recenzii
    FROM Recenzia           r
    JOIN Objednavka         o  ON o.id = r.id_objednavky
    JOIN DineInObjednavka   d  ON d.id = o.id
    WHERE EXTRACT(YEAR FROM o.cas_vytvorenia)::INT = current_setting('myapp.p_rok')::INT
    GROUP BY d.id_casnika
),

-- Krok 3: window funkcie nad agregovanymy datami casnikov
so_window AS (
    SELECT
        s.id_casnika,
        s.pocet_objednavok,
        s.celkova_trzba,
        s.avg_hodnota_objednavky,
        h.avg_hodnotenie,
        COALESCE(h.pocet_recenzii, 0)           AS pocet_recenzii,

        -- Poradie casnika podla trzby (1 = najvynosnejsi)
        RANK() OVER (
            ORDER BY s.celkova_trzba DESC
        )                                       AS poradie_podla_trzby,

        -- Percentualny podiel casnika na celkovych trzboch restauracie
        ROUND(
            s.celkova_trzba
            / SUM(s.celkova_trzba) OVER () * 100
        , 1)                                    AS podiel_na_celku_pct,

        -- Kumulativna trzba podla poradia (od najlepsieho)
        ROUND(
            SUM(s.celkova_trzba) OVER (
                ORDER BY s.celkova_trzba DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
        , 2)                                    AS kumulativna_trzba_podla_poradia

    FROM casnik_stats       s
    LEFT JOIN casnik_hodnotenia h ON h.id_casnika = s.id_casnika
)

-- Krok 4: finalny vystup s menom casnika
SELECT
    w.poradie_podla_trzby                       AS poradie,
    z.meno || ' ' || z.priezvisko              AS casnik,
    w.pocet_objednavok,
    w.celkova_trzba                             AS trzba_eur,
    w.avg_hodnota_objednavky                    AS avg_objednavka_eur,
    w.avg_hodnotenie,
    w.pocet_recenzii,
    w.podiel_na_celku_pct                       AS podiel_pct,
    w.kumulativna_trzba_podla_poradia           AS kumulativna_trzba_eur
FROM so_window          w
JOIN Zamestnanec        z  ON z.id = w.id_casnika
ORDER BY w.poradie_podla_trzby;

-- =============================================================================
-- Koniec queries.sql
-- =============================================================================