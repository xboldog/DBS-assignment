# DBS Zadanie 3 - Reštauračný systém

Repozitár obsahuje LaTeX report, fyzický PostgreSQL model, SQL procesy a reprodukovateľné seed dáta
pre reštauračný systém.

## Štruktúra

```text
.
├── assets/              # obrázky použité v reporte
├── src/
│   ├── report.tex       # hlavný LaTeX dokument
│   ├── schema.sql       # fyzický model databázy
│   ├── queries.sql      # implementované procesy
│   └── seed/
│       ├── seed.py
│       ├── seed.sql
│       ├── README.md
│       └── requirements.txt
└── Makefile
```

## Build reportu

Vyžaduje `pdflatex`.

```bash
make
```

Výsledok je `src/report.pdf`. Makefile nepúšťa BibTeX, pretože aktuálny report nepoužíva citácie ani
bibliografiu.

## Seed dáta

Návod na reprodukovanie seedu je v `src/seed/README.md`.
