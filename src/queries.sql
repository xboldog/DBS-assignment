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
-- KONFIGURACNE PARAMETRE - Proces 1
-- =============================================================================
-- Cislo stola a zakaznik - musia sa zhodovat s rezervaciou v DB:
SET myapp.p_cislo_stola  = '8';
SET myapp.p_id_zakaznika = '320';

-- Datum a cas prichodu hostia:
SET myapp.p_datum = '2026-05-03';
SET myapp.p_cas   = '13:15';

-- ID casnika ktory obsluhuje stol:
SET myapp.p_id_casnika = '13';

-- Polozky objednavky (3 polozky: id a mnozstvo):
SET myapp.p_pol1_id  = '12';  SET myapp.p_pol1_qty = '1';
SET myapp.p_pol2_id  = '17';  SET myapp.p_pol2_qty = '2';
SET myapp.p_pol3_id  = '24';  SET myapp.p_pol3_qty = '2';


-- =============================================================================
-- KONFIGURACNE PARAMETRE - Proces 2
-- =============================================================================
-- Rok pre ktory sa generuje vykonnostny report casnikov:
SET myapp.p_rok = '2026';


-- =============================================================================
-- ZDIELANE VIEWS
-- =============================================================================

-- Dostupne polozky menu
CREATE OR REPLACE VIEW v_dostupne_polozky AS
SELECT id, nazov, aktualna_cena, kategoria
FROM   PolozkaMenu
WHERE  je_dostupna = TRUE;

-- Potvrdene rezervacie (hostia este neprisli, stol ich caka).
CREATE OR REPLACE VIEW v_potvrdene_rezervacie AS
SELECT
    r.cislo_stola,
    r.id           AS id_rezervacie,
    r.id_zakaznika,
    r.datum,
    r.cas_zaciatku,
    r.cas_konca
FROM Rezervacia r
WHERE r.stav = 'potvrdena';


-- =============================================================================
-- PROCES 1: Vytvorenie dine-in objednavky
-- =============================================================================
--
-- Popis:
--   Zakaznik pride do restauracie a chce si sadnut k stolu. System overi:
--     (1) Ze zakaznik existuje v systeme
--         -> tabulka Zakaznik
--     (2) Ze pre dany stol a zakaznika existuje potvrdena rezervacia
--         na zadany datum a cas prichodu je v platnom okne
--         -> tabulka Rezervacia
--     (3) Ze zadany casnik existuje a ma rolu casnik
--         -> tabulka Zamestnanec
--     (4) Ze vsetky objednavane polozky su dostupne
--         -> tabulka PolozkaMenu
--   Ak vsetky podmienky platia, objednavka sa vytvori atomicky.
--   Chyby su hlasene cez RAISE NOTICE - spojenie zostane ciste.
--
-- Tabulky (5):
--   Rezervacia, PolozkaMenu, Objednavka, DineInObjednavka, ObjednavkaPolozka
-- =============================================================================

DO $$
DECLARE
    -- Nacitanie konfiguracnych parametrov
    p_cislo_stola    INT  := current_setting('myapp.p_cislo_stola')::INT;
    p_id_zakaznika   INT  := current_setting('myapp.p_id_zakaznika')::INT;
    p_id_casnika     INT  := current_setting('myapp.p_id_casnika')::INT;
    v_datum          DATE := current_setting('myapp.p_datum')::DATE;
    v_cas            TIME := current_setting('myapp.p_cas')::TIME;

    -- Polozky objednavky
    p_pol1_id        INT  := current_setting('myapp.p_pol1_id')::INT;
    p_pol1_qty       INT  := current_setting('myapp.p_pol1_qty')::INT;
    p_pol2_id        INT  := current_setting('myapp.p_pol2_id')::INT;
    p_pol2_qty       INT  := current_setting('myapp.p_pol2_qty')::INT;
    p_pol3_id        INT  := current_setting('myapp.p_pol3_id')::INT;
    p_pol3_qty       INT  := current_setting('myapp.p_pol3_qty')::INT;

    -- Interne premenne
    v_id_objednavky  INT;
    v_rez            RECORD;
    v_casnik_nazov   TEXT;
    v_pol            RECORD;
    v_nedostupna     BOOL := FALSE;
