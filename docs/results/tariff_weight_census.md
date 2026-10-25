# opt_tariff under total-trade weights (patch 0138)

Raw cache `C:\Users\maxxj\te_m3\w1_2010_2024\baci_hs92_v202601_elast_country_hs4_raw_cache.rds`, Stage 2b `data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`; rev ece82b1, 2026-10-25 19:19:22 EDT.

Each cell's optimal tariff recomputed over the published, directly estimated rows with each exporter weighted by its total customs value over its panel years (avg_trade times the number of those years) instead of its mean annual value.

- Replication: the pairs' panel years found for 100.0% of 4,982,259 rows; the mean of their values equals the published `avg_trade` for 100.0% of them; the mean-weighted tariff recomputed here equals the published `opt_tariff` in 100.0% of cells.
- Cells (210,098; 997 with a single directly estimated exporter, where the weights cannot matter): |change| median 5.6%, p90 31.5%, p99 91.3%; more than 10% in 35.3% of cells.
- Products (1,240): the median cell tariff moves by a median 5.6% (p90 13.5%, p99 20.3%); more than 5% in 54.1% of products.

**Reading (fixed in patch 0138): material.** Material if at least 10% of cells move by more than 10%, or at least 10% of products' median tariff by more than 5%.
