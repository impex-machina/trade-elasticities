# Product-level companion table (patch 0127)

Built from `data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (1240 products; bootstrap over importers, 200 draws); written to `data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv` (not yet published); rev d62301a, 2026-10-16 09:41:46 EDT.

## Distribution across products (p10 / p25 / p50 / p75 / p90)

- product median gamma: 0.405 / 0.531 / 0.732 / 1.038 / 1.359
- product median opt_tariff: 0.392 / 0.510 / 0.709 / 0.989 / 1.295
- product median sigma: 2.473 / 2.473 / 2.473 / 2.473 / 2.473
- width of the gamma interval, ln(hi / lo): 0.001 / 0.003 / 0.011 / 0.035 / 0.078
- share of a product's cells with their own sigma: 0.321 / 0.402 / 0.477 / 0.548 / 0.611

## Reproducibility across products (Spearman, 95% bootstrap interval over products)

| split | products | median gamma | median opt_tariff |
|---|---|---|---|
| odd vs even years (within a period) | 25 | 0.99 [0.96, 1.00] | 0.97 [0.87, 0.99] |
| 1995-2009 vs 2010-2024 (across periods) | 25 | 0.99 [0.95, 1.00] | 0.98 [0.91, 0.99] |

**Reading (fixed in patch 0127): publish.** Publish if both odd/even correlations are at least 0.50; do not publish if both are below 0.30; otherwise partial.
