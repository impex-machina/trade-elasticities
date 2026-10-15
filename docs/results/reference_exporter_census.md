# Reference exporters in the two stages (patch 0125)

Raw cache `C:\Users\maxxj\te_m3\w1_2010_2024\baci_hs92_v202601_elast_country_hs4_raw_cache.rds`, Stage 1 `data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`, Stage 2b `data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`; rev 4d65ef2, 2026-10-15 19:46:31 EDT.

Both stages pick the exporter with the most periods (ties by total value): Stage 1 counts years in levels on the untrimmed panel, Stage 2 counts retained differenced years after the |d ln p| >= 2 trim. An exporter's observation in year t needs the reference's difference in t, so each year the reference lacks one is lost for the whole cell; the reference's own shocks enter every observation.

- **A. The two references differ** in 17.7% of the 181,779 cells with a Stage-1 estimate and published Stage-2 rows (32,258 cells).
- **Stage-2 rule recomputed here** reproduces the published `ref_exporter` in 100.0% of 231,136 cells.
- **B. Observations.** On 182,912 cells with a Stage-1 estimate, Stage-1 observations number 72,087,352 under the current rule, 72,122,810 under the counting-basis alternative (most differenced years; another reference in 3.8% of cells), 72,182,375 under the best of the five longest differenced series (another reference in 7.4% of cells), and 72,642,607 if the reference had every year. The current rule's loss against the best: median 0.0%, p90 0.0%, p99 23.1% of a cell's observations, at least 5.0% in 4.3% of cells (against the simple alternative: at least 5.0% in 1.7% of cells).
- **C. Jumps.** The Stage-1 reference's own series has at least one |d ln p| >= 2 year in 36.6% of cells; in those cells such years enter a median 8.5% of the cell's Stage-1 observations (p90 28.6%).

**Reading (fixed in patch 0125): closed.** A local Stage-1 A/B of a rule that keeps more observations is worth running if the current rule loses at least 5.0% of a cell's usable observations against the best of the five candidates in at least 10.0% of cells. A and C are informational: aligning the two stages' references has no population consequence, and Stage 1 keeps its jumps by the 2026-09-22 sample decision.
