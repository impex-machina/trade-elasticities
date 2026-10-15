# Region-map coverage of the estimation data (patch 0125)

Raw cache `C:\Users\maxxj\te_m3\w1_2010_2024\baci_hs92_v202601_elast_country_hs4_raw_cache.rds` (113,781,209 rows, 1995-2024); `R/region_map.R` maps 233 codes; rev 4d65ef2, 2026-10-15 19:32:04 EDT.

234 country codes appear in the data; 4 of them are unmapped and fall into Stage 2a's catch-all `OTHER` region. Together they carry 0.0060% of trade value as importers (101,632 rows) and 0.0006% as exporters (37,372 rows).

| code | value share as importer | rows as importer | value share as exporter | rows as exporter | years |
|---|---|---|---|---|---|
| 316 | 0.0055% | 73,999 | 0.0003% | 22,773 | 2000-2024 |
| 86 | 0.0002% |  7,520 | 0.0001% |  6,436 | 1995-2024 |
| 260 | 0.0002% | 15,639 | 0.0001% |  3,375 | 1995-2024 |
| 612 | 0.0001% |  4,474 | 0.0000% |  4,788 | 1995-2024 |

**Reading (fixed in patch 0125): negligible.** Negligible means under 0.1% of trade value on both sides: the catch-all is documented, not changed. Otherwise the codes are mapped in a later patch and queued for the next Stage-2 session, because mapping them moves Stage 2a and so Stage 2b.
