"""
seed.py  –  Generátor seed dát pre Reštauračný systém
DBS / Databázové technológie  –  Zadanie 3
Autori: Dávid Boldog, Tomáš Bubeník

Použitie:
    pip install faker
    python seed.py          # vygeneruje seed.sql
    psql -d restauracia -f schema.sql
    psql -d restauracia -f seed.sql

Reprodukovateľnosť: fixný random seed (SEED = 42) zaručuje rovnaký
výstup pri každom spustení.
"""

import random
from datetime import date, time, datetime, timedelta
from faker import Faker

# =============================================================================
# Konfigurácia
# =============================================================================

OUTPUT_FILE = "seed.sql"
SEED        = 42            # fixný seed → reprodukovateľnosť

# Počty záznamov
N_ZAMESTNANEC   = 25
N_ZAKAZNIK      = 600
N_POLOZKA_MENU  = 50
N_REZERVACIA    = 1_500
N_OBJEDNAVKA    = 4_000     # celkový počet objednávok (dine-in + delivery)

# Pomery typov objednávok
DINE_IN_RATIO   = 0.60      # 60 % dine-in, 40 % delivery

# Podiel recenzií (z objednávok s faktúrou)
RECENZIA_RATIO  = 0.32

# Váhy zákazníkov – mocninová distribúcia (niektorí objednávajú oveľa viac)
ZAKAZNIK_POWER  = 1.5

# Rozsah dátumov (od 2024 do júna 2026)
DATE_FROM = date(2024, 1, 1)
DATE_TO   = date(2026, 6, 30)

# Simulovaný "aktuálny deň" – odovzdávame v nedeľu, ale pracujeme akoby bolo 3.5.2026.
# Pred TODAY → finálne stavy (ukončená/zaplatená/zrušená)
# = TODAY    → môžu byť všetky stavy (vrátane aktívnych/rozpracovaných)
# > TODAY    → len budúce stavy (potvrdená/zrušená pre rezervácie, žiadne objednávky)
TODAY = date(2026, 5, 3)

# Čísla stolov v reštaurácii
TABLE_NUMBERS = list(range(1, 21))   # stoly 1–20

# Počet aktívnych rezervácií na TODAY – maximálne počet stolov (20),
# realistický počet ~8–12 aby reštaurácia "žila", ale nebola preplnená
N_AKTIVNE_REZERVACIE = 10

# Počet objednávok vytvorených presne na TODAY (so zmiešanými stavmi).
# Zvyšné objednávky sa rozložia do minulosti (DATE_FROM .. TODAY-1).
N_OBJEDNAVKY_DNES = 120

# =============================================================================
# Inicializácia
# =============================================================================

random.seed(SEED)
fake = Faker("sk_SK")       # slovenská lokalizácia mien a adries
Faker.seed(SEED)

# =============================================================================
# Pomocné funkcie
# =============================================================================

def esc(s: str) -> str:
    """Escapuje apostrof v SQL reťazcoch."""
    return s.replace("'", "''")

def sql_str(s) -> str:
    """Obklopí hodnotu apostrofmi, alebo vráti NULL."""
    if s is None:
        return "NULL"
    return f"'{esc(str(s))}'"

def rand_time_slot():
    """Náhodný čas rezervácie – obedová alebo večerná zmena."""
    if random.random() < 0.45:
        # obed: 11:00 – 14:00
        h = random.randint(11, 13)
        m = random.choice([0, 15, 30, 45])
    else:
        # večera: 17:00 – 21:00
        h = random.randint(17, 20)
        m = random.choice([0, 15, 30, 45])
    return time(h, m)

def rand_time_slot_aktivna():
    """
    Čas začiatku pre aktívnu rezerváciu na TODAY (~10:30).
    Rezervácia musí byť už začatá (začiatok pred 10:30)
    a ešte neukončená (koniec po 10:30).
    Začiatok: 9:00 – 10:15, koniec: 11:00 – 13:00.
    """
    h = random.randint(9, 10)
    m = random.choice([0, 15, 30]) if h < 10 else random.choice([0, 15])
    return time(h, m)

def rand_date(from_: date, to_: date) -> date:
    delta = (to_ - from_).days
    return from_ + timedelta(days=random.randint(0, delta))

