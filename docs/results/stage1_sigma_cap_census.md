# Stage-1 sigma cap census (shipped v0.8.2/v0.8.3 Stage-1 table, 2026-09-29)

Read-only census on `data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`
(sha256 591d3bde…, unchanged v0.7.3 → v0.8.3) and the v0.8.2 Stage-2b table; recorded with patch 0084, which makes the cap a CLI parameter.

- adjust-4 cells (Step-2 sigma at the cap of 10): 10,809 (6.0% of ok cells); omega interior on 3,945 of them (those omega enter `feenstra_priors` although they were computed at the UNCAPPED Step-2 sigma, beside a published sigma of 10), omega capped 673, floored 1, NA 6,190.
- Uncapped Step-2 sigma on the adjust-4 cells, quantiles p10 / p25 / p50 / p75 / p90 / p95 / p99: 11.19 / 13.51 / 19.99 / 39.48 / 99.14 / 184.69 / 516.97; share <= 15: 32.5%, <= 20: 50.0%, <= 50: 80.2%, > 100: 9.9%.
- Closed-form HLIML sigma on the same cells (where computed), p10 / p25 / p50 / p75 / p90: 7.30 / 11.80 / 18.56 / 36.13 / 80.10 — the two estimators agree on the magnitude.
- Boundary sigma-cap cells (adjust 7): 7,259; interior HLIML cells with sigma in (8, 10): 1,049 — 18,068 cells sit at exactly 10 against a thin interior just below it.
- Stage-2b rows at sigma = 10: 541,480 (7.9%) in 18,063 cells; their gamma median 0.696 vs 0.652 elsewhere; opt_tariff cell median 0.672 vs 0.644 elsewhere.

Reading: the cap at 10 censors a continuous right tail of large-sigma (homogeneous) goods rather than a degenerate population — there is no break between 10 and 100 to aim a cap at; precision collapses continuously with sigma (the delta-method SE grows like (sigma - 1)^3), and the pipeline's own `sigma_robust` screen, which cannot act on a capped sigma because a pinned sigma carries no SE, is the right instrument once the cap stops binding on the bulk. The experiment is `--stage1-sigma-cap 50` (keeps 80% of the adjust-4 cells as estimates with SEs), with `--stage2-sigma-fallback-pin` holding the fallback sigma at its v0.8.3 value so the fallback rows do not move through the clean-cell median, and `--stage1-capped-omega drop` keeping the remaining capped cells' omega out of the Stage-2a priors. The cap-50 Stage-1 table records the uncapped `sigma_step2` and `sigma_hliml_cf` for every cell, so the Stage-1 side of any lower cap can be read off it without another Stage-1 run.
