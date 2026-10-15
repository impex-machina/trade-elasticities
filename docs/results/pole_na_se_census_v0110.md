# Clean-set cells the sigma-pole rule cannot assess (v0110)

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`, Stage 2b `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (rev b19ed09, 2026-10-14 21:15:35 EDT). Rules as shipped: edge fallback, pole fallback at c = 1.

- Clean set: 113,706 cells (edge rule dropped 13,810, pole rule 55,396).
- Kept without a finite sigma_se (the pole test cannot run): **413 cells**.
- By route: hliml_boundary 413. By edge: omega_cap 270, omega_floor 143. Edge-SE status: edge_se_negative_variance 374, edge_se_singular_curvature  39. boundary_corner: 22.
- Their sigma: p10 1.014, p25 1.393, median 2.356, p75 4.072, p90 8.523; below 1.2: 70, below 1.5: 125, below 2: 177.
- With their route's median relative SE in place of the missing SE, the rule would drop 72 of them (sizing only).
- Stage-2b published rows in these cells: 2,855 (Tier 3 1,184); sigma_robust TRUE on 0 (expected 0: no finite SE); gamma median of their directly estimated rows 0.598 vs 0.787 over all directly estimated rows.