def weighted_customer_ids(ids: list, n: int) -> list:
    """
    Vráti n id zákazníkov podľa mocninovej distribúcie –
    niektorí zákazníci majú oveľa viac objednávok ako iní.
    """
    weights = [1 / (i + 1) ** ZAKAZNIK_POWER for i in range(len(ids))]
    return random.choices(ids, weights=weights, k=n)

# =============================================================================
# Generátory dát
# =============================================================================

def gen_zamestnanec(n: int) -> list[dict]:
    typy = ["casnik"] * 9 + ["kuchar"] * 7 + ["kurier"] * 6 + ["manazer"] * 3
    random.shuffle(typy)
    rows = []
    emails_used = set()
    tels_used   = set()
    for i in range(n):
        # unikátny email a telefón
        while True:
            email = fake.unique.email()
            if email not in emails_used:
                emails_used.add(email)
                break
        while True:
            tel = fake.phone_number()[:20]
            if tel not in tels_used:
                tels_used.add(tel)
                break
        rows.append({
            "meno":           fake.first_name(),
            "priezvisko":     fake.last_name(),
            "typ":            typy[i % len(typy)],
            "hodinova_mzda":  round(random.uniform(6.5, 18.0), 2),
            "odpracovany_cas": round(random.uniform(0, 2000), 2),
            "email":          email,
            "tel":            tel,
            "heslo":          fake.sha256()[:64],
        })
    return rows


def gen_zakaznik(n: int) -> list[dict]:
    rows = []
    for _ in range(n):
        rows.append({
            "meno":       fake.first_name(),
            "priezvisko": fake.last_name(),
            "email":      fake.unique.email(),
            "tel":        fake.unique.phone_number()[:20],
            "heslo":      fake.sha256()[:64],
        })
    return rows


def gen_polozka_menu(n: int) -> list[dict]:
    jedla = [
        "Hovädzí tatarák", "Cesnaková polievka", "Svíčková na smotane",
        "Vyprážaný syr", "Grilovaný losos", "Kačacia pečeň", "Sviečková",
        "Rezeň viedenský", "Kurací burger", "Vegánske rizoto",
        "Špagety carbonara", "Pizza Margherita", "Lamb chops",
        "Cézar šalát", "Tom Yum polievka", "Grilovaný halibut",
        "Fazuľová polievka", "Hovädzí burger", "Pulled pork sendvič",
        "Teľacie na víne", "Grilované zeleniny", "Penne arrabbiata",
        "Kuracie prsia na masle", "Rybia polievka", "Jahňacie kotlety",
    ]
    napoje = [
        "Espresso", "Cappuccino", "Latte macchiato", "Čierny čaj",
        "Pomarančový džús", "Jablkový džús", "Minerálna voda",
        "Pivo 12°", "Víno červené (dcl)", "Víno biele (dcl)",
        "Limonáda domáca", "Kakao", "Horúca čokoláda",
    ]
    dezerty = [
        "Tiramisu", "Cheesecake", "Palačinky so džemom",
        "Štrúdľa jablková", "Čokoládová fontána", "Crème brûlée",
        "Panna cotta", "Ovocný šalát", "Zmrzlina (3 gule)",
        "Brownies s vanilkovou zmrzlinou", "Medovník", "Makronky",
    ]

    pool = (
        [(n, "jedlo",  round(random.uniform(8, 28), 2)) for n in jedla] +
        [(n, "napoj",  round(random.uniform(1.5, 7), 2)) for n in napoje] +
        [(n, "dezert", round(random.uniform(4, 12), 2)) for n in dezerty]
    )
    random.shuffle(pool)
    selected = pool[:n]

    rows = []
    for nazov, kat, cena in selected:
        rows.append({
            "nazov":         nazov,
            "popis":         fake.sentence(nb_words=8),
            "aktualna_cena": cena,
            "kategoria":     kat,
            "je_dostupna":   random.random() > 0.08,   # ~8 % nedostupných
        })
    return rows