BEGIN

    -- ── Testovacie parametre (vypiseme hned na zaciatku) ──────────────────────
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'TESTOVACIE PARAMETRE:';
    RAISE NOTICE '  p_cislo_stola  = %', p_cislo_stola;
    RAISE NOTICE '  p_id_zakaznika = %', p_id_zakaznika;
    RAISE NOTICE '  p_id_casnika   = %', p_id_casnika;
    RAISE NOTICE '  p_datum        = %', v_datum;
    RAISE NOTICE '  p_cas          = %  (cas prichodu hosti)', v_cas;
    RAISE NOTICE '  pol1: id=%, qty=%', p_pol1_id, p_pol1_qty;
    RAISE NOTICE '  pol2: id=%, qty=%', p_pol2_id, p_pol2_qty;
    RAISE NOTICE '  pol3: id=%, qty=%', p_pol3_id, p_pol3_qty;
    RAISE NOTICE '============================================================';

    -- ── Krok 1: Validacia zakaznika ───────────────────────────────────────────
    IF NOT EXISTS (SELECT 1 FROM Zakaznik WHERE id = p_id_zakaznika) THEN
        RAISE NOTICE '[CHYBA] Zakaznik id=% neexistuje.', p_id_zakaznika;
        RETURN;
    END IF;

    -- ── Krok 2: Validacia rezervacie ──────────────────────────────────────────
    -- Hladame potvrdenu rezervaciu pre kombinaciu stol + zakaznik + datum.
    -- Cas prichodu musi byt v okne <cas_zaciatku, cas_konca>:
    SELECT * INTO v_rez
    FROM   v_potvrdene_rezervacie
    WHERE  cislo_stola  = p_cislo_stola
      AND  id_zakaznika = p_id_zakaznika
      AND  datum        = v_datum
      AND  cas_zaciatku <= v_cas
      AND  cas_konca    >= v_cas;

    IF NOT FOUND THEN
        -- Rozlisime ci prisli po konci rezervacie, alebo rezervacia vobec neexistuje
        IF EXISTS (
            SELECT 1 FROM Rezervacia
            WHERE  cislo_stola  = p_cislo_stola
              AND  id_zakaznika = p_id_zakaznika
              AND  datum        = v_datum
              AND  stav         = 'potvrdena'
              AND  cas_konca    < v_cas
        ) THEN
            RAISE NOTICE
                '[CHYBA] Rezervacia pre stol c. % a zakaznika id=% na datum % '
                'uz vyprsala (cas prichodu % je po konci rezervacie). '
                'Zakaznik je odmietnuty.',
                p_cislo_stola, p_id_zakaznika, v_datum, v_cas;
        ELSE
            RAISE NOTICE
                '[CHYBA] Pre stol c. % a zakaznika id=% neexistuje potvrdena '
                'rezervacia na datum % v case %. '
                'Skontrolujte p_cislo_stola, p_id_zakaznika, p_datum a p_cas.',
                p_cislo_stola, p_id_zakaznika, v_datum, v_cas;
        END IF;
        RETURN;
    END IF;

    RAISE NOTICE '[OK] Rezervacia najdena: stol=%, datum=%, okno=%-%',
        p_cislo_stola, v_datum, v_rez.cas_zaciatku, v_rez.cas_konca;

    -- ── Krok 3: Validacia casnika ──────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM Zamestnanec
        WHERE  id = p_id_casnika AND typ = 'casnik'
    ) THEN
        RAISE NOTICE
            '[CHYBA] Zamestnanec id=% nie je casnik alebo neexistuje.', p_id_casnika;
        RETURN;
    END IF;

    SELECT meno || ' ' || priezvisko INTO v_casnik_nazov
    FROM   Zamestnanec WHERE id = p_id_casnika;

    -- ── Krok 4: Validacia dostupnosti poloziek menu ───────────────────────────
    IF NOT EXISTS (SELECT 1 FROM PolozkaMenu WHERE id = p_pol1_id AND je_dostupna = TRUE) THEN
        RAISE NOTICE '[CHYBA] Polozka menu id=% nie je dostupna alebo neexistuje.', p_pol1_id;
        v_nedostupna := TRUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM PolozkaMenu WHERE id = p_pol2_id AND je_dostupna = TRUE) THEN
        RAISE NOTICE '[CHYBA] Polozka menu id=% nie je dostupna alebo neexistuje.', p_pol2_id;
        v_nedostupna := TRUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM PolozkaMenu WHERE id = p_pol3_id AND je_dostupna = TRUE) THEN
        RAISE NOTICE '[CHYBA] Polozka menu id=% nie je dostupna alebo neexistuje.', p_pol3_id;
        v_nedostupna := TRUE;
    END IF;

    IF v_nedostupna THEN
        RETURN;
    END IF;

    -- ── Vsetky validacie presli - vytvarame objednavku ────────────────────────
    RAISE NOTICE 'VYTVARAME OBJEDNAVKU:';
    RAISE NOTICE '  Stol:   %', p_cislo_stola;
    RAISE NOTICE '  Casnik: % (id=%)', v_casnik_nazov, p_id_casnika;
    RAISE NOTICE '  Cas vytvorenia: % %', v_datum, v_cas;
    RAISE NOTICE '  Polozky:';

    FOR v_pol IN
        SELECT pm.id AS pol_id,
               vals.mnozstvo,
               pm.nazov,
               pm.aktualna_cena,
               vals.mnozstvo * pm.aktualna_cena AS subtotal
        FROM   (VALUES (p_pol1_id, p_pol1_qty),
                       (p_pol2_id, p_pol2_qty),
                       (p_pol3_id, p_pol3_qty)) AS vals(pol_id, mnozstvo)
        JOIN   PolozkaMenu pm ON pm.id = vals.pol_id
    LOOP
        RAISE NOTICE '    - % x%  =  % EUR  (id=%)',
            v_pol.nazov, v_pol.mnozstvo, v_pol.subtotal, v_pol.pol_id;
    END LOOP;
    RAISE NOTICE '============================================================';

    -- INSERT 1: hlavny zaznam -> Objednavka
    INSERT INTO Objednavka (stav, cas_vytvorenia)
    VALUES ('nova', (v_datum || ' ' || v_cas)::TIMESTAMP)
    RETURNING id INTO v_id_objednavky;

    -- INSERT 2: dine-in specializacia -> DineInObjednavka
    INSERT INTO DineInObjednavka (id, id_zakaznika, cislo_stola, id_casnika)
    VALUES (v_id_objednavky, p_id_zakaznika, p_cislo_stola, p_id_casnika);

    -- INSERT 3: polozky so snimkou ceny -> ObjednavkaPolozka
    INSERT INTO ObjednavkaPolozka
        (id_objednavky, id_polozky, mnozstvo, stav, cena_v_case_objednavky)
    SELECT
        v_id_objednavky,
        pm.id,
        vals.mnozstvo,
        'nova',
        pm.aktualna_cena
    FROM   (VALUES (p_pol1_id, p_pol1_qty),
                   (p_pol2_id, p_pol2_qty),
                   (p_pol3_id, p_pol3_qty)) AS vals(pol_id, mnozstvo)
    JOIN   PolozkaMenu pm ON pm.id = vals.pol_id
    WHERE  pm.je_dostupna = TRUE;

    RAISE NOTICE '[OK] Objednavka id=% uspesne vytvorena s 3 polozkami.', v_id_objednavky;

