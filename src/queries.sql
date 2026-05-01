-- =============================================================================
-- queries.sql  –  Reštauračný systém
-- DBS / Databázové technológie  –  Zadanie 3
-- Autori: Dávid Boldog, Tomáš Bubeník
-- =============================================================================
-- Obsah:
--   PROCES 1  – Vytvorenie dine-in objednávky          (operačný / transakčný)
--   PROCES 2  – Výkonnostný report čašníkov            (analytický)
-- =============================================================================


-- =============================================================================
-- PROCES 1: Vytvorenie dine-in objednávky
-- =============================================================================
--
-- Popis:
--   Zákazník si pri stole objedná jedlá. Pred samotným INSERTom systém overí:
--     (1) že pre daný stôl existuje aktívna rezervácia v aktuálnom čase
--         → tabuľka Rezervacia
--     (2) že všetky objednávané položky sú dostupné
--         → tabuľka PolozkaMenu
--   Ak obidve podmienky platia, objednávka sa vytvorí atomicky v jednej
--   transakcii. Ak nie, transakcia sa rollbackne a žiadne záznamy nevzniknú.
--
-- Tabuľky (5):
--   Rezervacia, PolozkaMenu, Objednavka, DineInObjednavka, ObjednavkaPolozka
--
-- Vstup:
--   cislo_stola  = 3
--   id_zakaznika = 1
--   id_casnika   = 6
--   polozky      = [(id=1, mnozstvo=2), (id=5, mnozstvo=1)]
--
-- Výstup:
--   Detail novo vytvorenej objednávky s položkami a medzisúčtami.
-- =============================================================================

BEGIN;

-- ── VIEW: stoly s aktívnou rezerváciou v aktuálnom čase ──────────────────────
-- Používa sa pri každej novej dine-in objednávke. Encapsuluje podmienky
-- časového prekrytia a stavu rezervácie, aby sa nemuseli opakovať.
CREATE OR REPLACE VIEW v_aktivne_stoly AS
SELECT DISTINCT
    r.cislo_stola,
    r.id            AS id_rezervacie,
    r.id_zakaznika,
    r.cas_zaciatku,
    r.cas_konca
FROM Rezervacia r
WHERE r.stav         = 'aktivna'
  AND r.datum        = CURRENT_DATE
  AND r.cas_zaciatku <= CURRENT_TIME
  AND r.cas_konca    >= CURRENT_TIME;

-- ── VIEW: dostupné položky menu ───────────────────────────────────────────────
-- Encapsuluje filter je_dostupna = TRUE. Používa sa pri zostavovaní objednávky
-- aj pri validácii – zákazník vidí len to, čo si môže objednať.
CREATE OR REPLACE VIEW v_dostupne_polozky AS
SELECT
    id,
    nazov,
    aktualna_cena,
    kategoria
FROM PolozkaMenu
WHERE je_dostupna = TRUE;

-- ── Validácia 1: existuje aktívna rezervácia pre daný stôl? ──────────────────
-- Ak nie → RAISE EXCEPTION preruší transakciu, žiadne INSERTy sa nevykonajú.
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*)
    INTO   v_count
    FROM   v_aktivne_stoly
    WHERE  cislo_stola = 3;             -- :cislo_stola

    IF v_count = 0 THEN
        RAISE EXCEPTION
            'Stôl č. % nemá aktívnu rezerváciu – objednávku nie je možné vytvoriť.', 3;
    END IF;
END $$;

-- ── Validácia 2: sú všetky požadované položky dostupné? ──────────────────────
-- VALUES tabuľka simuluje vstupný zoznam z aplikácie.
-- Ak čo i len jedna položka chýba vo v_dostupne_polozky → výnimka.
DO $$
DECLARE
    v_nedostupne INT;
BEGIN
    SELECT COUNT(*)
    INTO   v_nedostupne
    FROM  (VALUES (1), (5)) AS poziadavka(id_pol)   -- :id_polozky zoznam
    WHERE  poziadavka.id_pol NOT IN (
               SELECT id FROM v_dostupne_polozky
           );

    IF v_nedostupne > 0 THEN
        RAISE EXCEPTION
            '% položka/y nie sú dostupné – objednávku nie je možné vytvoriť.',
            v_nedostupne;
    END IF;
END $$;

-- ── INSERT 1: hlavný záznam objednávky  →  Objednavka ────────────────────────
INSERT INTO Objednavka (stav, cas_vytvorenia)
VALUES ('nova', NOW());

-- ── INSERT 2: dine-in špecializácia  →  DineInObjednavka ─────────────────────
-- currval() vráti id práve vloženého riadku – v rámci tej istej transakcie
-- je to bezpečné, iné súbežné transakcie ho neovplyvnia.
INSERT INTO DineInObjednavka (id, id_zakaznika, cislo_stola, id_casnika)
VALUES (
    currval('objednavka_id_seq'),       -- id práve vytvorenej objednávky
    1,                                  -- :id_zakaznika
    3,                                  -- :cislo_stola
    6                                   -- :id_casnika
);

-- ── INSERT 3: položky so snímkou ceny  →  ObjednavkaPolozka ──────────────────
-- JOIN na PolozkaMenu dotiahne aktuálnu cenu a uloží ju ako snímku.
-- Historické objednávky tak zostanú konzistentné aj po zmene ceny v menu.
-- WHERE je_dostupna = TRUE je posledná poistka na úrovni DB.
INSERT INTO ObjednavkaPolozka
    (id_objednavky, id_polozky, mnozstvo, stav, cena_v_case_objednavky)