def gen_rezervacia(n: int, zakaznik_ids: list) -> list[dict]:
    """
    Rezervácie:
      - dátum < TODAY            → 'ukoncena' alebo 'zrusena'
      - dátum = TODAY (3.5.2026) → môžu byť všetky stavy: 'aktivna', 'potvrdena',
                                   'ukoncena', 'zrusena'. Aktívnych je presne
                                   N_AKTIVNE_REZERVACIE, každá na inom stole
                                   (nemôžu sa prekrývať).
      - dátum > TODAY            → 'potvrdena' alebo 'zrusena'
    """
    # Vygeneruj n dátumov a zoraď ich vzostupne.
    # Časť dátumov tlačíme priamo na TODAY, aby tam vznikol viditeľný "dnešný" deň.
    total_days = (DATE_TO - DATE_FROM).days
    raw_dates = [
        DATE_FROM + timedelta(days=random.randint(0, total_days))
        for _ in range(n - 25)
    ]
    # Pridaj 25 rezervácií presne na TODAY (z toho bude 10 aktívnych + zvyšok mix).
    raw_dates += [TODAY] * 25
    sorted_dates = sorted(raw_dates)

    # Aktívne stoly použité na TODAY – aby sa nezhodovali (žiadne dva aktívne na rovnakom)
    aktivne_stoly_pouzite: set = set()
    aktivne_count = 0

    rows = []
    for d in sorted_dates:
        cislo_stola = random.choice(TABLE_NUMBERS)

        if d < TODAY:
            # Minulosť → finálne stavy
            zac = rand_time_slot()
            koniec_min = zac.hour * 60 + zac.minute + random.randint(60, 180)
            koniec_min = min(koniec_min, 23 * 60)
            koniec = time(koniec_min // 60, koniec_min % 60)
            stav = random.choices(
                ["ukoncena", "zrusena"],
                weights=[85, 15]
            )[0]
        elif d == TODAY:
            # Dnes → mix všetkých stavov, ale aktívnych presne N_AKTIVNE_REZERVACIE
            # a každá na inom stole.
            kandidat = random.choices(
                ["aktivna", "potvrdena", "ukoncena", "zrusena"],
                weights=[40, 30, 20, 10]
            )[0]
            if kandidat == "aktivna":
                if (aktivne_count < N_AKTIVNE_REZERVACIE
                        and cislo_stola not in aktivne_stoly_pouzite):
                    stav = "aktivna"
                    aktivne_stoly_pouzite.add(cislo_stola)
                    aktivne_count += 1
                    # Aktívna rezervácia: začala pred 10:30, ešte stále trvá
                    zac = rand_time_slot_aktivna()
                    # Koniec: 11:00 – 13:00 (zaručene po 10:30)
                    koniec_h = random.randint(11, 12)
                    koniec_m = random.choice([0, 15, 30, 45])
                    koniec = time(koniec_h, koniec_m)
                else:
                    # Už máme dosť aktívnych alebo stôl je obsadený → pretypuj
                    stav = random.choices(
                        ["potvrdena", "ukoncena", "zrusena"],
                        weights=[50, 30, 20]
                    )[0]
                    zac = rand_time_slot()
                    koniec_min = zac.hour * 60 + zac.minute + random.randint(60, 180)
                    koniec_min = min(koniec_min, 23 * 60)
                    koniec = time(koniec_min // 60, koniec_min % 60)
            else:
                stav = kandidat
                zac = rand_time_slot()
                koniec_min = zac.hour * 60 + zac.minute + random.randint(60, 180)
                koniec_min = min(koniec_min, 23 * 60)
                koniec = time(koniec_min // 60, koniec_min % 60)
        else:
            # Budúcnosť → potvrdená alebo zrušená
            zac = rand_time_slot()
            koniec_min = zac.hour * 60 + zac.minute + random.randint(60, 180)
            koniec_min = min(koniec_min, 23 * 60)
            koniec = time(koniec_min // 60, koniec_min % 60)
            stav = random.choices(
                ["potvrdena", "zrusena"],
                weights=[88, 12]
            )[0]

        rows.append({
            "id_zakaznika": random.choice(zakaznik_ids),
            "cislo_stola":  cislo_stola,
            "datum":        d,
            "cas_zaciatku": zac,
            "cas_konca":    koniec,
            "pocet_osob":   random.randint(1, 8),
            "stav":         stav,
        })
    return rows


def gen_objednavky(
    n: int,
    zakaznik_ids: list,
    zamestnanec_rows: list,
    polozka_ids: list,
    polozka_ceny: dict,
    polozka_dostupna: dict,
) -> tuple:
    """
    Vráti tuple:
      (objednavky, dine_in, delivery, polozky, faktury, recenzie)

    Pravidlá:
      - Žiadne objednávky po TODAY (nemôžeme objednať do budúcnosti).
      - Pred TODAY: stav 'zaplatena' (finálny). Položky 'dorucena' (~3 %
        môže byť individuálne 'zrusena' – realistický rozptyl). Každá
        objednávka má presne 1 faktúru s je_zaplatena=TRUE.
      - Na TODAY: mix všetkých stavov pre objednávku aj položky.
        Faktúra môže byť je_zaplatena=FALSE alebo úplne chýbať
        (ak objednávka ešte nie je zaplatená/doručená).
      - DineInObjednavka + DeliveryObjednavka = Objednavka (1:1, presne jeden typ).
      - Recenzie len pre objednávky s faktúrou; čas recenzie ∈ (cas_obj, TODAY].
    """
    casnici = [z["id"] for z in zamestnanec_rows if z["typ"] == "casnik"]
    kurieri = [z["id"] for z in zamestnanec_rows if z["typ"] == "kurier"]

    # Zákazníci s mocninovou distribúciou – niektorí majú veľa objednávok
    customer_pool = weighted_customer_ids(zakaznik_ids, n)

    # Dostupné položky
    dostupne_ids = [pid for pid, d in polozka_dostupna.items() if d]

    objednavky   = []
    dine_in      = []
    delivery     = []
    polozky      = []
    faktury      = []
    recenzie     = []

    objednavka_id  = 1
    polozka_row_id = 1
    faktura_id     = 1

    # Rozdelenie: N - N_OBJEDNAVKY_DNES do minulosti, N_OBJEDNAVKY_DNES na TODAY.
    n_dnes = min(N_OBJEDNAVKY_DNES, n)
    n_pred = n - n_dnes

    # Časy pre minulosť: zaručíme aspoň 1 objednávku na každý deň [DATE_FROM, TODAY-1],
    # aby v tabuľke neboli medzery. Zvyšné objednávky rozložíme náhodne.
    last_past_day = TODAY - timedelta(days=1)
    past_days = [DATE_FROM + timedelta(days=d)
                 for d in range((last_past_day - DATE_FROM).days + 1)]

    timestamps: list[datetime] = []

    # 1 garantovaná objednávka na každý deň
    for d in past_days:
        mins_in_day = random.randint(0, 12 * 60 - 1)   # 10:00–22:59
        ts = datetime(d.year, d.month, d.day, 10, 0) + timedelta(minutes=mins_in_day)
        timestamps.append(ts)

    # Zvyšné minulé objednávky náhodne rozložené
    n_extra = n_pred - len(past_days)
    if n_extra > 0:
        for _ in range(n_extra):
            d = random.choice(past_days)
            mins_in_day = random.randint(0, 12 * 60 - 1)
            ts = datetime(d.year, d.month, d.day, 10, 0) + timedelta(minutes=mins_in_day)
            timestamps.append(ts)

    # Časy pre TODAY: úzke 45-minútové okno (10:00–10:44).
    # Prvá a posledná pripravuje_sa sa líšia max o 44 minút, nie hodiny.
    today_dt = datetime(TODAY.year, TODAY.month, TODAY.day, 10, 0)
    for _ in range(n_dnes):
        mins = random.randint(0, 44)   # 10:00–10:44
        timestamps.append(today_dt + timedelta(minutes=mins))

    # Spoločne zoradiť podľa času (minulosť aj dnešok plynule rastú v ID)
    timestamps.sort()

    for i, ts in enumerate(timestamps):
        zak_id = customer_pool[i]
        ts_date = ts.date()

        is_dine_in = random.random() < DINE_IN_RATIO

        # ---- STAV OBJEDNÁVKY ----
        if ts_date < TODAY:
            # Minulosť → finálny stav: zaplatená alebo zrušená (~8 %)
            stav = random.choices(
                ["zaplatena", "zrusena"],
                weights=[92, 8]
            )[0]
        else:
            # ts_date == TODAY → zmiešané stavy podľa typu
            if is_dine_in:
                stav = random.choices(
                    ["nova", "pripravuje_sa", "hotova", "zaplatena", "zrusena"],
                    weights=[12, 22, 18, 38, 10]
                )[0]
            else:
                stav = random.choices(
                    ["nova", "pripravuje_sa", "dorucuje_sa", "dorucena", "zrusena"],
                    weights=[12, 22, 18, 38, 10]
                )[0]

        objednavky.append({
            "id":             objednavka_id,
            "stav":           stav,
            "cas_vytvorenia": ts,
        })

        # ---- TYP OBJEDNÁVKY (presne jeden, dineIn + delivery = total) ----
        if is_dine_in:
            dine_in.append({
                "id":           objednavka_id,
                "id_zakaznika": zak_id if random.random() > 0.15 else None,
                "cislo_stola":  random.choice(TABLE_NUMBERS),
                "id_casnika":   random.choice(casnici) if casnici else None,
            })
        else:
            # Pravidlo pre kuriéra:
            #   - minulé 'zaplatena'                        → kuriér MUSÍ byť priradený
            #   - minulé 'zrusena'                          → ~50 % NULL (zrušené pred pridelením)
            #   - dnešné 'dorucena' / 'dorucuje_sa'         → kuriér MUSÍ byť priradený
            #   - dnešné 'nova' / 'pripravuje_sa'           → kuriér ešte väčšinou NIE JE pridelený (NULL)
            #   - dnešné 'zrusena'                          → môže byť NULL (zrušené pred pridelením)
            if ts_date < TODAY:
                # Minulosť: zaplatená → kuriér MUSÍ byť; zrušená → môže byť NULL
                if stav == "zrusena":
                    id_kuriera = random.choice(kurieri) if kurieri and random.random() > 0.5 else None
                else:
                    id_kuriera = random.choice(kurieri) if kurieri else None
            elif stav in ("dorucena", "dorucuje_sa"):
                id_kuriera = random.choice(kurieri) if kurieri else None
            elif stav in ("nova", "pripravuje_sa"):
                # Väčšinou NULL (kuchár ešte vyrába, kuriér čaká)
                id_kuriera = random.choice(kurieri) if kurieri and random.random() > 0.75 else None
            else:  # 'zrusena' na TODAY
                id_kuriera = random.choice(kurieri) if kurieri and random.random() > 0.6 else None

            delivery.append({
                "id":           objednavka_id,
                "id_zakaznika": zak_id,
                "id_kuriera":   id_kuriera,
                "mesto":        fake.city(),
                "ulica":        fake.street_address(),
            })

        # ---- STAV POLOŽKY (striktne odvodený od stavu objednávky) ----
        # Pravidlá (kuchár pridáva stav, keď pripravuje):
        #   objednavka 'nova'                            → položky všetky 'nova'
        #   objednavka 'pripravuje_sa'                   → položky 'nova' alebo 'pripravuje_sa'
        #   objednavka 'hotova'/'zaplatena'/'dorucena'/'dorucuje_sa'
        #                                                → položky 'dorucena' (občas individuálne 'zrusena')
        #   objednavka 'zrusena'                         → položky všetky 'zrusena'
        if stav == "nova":
            stav_pol_provider = lambda: "nova"
        elif stav == "pripravuje_sa":
            stav_pol_provider = lambda: random.choices(
                ["pripravuje_sa", "nova"], weights=[60, 40]
            )[0]
        elif stav in ("hotova", "zaplatena", "dorucena", "dorucuje_sa"):
            # Väčšina dorucena, ~3 % individuálne zrušené
            stav_pol_provider = lambda: "dorucena" if random.random() > 0.03 else "zrusena"
        else:  # 'zrusena'
            stav_pol_provider = lambda: "zrusena"

        # Položky objednávky: 1–5, váhovo skôr 2–3
        n_pol = random.choices([1, 2, 3, 4, 5], weights=[10, 35, 35, 15, 5])[0]
        vybrane = random.sample(dostupne_ids, min(n_pol, len(dostupne_ids)))

        for pid in vybrane:
            polozky.append({
                "id":                     polozka_row_id,
                "id_objednavky":          objednavka_id,
                "id_polozky":             pid,
                "mnozstvo":               random.randint(1, 3),
                "stav":                   stav_pol_provider(),
                "cena_v_case_objednavky": polozka_ceny[pid],
            })
            polozka_row_id += 1

        # ---- FAKTÚRA ----
        ma_fakturu = False
        if ts_date < TODAY:
            # Pred TODAY: zaplatené → faktúra zaplatená; zrušené → bez faktúry
            if stav == "zaplatena":
                faktury.append({
                    "id":            faktura_id,
                    "id_objednavky": objednavka_id,
                    "je_zaplatena":  True,
                    "sposob_platby": random.choices(
                        ["hotovost", "karta", "online"],
                        weights=[20, 55, 25]
                    )[0],
                })
                faktura_id += 1
                ma_fakturu = True
            # stav == "zrusena" → bez faktúry (ma_fakturu zostáva False)
        else:
            # TODAY:
            # - 'zaplatena' / 'dorucena' → faktúra je_zaplatena=TRUE
            # - 'pripravuje_sa', 'hotova', 'dorucuje_sa' → ~50 % má faktúru je_zaplatena=FALSE
            # - 'nova', 'zrusena' → bez faktúry
            if stav in ("zaplatena", "dorucena"):
                faktury.append({
                    "id":            faktura_id,
                    "id_objednavky": objednavka_id,
                    "je_zaplatena":  True,
                    "sposob_platby": random.choices(
                        ["hotovost", "karta", "online"],
                        weights=[20, 55, 25]
                    )[0],
                })
                faktura_id += 1
                ma_fakturu = True
            elif stav in ("pripravuje_sa", "hotova", "dorucuje_sa"):
                if random.random() < 0.5:
                    faktury.append({
                        "id":            faktura_id,
                        "id_objednavky": objednavka_id,
                        "je_zaplatena":  False,
                        "sposob_platby": random.choices(
                            ["hotovost", "karta", "online"],
                            weights=[20, 55, 25]
                        )[0],
                    })
                    faktura_id += 1
                    ma_fakturu = True
            # 'nova' a 'zrusena' → ma_fakturu zostáva False

        # ---- RECENZIA ---- (len pre minulé objednávky s faktúrou)
        # Recenzia môže prísť hocikedy medzi objednávkou a TODAY (vrátane).
        if ts_date < TODAY and ma_fakturu and random.random() < RECENZIA_RATIO:
            min_rec = ts + timedelta(hours=1)
            max_rec = min(ts + timedelta(days=14),
                          datetime.combine(TODAY, time(22, 0)))
            if max_rec > min_rec:
                delta_s = int((max_rec - min_rec).total_seconds())
                cas_rec = min_rec + timedelta(seconds=random.randint(0, delta_s))
                recenzie.append({
                    "id":            None,   # priradíme po finálnom zoradení
                    "id_objednavky": objednavka_id,
                    "hodnotenie":    random.choices(
                        [1, 2, 3, 4, 5],
                        weights=[3, 5, 15, 40, 37]
                    )[0],
                    "komentar":      fake.sentence(nb_words=10) if random.random() > 0.3 else None,
                    "cas":           cas_rec,
                })

        objednavka_id += 1

    # Recenzie zoradiť chronologicky podľa času a prečíslovať ID (logické poradie).
    recenzie.sort(key=lambda r: r["cas"])
    for idx, r in enumerate(recenzie, start=1):
        r["id"] = idx

    # ---- Obranné kontroly invariantov ----
    assert len(dine_in) + len(delivery) == len(objednavky), (
        f"DineIn ({len(dine_in)}) + Delivery ({len(delivery)}) "
        f"!= Objednavka ({len(objednavky)})"
    )
    din_ids = {r["id"] for r in dine_in}
    del_ids = {r["id"] for r in delivery}
    assert not (din_ids & del_ids), "Objednávka v DineIn aj Delivery súčasne!"
    assert (din_ids | del_ids) == {r["id"] for r in objednavky}, \
        "Objednávka bez záznamu v DineIn/Delivery!"

    return objednavky, dine_in, delivery, polozky, faktury, recenzie


# =============================================================================
# SQL renderovacie funkcie
# =============================================================================

def render_zamestnanec(rows: list) -> str:
    lines = []
    for i, r in enumerate(rows, start=1):
        r["id"] = i
        lines.append(
            f"({i}, {sql_str(r['meno'])}, {sql_str(r['priezvisko'])}, "
            f"'{r['typ']}', {r['hodinova_mzda']}, {r['odpracovany_cas']}, "
            f"{sql_str(r['email'])}, {sql_str(r['tel'])}, {sql_str(r['heslo'])})"
        )
    return ("INSERT INTO Zamestnanec "
            "(id, meno, priezvisko, typ, hodinova_mzda, odpracovany_cas, email, tel, heslo)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_zakaznik(rows: list) -> str:
    lines = []
    for i, r in enumerate(rows, start=1):
        r["id"] = i
        lines.append(
            f"({i}, {sql_str(r['meno'])}, {sql_str(r['priezvisko'])}, "
            f"{sql_str(r['email'])}, {sql_str(r['tel'])}, {sql_str(r['heslo'])})"
        )
    return ("INSERT INTO Zakaznik (id, meno, priezvisko, email, tel, heslo)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_polozka_menu(rows: list) -> str:
    lines = []
    for i, r in enumerate(rows, start=1):
        r["id"] = i
        dostupna = "TRUE" if r["je_dostupna"] else "FALSE"
        lines.append(
            f"({i}, {sql_str(r['nazov'])}, {sql_str(r['popis'])}, "
            f"{r['aktualna_cena']}, '{r['kategoria']}', {dostupna})"
        )
    return ("INSERT INTO PolozkaMenu (id, nazov, popis, aktualna_cena, kategoria, je_dostupna)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_rezervacia(rows: list) -> str:
    lines = []
    for i, r in enumerate(rows, start=1):
        lines.append(
            f"({i}, {r['id_zakaznika']}, {r['cislo_stola']}, "
            f"'{r['datum']}', '{r['cas_zaciatku']}', '{r['cas_konca']}', "
            f"{r['pocet_osob']}, '{r['stav']}')"
        )
    return ("INSERT INTO Rezervacia "
            "(id, id_zakaznika, cislo_stola, datum, cas_zaciatku, cas_konca, pocet_osob, stav)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_objednavka(rows: list) -> str:
    lines = []
    for r in rows:
        lines.append(
            f"({r['id']}, '{r['stav']}', '{r['cas_vytvorenia']}')"
        )
    return ("INSERT INTO Objednavka (id, stav, cas_vytvorenia)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_dine_in(rows: list) -> str:
    lines = []
    for r in rows:
        zak = r["id_zakaznika"] if r["id_zakaznika"] else "NULL"
        cas = r["id_casnika"]   if r["id_casnika"]   else "NULL"
        lines.append(
            f"({r['id']}, {zak}, {r['cislo_stola']}, {cas})"
        )
    return ("INSERT INTO DineInObjednavka (id, id_zakaznika, cislo_stola, id_casnika)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_delivery(rows: list) -> str:
    lines = []
    for r in rows:
        kur = r["id_kuriera"] if r["id_kuriera"] else "NULL"
        lines.append(
            f"({r['id']}, {r['id_zakaznika']}, {kur}, "
            f"{sql_str(r['mesto'])}, {sql_str(r['ulica'])})"
        )
    return ("INSERT INTO DeliveryObjednavka "
            "(id, id_zakaznika, id_kuriera, mesto, ulica)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_polozky(rows: list) -> str:
    lines = []
    for r in rows:
        lines.append(
            f"({r['id']}, {r['id_objednavky']}, {r['id_polozky']}, "
            f"{r['mnozstvo']}, '{r['stav']}', {r['cena_v_case_objednavky']})"
        )
    return ("INSERT INTO ObjednavkaPolozka "
            "(id, id_objednavky, id_polozky, mnozstvo, stav, cena_v_case_objednavky)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_faktury(rows: list) -> str:
    lines = []
    for r in rows:
        zap = "TRUE" if r["je_zaplatena"] else "FALSE"
        lines.append(
            f"({r['id']}, {r['id_objednavky']}, {zap}, '{r['sposob_platby']}')"
        )
    return ("INSERT INTO Faktura (id, id_objednavky, je_zaplatena, sposob_platby)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_recenzie(rows: list) -> str:
    lines = []
    for r in rows:
        lines.append(
            f"({r['id']}, {r['id_objednavky']}, {r['hodnotenie']}, "
            f"{sql_str(r['komentar'])}, '{r['cas']}')"
        )
    return ("INSERT INTO Recenzia (id, id_objednavky, hodnotenie, komentar, cas)\nVALUES\n"
            + ",\n".join(lines) + ";\n")


def render_sequences(
    n_zam, n_zak, n_pol, n_rez, n_obj, n_obp, n_fak, n_rec
) -> str:
    """
    Nastaví PostgreSQL sekvencie na správnu hodnotu po manuálnych INSERToch
    s explicitnými ID (inak by SERIAL generoval konflikty).
    """
    return "\n".join([
        f"SELECT setval('zamestnanec_id_seq', {n_zam});",
        f"SELECT setval('zakaznik_id_seq', {n_zak});",
        f"SELECT setval('polozkamenu_id_seq', {n_pol});",
        f"SELECT setval('rezervacia_id_seq', {n_rez});",
        f"SELECT setval('objednavka_id_seq', {n_obj});",
        f"SELECT setval('objednavkapolozka_id_seq', {n_obp});",
        f"SELECT setval('faktura_id_seq', {n_fak});",
        f"SELECT setval('recenzia_id_seq', {n_rec});",
    ]) + "\n"


# =============================================================================
# Hlavný program
# =============================================================================

def main():
    print("Generujem dáta...")

    zam_rows  = gen_zamestnanec(N_ZAMESTNANEC)
    zak_rows  = gen_zakaznik(N_ZAKAZNIK)
    pol_rows  = gen_polozka_menu(N_POLOZKA_MENU)

    # Priradiť ID pred generovaním objednávok
    for i, r in enumerate(zam_rows, 1): r["id"] = i
    for i, r in enumerate(zak_rows, 1): r["id"] = i
    for i, r in enumerate(pol_rows, 1): r["id"] = i

    zakaznik_ids     = [r["id"] for r in zak_rows]
    polozka_ids      = [r["id"] for r in pol_rows]
    polozka_ceny     = {r["id"]: r["aktualna_cena"] for r in pol_rows}
    polozka_dostupna = {r["id"]: r["je_dostupna"]   for r in pol_rows}

    rez_rows = gen_rezervacia(N_REZERVACIA, zakaznik_ids)

    obj, din, del_, pol, fak, rec = gen_objednavky(
        N_OBJEDNAVKA,
        zakaznik_ids,
        zam_rows,
        polozka_ids,
        polozka_ceny,
        polozka_dostupna,
    )

    # Štatistiky
    print(f"  Zamestnanec:       {len(zam_rows):>6}")
    print(f"  Zakaznik:          {len(zak_rows):>6}")
    print(f"  PolozkaMenu:       {len(pol_rows):>6}")
    print(f"  Rezervacia:        {len(rez_rows):>6}")
    print(f"  Objednavka:        {len(obj):>6}")
    print(f"    DineInObjednavka:{len(din):>6}")
    print(f"    DeliveryObjedn.: {len(del_):>6}")
    print(f"  ObjednavkaPolozka: {len(pol):>6}")
    print(f"  Faktura:           {len(fak):>6}")
    print(f"  Recenzia:          {len(rec):>6}")
    total = sum([len(zam_rows), len(zak_rows), len(pol_rows), len(rez_rows),
                 len(obj), len(pol), len(fak), len(rec)])
    print(f"  ─────────────────────────")
    print(f"  SPOLU:             {total:>6}")

    # Zápis do seed.sql
    print(f"\nZapisujem do {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:

        f.write("-- ============================================================\n")
        f.write("-- seed.sql  –  Reštauračný systém\n")
        f.write("-- Generované skriptom seed.py  (random seed = 42)\n")
        f.write("-- ============================================================\n\n")

        f.write("BEGIN;\n\n")

        f.write("-- Zamestnanec\n")
        f.write(render_zamestnanec(zam_rows))
        f.write("\n")

        f.write("-- Zakaznik\n")
        f.write(render_zakaznik(zak_rows))
        f.write("\n")

        f.write("-- PolozkaMenu\n")
        f.write(render_polozka_menu(pol_rows))
        f.write("\n")

        f.write("-- Rezervacia\n")
        f.write(render_rezervacia(rez_rows))
        f.write("\n")

        f.write("-- Objednavka\n")
        f.write(render_objednavka(obj))
        f.write("\n")

        f.write("-- DineInObjednavka\n")
        f.write(render_dine_in(din))
        f.write("\n")

        f.write("-- DeliveryObjednavka\n")
        f.write(render_delivery(del_))
        f.write("\n")

        f.write("-- ObjednavkaPolozka\n")
        f.write(render_polozky(pol))
        f.write("\n")

        f.write("-- Faktura\n")
        f.write(render_faktury(fak))
        f.write("\n")

        f.write("-- Recenzia\n")
        f.write(render_recenzie(rec))
        f.write("\n")

        f.write("-- Oprava sekvencií (SERIAL musí vedieť kde pokračovať)\n")
        f.write(render_sequences(
            len(zam_rows), len(zak_rows), len(pol_rows), len(rez_rows),
            len(obj), len(pol), len(fak), len(rec)
        ))
        f.write("\nCOMMIT;\n")

    print(f"Hotovo → {OUTPUT_FILE}")


if __name__ == "__main__":
    main()