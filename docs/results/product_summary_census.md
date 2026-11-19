# Product-level companion table (patches 0127-0128)

Built from `data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (1240 products); written to `data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv`; rev 215a579, 2026-11-19 01:58:43 EST.

The reproducibility rows are carried from the census of 2026-11-08 01:47:56 EST (rev 2eae5c4), measured on the 2% subsample runs of the v0.12.0 configuration (patches 0164, 0168). The table above comes from a later estimation, and the rows were not re-measured on its configuration: read them as v0.12.0's, not as this table's.

## Distribution across products (p10 / p25 / p50 / p75 / p90)

- product median gamma: 0.417 / 0.546 / 0.753 / 1.058 / 1.366
- product median opt_tariff: 0.421 / 0.542 / 0.750 / 1.051 / 1.361
- product median sigma: 2.605 / 2.666 / 2.678 / 2.684 / 2.754
- share of a product's cells with their own sigma (the update or a Stage-1 estimate, not the level / fallback): 0.658 / 0.766 / 0.871 / 0.933 / 0.961

## Reproducibility across products

Spearman correlation across products (95% bootstrap interval over products), and the level gap: how far a product's median moves between the two halves, |median_a / median_b - 1| at the median and the 90th percentile across products.

| split | products | median gamma: Spearman | gap p50 / p90 | median opt_tariff: Spearman | gap p50 / p90 |
|---|---|---|---|---|---|
| odd vs even years (within a period) | 25 | 1.00 [0.99, 1.00] | 0.2% / 0.7% | 0.97 [0.88, 0.99] | 3.0% / 11.7% |
| 1995-2009 vs 2010-2024 (across periods) | 25 | 0.63 [0.28, 0.81] | 26.1% / 95.7% | 0.73 [0.45, 0.88] | 18.4% / 60.8% |

**Reading (fixed in patch 0127): publish.** Publish if both odd/even correlations are at least 0.50; do not publish if both are below 0.30; otherwise partial.
