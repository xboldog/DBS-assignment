-- =============================================================================
-- queries.sql  -  Restauracny system
-- DBS / Databazove technologie  -  Zadanie 3
-- Autori: David Boldog, Tomas Bubenik
-- =============================================================================
-- Obsah:
--   PROCES 1  - Vytvorenie dine-in objednavky       (operacny / transakcny)
--   PROCES 2  - Vykonnostny report casnikov          (analyticky)
-- =============================================================================


-- =============================================================================
-- KONFIGURACNE PARAMETRE - Proces 1
-- =============================================================================
-- Cislo stola a zakaznik - musia sa zhodovat s rezervaciou v DB:
SET myapp.p_cislo_stola  = '8';
SET myapp.p_id_zakaznika = '320';

-- Datum a cas prichodu hosti:
SET myapp.p_datum = '2026-05-03';
SET myapp.p_cas   = '13:15';

-- ID casnika, ktory obsluhuje stol:
SET myapp.p_id_casnika = '13';

-- Polozky objednavky (3 polozky: id a mnozstvo):
SET myapp.p_pol1_id  = '12';  SET myapp.p_pol1_qty = '1';
SET myapp.p_pol2_id  = '17';  SET myapp.p_pol2_qty = '2';
SET myapp.p_pol3_id  = '24';  SET myapp.p_pol3_qty = '2';


-- =============================================================================
-- KONFIGURACNE PARAMETRE - Proces 2
-- =============================================================================
-- Rok, pre ktory sa generuje vykonnostny report casnikov:
SET myapp.p_rok = '2026';


-- =============================================================================
-- ZDIELANE VIEWS
-- =============================================================================

-- Dostupne polozky menu
CREATE OR REPLACE VIEW v_dostupne_polozky AS
SELECT id, nazov, aktualna_cena, kategoria
FROM PolozkaMenu
WHERE je_dostupna = TRUE;

-- Potvrdene rezervacie (hostia este neprisli, stol ich caka).
CREATE OR REPLACE VIEW v_potvrdene_rezervacie AS
SELECT
    r.cislo_stola,
    r.id AS id_rezervacie,
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
--     (1) ze zakaznik existuje,
--     (2) ze pre dany stol a zakaznika existuje potvrdena rezervacia
--         na zadany datum a cas prichodu,
--     (3) ze zadany zamestnanec existuje a ma rolu casnik,
--     (4) ze vsetky objednavane polozky existuju, su dostupne a maju kladne
--         mnozstvo.
--
--   Ak vsetky podmienky platia, prikaz atomicky:
--     - zmeni rezervaciu na stav aktivna,
--     - vlozi hlavny zaznam do Objednavka,
--     - vlozi specializaciu do DineInObjednavka,
--     - vlozi polozky do ObjednavkaPolozka so snimkou aktualnej ceny.
--
-- Tabulky (7):
--   Zakaznik, Zamestnanec, Rezervacia, PolozkaMenu,
--   Objednavka, DineInObjednavka, ObjednavkaPolozka
-- =============================================================================