END $$;

-- ── Vystup: detail novo vytvorenej objednavky ────────────────────────────────
SELECT
    o.id                                        AS id_objednavky,
    o.stav,
    o.cas_vytvorenia                            AS cas_vytvorenia,
    d.cislo_stola,
    zak.meno || ' ' || zak.priezvisko          AS zakaznik,
    z.meno   || ' ' || z.priezvisko            AS casnik,
    pm.nazov                                    AS polozka,
    op.mnozstvo,
    op.cena_v_case_objednavky                   AS cena_za_kus,
    op.mnozstvo * op.cena_v_case_objednavky     AS subtotal
FROM Objednavka         o
JOIN DineInObjednavka   d   ON d.id            = o.id
JOIN Zakaznik           zak ON zak.id          = d.id_zakaznika
JOIN ObjednavkaPolozka  op  ON op.id_objednavky = o.id
JOIN PolozkaMenu        pm  ON pm.id           = op.id_polozky
LEFT JOIN Zamestnanec   z   ON z.id            = d.id_casnika
WHERE o.id = (SELECT MAX(id) FROM Objednavka WHERE stav = 'nova')
ORDER BY pm.nazov;

-- ── Celkova suma objednavky ───────────────────────────────────────────────────
SELECT
	SUM(op.mnozstvo * op.cena_v_case_objednavky) AS celkova_suma_eur
FROM
	ObjednavkaPolozka op
WHERE
	op.id_objednavky = (
	SELECT
		MAX(id)
	FROM
		Objednavka
	WHERE
		stav = 'nova');


-- =============================================================================
-- PROCES 2: Vykonnostny report casnikov
-- =============================================================================
--
-- Popis:
--   Manazer chce za zvoleny rok vidiet vykonnostny prehlad kazdeho casnika:
--     - pocet vsetkych objednavok ktore obsluhoval (vsetky stavy okrem zrusenych)
--     - celkova hodnota objednavok a priemerna hodnota objednavky
--     - priemerne hodnotenie zakaznikov (z recenzii)
--     - poradie casnika podla trzby medzi vsetkymi casnikmi  -> RANK()
--     - percentualny podiel casnika na celkovych trzboch     -> SUM() OVER()
--     - kumulativna trzba podla poradia                      -> SUM() OVER()
--
-- Tabulky (5):
--   Zamestnanec, DineInObjednavka, Objednavka,
--   ObjednavkaPolozka, Recenzia
-- =============================================================================

-- ── VIEW: vsetky dine-in objednavky casnika (okrem zrusenych) ─────────────────
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
WHERE o.stav <> 'zrusena'
GROUP BY o.id, o.cas_vytvorenia, d.id_casnika;

-- ── Hlavny analyticky dopyt ───────────────────────────────────────────────────
WITH
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
so_window AS (
    SELECT
        s.id_casnika,
        s.pocet_objednavok,
        s.celkova_trzba,
        s.avg_hodnota_objednavky,
        h.avg_hodnotenie,
        COALESCE(h.pocet_recenzii, 0)           AS pocet_recenzii,
        RANK() OVER (
            ORDER BY s.celkova_trzba DESC
        )                                       AS poradie_podla_trzby,
        ROUND(
            s.celkova_trzba
            / SUM(s.celkova_trzba) OVER () * 100
        , 1)                                    AS podiel_na_celku_pct,
        ROUND(
            SUM(s.celkova_trzba) OVER (
                ORDER BY s.celkova_trzba DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
        , 2)                                    AS kumulativna_trzba_podla_poradia
    FROM casnik_stats       s
    LEFT JOIN casnik_hodnotenia h ON h.id_casnika = s.id_casnika
)
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