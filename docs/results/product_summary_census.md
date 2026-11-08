# Product-level companion table (patches 0127-0128)

Built from `data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (1240 products); written to `data\derived\product\baci_hs92_v202601_elast_hs4_product_summary.csv`; rev 2eae5c4, 2026-11-08 01:47:56 EST.

## Distribution across products (p10 / p25 / p50 / p75 / p90)

- product median gamma: 0.410 / 0.538 / 0.745 / 1.045 / 1.360
- product median opt_tariff: 0.416 / 0.540 / 0.745 / 1.046 / 1.361
- product median sigma: 2.605 / 2.666 / 2.678 / 2.688 / 2.759
- share of a product's cells with their own sigma: 0.000 / 0.000 / 0.000 / 0.006 / 0.014

## Reproducibility across products

Spearman correlation across products (95% bootstrap interval over products), and the level gap: how far a product's median moves between the two halves, |median_a / median_b - 1| at the median and the 90th percentile across products.

| split | products | median gamma: Spearman | gap p50 / p90 | median opt_tariff: Spearman | gap p50 / p90 |
|---|---|---|---|---|---|
| odd vs even years (within a period) | 25 | 1.00 [0.99, 1.00] | 0.2% / 0.7% | 0.97 [0.88, 0.99] | 3.0% / 11.7% |
| 1995-2009 vs 2010-2024 (across periods) | 25 | 0.63 [0.28, 0.81] | 26.1% / 95.7% | 0.73 [0.45, 0.88] | 18.4% / 60.8% |

**Reading (fixed in patch 0127): publish.** Publish if both odd/even correlations are at least 0.50; do not publish if both are below 0.30; otherwise partial.