WITH
params AS (
    SELECT
        current_setting('myapp.p_cislo_stola')::INT  AS cislo_stola,
        current_setting('myapp.p_id_zakaznika')::INT AS id_zakaznika,
        current_setting('myapp.p_id_casnika')::INT   AS id_casnika,
        current_setting('myapp.p_datum')::DATE       AS datum,
        current_setting('myapp.p_cas')::TIME         AS cas_prichodu
),
input_items(polozka_id, mnozstvo) AS (
    VALUES
        (current_setting('myapp.p_pol1_id')::INT, current_setting('myapp.p_pol1_qty')::INT),
        (current_setting('myapp.p_pol2_id')::INT, current_setting('myapp.p_pol2_qty')::INT),
        (current_setting('myapp.p_pol3_id')::INT, current_setting('myapp.p_pol3_qty')::INT)
),
valid_reservation AS (
    SELECT r.*
    FROM Rezervacia r
    JOIN params p
      ON p.cislo_stola = r.cislo_stola
     AND p.id_zakaznika = r.id_zakaznika
     AND p.datum = r.datum
     AND p.cas_prichodu BETWEEN r.cas_zaciatku AND r.cas_konca
    WHERE r.stav = 'potvrdena'
    ORDER BY r.id
    LIMIT 1
),
validation_errors AS (
    SELECT format('[CHYBA] Zakaznik id=%s neexistuje.', p.id_zakaznika) AS sprava
    FROM params p
    WHERE NOT EXISTS (
        SELECT 1
        FROM Zakaznik z
        WHERE z.id = p.id_zakaznika
    )

    UNION ALL

    SELECT
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM Rezervacia r
                WHERE r.cislo_stola = p.cislo_stola
                  AND r.id_zakaznika = p.id_zakaznika
                  AND r.datum = p.datum
                  AND r.stav = 'potvrdena'
                  AND r.cas_konca < p.cas_prichodu
            )
            THEN format(
                '[CHYBA] Rezervacia pre stol c. %s a zakaznika id=%s na datum %s uz vyprsala.',
                p.cislo_stola, p.id_zakaznika, p.datum
            )
            ELSE format(
                '[CHYBA] Pre stol c. %s a zakaznika id=%s neexistuje potvrdena rezervacia na datum %s v case %s.',
                p.cislo_stola, p.id_zakaznika, p.datum, p.cas_prichodu
            )
        END AS sprava
    FROM params p
    WHERE NOT EXISTS (SELECT 1 FROM valid_reservation)

    UNION ALL

    SELECT format('[CHYBA] Zamestnanec id=%s nie je casnik alebo neexistuje.', p.id_casnika)
    FROM params p
    WHERE NOT EXISTS (
        SELECT 1
        FROM Zamestnanec z
        WHERE z.id = p.id_casnika
          AND z.typ = 'casnik'
    )

    UNION ALL

    SELECT format('[CHYBA] Mnozstvo pre polozku menu id=%s musi byt kladne.', i.polozka_id)
    FROM input_items i
    WHERE i.mnozstvo <= 0

    UNION ALL

    SELECT format('[CHYBA] Polozka menu id=%s nie je dostupna alebo neexistuje.', i.polozka_id)
    FROM input_items i
    WHERE NOT EXISTS (
        SELECT 1
        FROM PolozkaMenu pm
        WHERE pm.id = i.polozka_id
          AND pm.je_dostupna = TRUE
    )
),
activated_reservation AS (
    UPDATE Rezervacia r
    SET stav = 'aktivna'
    FROM valid_reservation vr
    WHERE r.id = vr.id
      AND NOT EXISTS (SELECT 1 FROM validation_errors)
    RETURNING r.id
),
inserted_order AS (
    INSERT INTO Objednavka (cas_vytvorenia)
    SELECT p.datum + p.cas_prichodu
    FROM params p
    WHERE EXISTS (SELECT 1 FROM activated_reservation)
    RETURNING id, stav, cas_vytvorenia
),
inserted_dine_in AS (
    INSERT INTO DineInObjednavka (id, id_zakaznika, cislo_stola, id_casnika)
    SELECT
        o.id,
        p.id_zakaznika,
        p.cislo_stola,
        p.id_casnika
    FROM inserted_order o
    CROSS JOIN params p
    RETURNING id, id_zakaznika, cislo_stola, id_casnika
),
inserted_items AS (
    INSERT INTO ObjednavkaPolozka
        (id_objednavky, id_polozky, mnozstvo, cena_v_case_objednavky)
    SELECT
        o.id,
        pm.id,
        i.mnozstvo,
        pm.aktualna_cena
    FROM inserted_order o
    CROSS JOIN input_items i
    JOIN PolozkaMenu pm
      ON pm.id = i.polozka_id
     AND pm.je_dostupna = TRUE
    RETURNING id_objednavky, id_polozky, mnozstvo, cena_v_case_objednavky
)
SELECT *
FROM (
    SELECT
        'OK'                                      AS vysledok,
        o.id                                      AS id_objednavky,
        o.stav                                    AS stav,
        o.cas_vytvorenia                          AS cas_vytvorenia,
        d.cislo_stola,
        zak.meno || ' ' || zak.priezvisko        AS zakaznik,
        z.meno || ' ' || z.priezvisko            AS casnik,
        pm.nazov                                  AS polozka,
        ii.mnozstvo,
        ii.cena_v_case_objednavky                 AS cena_za_kus,
        ii.mnozstvo * ii.cena_v_case_objednavky   AS subtotal,
        SUM(ii.mnozstvo * ii.cena_v_case_objednavky)
            OVER (PARTITION BY ii.id_objednavky)  AS celkova_suma_eur,
        format('[OK] Objednavka id=%s uspesne vytvorena.', o.id) AS sprava
    FROM inserted_order o
    JOIN inserted_dine_in d ON d.id = o.id
    JOIN Zakaznik zak ON zak.id = d.id_zakaznika
    JOIN Zamestnanec z ON z.id = d.id_casnika
    JOIN inserted_items ii ON ii.id_objednavky = o.id
    JOIN PolozkaMenu pm ON pm.id = ii.id_polozky

    UNION ALL

    SELECT
        'CHYBA',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        e.sprava
    FROM validation_errors e
) vysledok_procesu
ORDER BY vysledok, polozka NULLS LAST, sprava;


