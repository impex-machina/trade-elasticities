# Product-level companion table (patches 0127-0128)

Built from `data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (1240 products); written to `data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv`; rev 095821c, 2026-10-16 10:40:22 EDT.

## Distribution across products (p10 / p25 / p50 / p75 / p90)

- product median gamma: 0.405 / 0.531 / 0.732 / 1.038 / 1.359
- product median opt_tariff: 0.392 / 0.510 / 0.709 / 0.989 / 1.295
- product median sigma: 2.473 / 2.473 / 2.473 / 2.473 / 2.473
- share of a product's cells with their own sigma: 0.321 / 0.402 / 0.477 / 0.548 / 0.611

## Reproducibility across products

Spearman correlation across products (95% bootstrap interval over products), and the level gap: how far a product's median moves between the two halves, |median_a / median_b - 1| at the median and the 90th percentile across products.

| split | products | median gamma: Spearman | gap p50 / p90 | median opt_tariff: Spearman | gap p50 / p90 |
|---|---|---|---|---|---|
| odd vs even years (within a period) | 25 | 0.99 [0.96, 1.00] | 0.2% / 2.0% | 0.97 [0.88, 0.99] | 4.4% / 8.6% |
| 1995-2009 vs 2010-2024 (across periods) | 25 | 0.99 [0.95, 1.00] | 0.8% / 4.6% | 0.98 [0.92, 1.00] | 3.7% / 11.1% |

**Reading (fixed in patch 0127): publish.** Publish if both odd/even correlations are at least 0.50; do not publish if both are below 0.30; otherwise partial.
