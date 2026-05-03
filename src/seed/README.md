# Reprodukovanie seed dát

Tento priečinok obsahuje generátor a vygenerované seed dáta pre reštauračný systém.

## Súbory

- `seed.py` - generátor dát
- `seed.sql` - vygenerované INSERT príkazy
- `requirements.txt` - Python závislosti generátora

Súbor `schema.sql` je v odovzdávanom balíku vedľa priečinka `seed/`.

## Požiadavky

- PostgreSQL
- Python 3
- balík `Faker` zo súboru `requirements.txt`

## Postup

Z koreňa odovzdaného balíka vytvor databázu a aplikuj schému:

```bash
createdb restauracia
psql -d restauracia -f schema.sql
```

Nainštaluj závislosti a znovu vygeneruj `seed.sql`:

```bash
cd seed
python -m pip install -r requirements.txt
python seed.py
```

Seed načítaj do databázy z koreňa balíka:

```bash
psql -d restauracia -f seed/seed.sql
```

Generovanie je deterministické. Skript používa `SEED = 42`, preto pri rovnakom prostredí a rovnakej
verzii knižnice Faker vytvorí rovnaké dáta.

## Kontrola počtov

Po načítaní dát sa dajú počty overiť napríklad:

```sql
SELECT 'Zamestnanec' AS tabulka, COUNT(*) FROM Zamestnanec
UNION ALL SELECT 'Zakaznik', COUNT(*) FROM Zakaznik
UNION ALL SELECT 'PolozkaMenu', COUNT(*) FROM PolozkaMenu
UNION ALL SELECT 'Rezervacia', COUNT(*) FROM Rezervacia
UNION ALL SELECT 'Objednavka', COUNT(*) FROM Objednavka
UNION ALL SELECT 'DineInObjednavka', COUNT(*) FROM DineInObjednavka
UNION ALL SELECT 'DeliveryObjednavka', COUNT(*) FROM DeliveryObjednavka
UNION ALL SELECT 'ObjednavkaPolozka', COUNT(*) FROM ObjednavkaPolozka
UNION ALL SELECT 'Faktura', COUNT(*) FROM Faktura
UNION ALL SELECT 'Recenzia', COUNT(*) FROM Recenzia;
```