-- =============================================================================
-- PROCES 2: Vykonnostny report casnikov
-- =============================================================================
--
-- Popis:
--   Manazer chce za zvoleny rok vidiet vykonnostny prehlad kazdeho casnika:
--     - pocet vsetkych objednavok, ktore obsluhoval (vsetky stavy okrem zrusenych),
--     - celkova hodnota objednavok a priemerna hodnota objednavky,
--     - priemerne hodnotenie zakaznikov (z recenzii),
--     - poradie casnika podla trzby medzi vsetkymi casnikmi  -> RANK(),
--     - percentualny podiel casnika na celkovych trzboch     -> SUM() OVER(),
--     - kumulativna trzba podla poradia                      -> SUM() OVER().
--
-- Tabulky (6):
--   Zamestnanec, DineInObjednavka, Objednavka,
--   ObjednavkaPolozka, Faktura, Recenzia
-- =============================================================================

-- VIEW: vsetky dine-in objednavky casnika (okrem zrusenych)
CREATE OR REPLACE VIEW v_dine_in_trzby AS
SELECT
    o.id                                             AS id_objednavky,
    o.cas_vytvorenia,
    d.id_casnika,
    SUM(op.mnozstvo * op.cena_v_case_objednavky)     AS trzba_objednavky
FROM Objednavka         o
JOIN Faktura            f  ON f.id_objednavky = o.id
                           AND f.je_zaplatena = TRUE
JOIN DineInObjednavka   d  ON d.id             = o.id
JOIN ObjednavkaPolozka  op ON op.id_objednavky = o.id
                           AND op.stav        <> 'zrusena'
WHERE o.stav <> 'zrusena'
GROUP BY o.id, o.cas_vytvorenia, d.id_casnika;

-- Hlavny analyticky dopyt bez CTE, cez vnorene subqueries
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
FROM (
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
    FROM (
        SELECT
            t.id_casnika,
            COUNT(*)                                AS pocet_objednavok,
            ROUND(SUM(t.trzba_objednavky), 2)       AS celkova_trzba,
            ROUND(AVG(t.trzba_objednavky), 2)       AS avg_hodnota_objednavky
        FROM v_dine_in_trzby t
        WHERE t.cas_vytvorenia >= (current_setting('myapp.p_rok') || '-01-01')::TIMESTAMP
          AND t.cas_vytvorenia <  ((current_setting('myapp.p_rok')::INT + 1)::TEXT || '-01-01')::TIMESTAMP
        GROUP BY t.id_casnika
    ) s
    LEFT JOIN (
        SELECT
            d.id_casnika,
            ROUND(AVG(r.hodnotenie), 2)             AS avg_hodnotenie,
            COUNT(r.id)                             AS pocet_recenzii
        FROM Recenzia           r
        JOIN Objednavka         o  ON o.id = r.id_objednavky
        JOIN DineInObjednavka   d  ON d.id = o.id
        WHERE o.cas_vytvorenia >= (current_setting('myapp.p_rok') || '-01-01')::TIMESTAMP
          AND o.cas_vytvorenia <  ((current_setting('myapp.p_rok')::INT + 1)::TEXT || '-01-01')::TIMESTAMP
        GROUP BY d.id_casnika
    ) h ON h.id_casnika = s.id_casnika
) w
JOIN Zamestnanec z ON z.id = w.id_casnika
ORDER BY w.poradie_podla_trzby;