SELECT
    currval('objednavka_id_seq'),
    p.id,
    req.mnozstvo,
    'nova',
    p.aktualna_cena                     -- snímka ceny v čase objednávky
FROM (VALUES
    (1, 2),                             -- (id_polozky, mnozstvo)
    (5, 1)
) AS req(id_pol, mnozstvo)
JOIN PolozkaMenu p ON p.id = req.id_pol
WHERE p.je_dostupna = TRUE;

-- ── Výstup: detail novo vytvorenej objednávky ────────────────────────────────
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
WHERE o.id = currval('objednavka_id_seq');

COMMIT;


-- =============================================================================
-- PROCES 2: Výkonnostný report čašníkov
-- =============================================================================
--
-- Popis:
--   Manažér chce za zvolený rok vidieť výkonnostný prehľad každého čašníka:
--     – celková tržba ktorú obslúžil
--     – počet objednávok
--     – priemerná hodnota objednávky
--     – priemerné hodnotenie zákazníkov (z recenzií)
--     – poradie čašníka podľa tržby medzi všetkými čašníkmi  →  RANK()
--     – percentuálny podiel čašníka na celkových tržbách     →  SUM() OVER()
--     – kumulatívna tržba podľa poradia                      →  SUM() OVER()
--
-- Tabuľky (6):
--   Zamestnanec, DineInObjednavka, Objednavka,
--   ObjednavkaPolozka, Faktura, Recenzia
--
-- Vstup:
--   rok = 2024
--
-- Výstup:
--   Jeden riadok za čašníka, zoradené podľa tržby zostupne.
-- =============================================================================

-- ── VIEW: základ pre report – zaplatené dine-in objednávky s tržbami ─────────
-- Spája Objednavka, DineInObjednavka, ObjednavkaPolozka a Faktura.
-- Výsledok je jedna objednávka = jedna tržba (suma položiek).
-- Zrušené položky (stav = 'zrusena') do tržby nevstupujú.
CREATE OR REPLACE VIEW v_dine_in_trzby AS
SELECT
    o.id                                                AS id_objednavky,
    o.cas_vytvorenia,
    EXTRACT(YEAR FROM o.cas_vytvorenia)::INT            AS rok,
    d.id_casnika,
    SUM(op.mnozstvo * op.cena_v_case_objednavky)        AS trzba_objednavky
FROM Objednavka         o
JOIN DineInObjednavka   d  ON d.id             = o.id
JOIN ObjednavkaPolozka  op ON op.id_objednavky = o.id
                           AND op.stav        <> 'zrusena'
JOIN Faktura            f  ON f.id_objednavky  = o.id
                           AND f.je_zaplatena  = TRUE
GROUP BY o.id, o.cas_vytvorenia, d.id_casnika;

-- ── Hlavný analytický dopyt ───────────────────────────────────────────────────
WITH
-- Krok 1: agregácia tržieb a počtu objednávok na úrovni čašníka za rok
casnik_stats AS (
    SELECT
        t.id_casnika,
        COUNT(*)                                AS pocet_objednavok,
        ROUND(SUM(t.trzba_objednavky), 2)       AS celkova_trzba,
        ROUND(AVG(t.trzba_objednavky), 2)       AS avg_hodnota_objednavky
    FROM v_dine_in_trzby t
    WHERE t.rok = 2024                          -- :rok
    GROUP BY t.id_casnika
),

-- Krok 2: priemerné hodnotenie recenzií pre každého čašníka
-- Recenzia → Objednavka → DineInObjednavka → čašník
casnik_hodnotenia AS (
    SELECT
        d.id_casnika,
        ROUND(AVG(r.hodnotenie), 2)             AS avg_hodnotenie,
        COUNT(r.id)                             AS pocet_recenzii
    FROM Recenzia           r
    JOIN Objednavka         o  ON o.id  = r.id_objednavky
    JOIN DineInObjednavka   d  ON d.id  = o.id
    WHERE EXTRACT(YEAR FROM o.cas_vytvorenia)::INT = 2024   -- :rok
    GROUP BY d.id_casnika
),

-- Krok 3: window funkcie nad agregovanými dátami čašníkov
so_window AS (
    SELECT
        s.id_casnika,
        s.pocet_objednavok,
        s.celkova_trzba,
        s.avg_hodnota_objednavky,
        COALESCE(h.avg_hodnotenie, NULL)        AS avg_hodnotenie,
        COALESCE(h.pocet_recenzii, 0)           AS pocet_recenzii,

        -- Poradie čašníka podľa tržby (1 = najvýnosnejší)
        RANK() OVER (
            ORDER BY s.celkova_trzba DESC
        )                                       AS poradie_podla_trzby,

        -- Percentuálny podiel čašníka na celkových tržbách reštaurácie
        ROUND(
            s.celkova_trzba
            / SUM(s.celkova_trzba) OVER () * 100
        , 1)                                    AS podiel_na_celku_pct,

        -- Kumulatívna tržba podľa poradia (od najlepšieho)
        ROUND(
            SUM(s.celkova_trzba) OVER (
                ORDER BY s.celkova_trzba DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
        , 2)                                    AS kumulativna_trzba_podla_poradia

    FROM casnik_stats       s
    LEFT JOIN casnik_hodnotenia h ON h.id_casnika = s.id_casnika
)

-- Krok 4: finálny výstup s menom čašníka
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