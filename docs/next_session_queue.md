# Next estimation session: queued default changes

Changes that have been measured, cleared their pre-registered rule for
adoption, and wait for the next Stage-2 session that happens for another
reason. None of them justifies a session on its own. When a session is
planned, flip each default in one patch before it, re-measure the
configuration **as it will ship** on the 2% subsample (the 2026-10-12
lesson), and remove the entry here.

No change is queued. Patch 0113 flipped the two that were -- `--stage2a-handoff-rows published`
(correctness) and `--stage2-export-moment value` (Eq. (8) on export values) -- for the v0.11.0
session (`docs/methodology/stage2_country.md`, "The v0.11.0 session").

**Superseded:** `--stage2-export-total all` (the export-share denominator over all value; measured 2026-10-13, $\Delta r_{\text{within}}$ −0.001). Under `--stage2-export-moment value` the exporter total enters nothing; flip it only if the export moment stays `share`.

**Shipped as v0.12.0 (2026-11-08; the full-data session of 2026-11-07, release gate PASS, `docs/results/gate_v0120.md`):** `--stage2-sigma-update import --stage2-sigma-shrink 0.146` -- the Stage-2b sigma re-solved per cell from the Eq. (10) block at the gamma_V-final gamma-hats, shrunk toward the full-panel level by Spearman-Brown's b_full = 0.255, set before a fourth Stage-2b pass (patches 0152/0154). Measured as it will ship on the 2% subsample: the two-window census (`docs/results/sigma_update_window_census.md`; the shrunk sigma beats the level predictor out of sample, gain 0.011 in median |d ln(sigma - 1)|, bootstrap CI [0.004, 0.016]; the incumbent Stage-1 sigma has no cross-period reproducibility, r 0.04), the ship-config census (`docs/results/ship_config_census.md`: sigma moves in 99.7% of cells, fallback cells 2,328 -> 356, gamma by > 1% in 49% of rows, opt_tariff by > 1% in 91% of cells, median tariff 0.666 -> 0.692) and the odd/even parity A/B (`docs/results/stage2_reliability_ship.md`: r_within 0.357 -> 0.380, delta +0.023, goods-bootstrap CI [0.007, 0.040], 0.15% of draws <= 0). The full-data run is Stage 1 and 2a loaded, Stage 2b with four passes (about 2 h 25 against 1 h 50). The README template, the card and the column notes are written from the censuses in the release patch; `sigma_se`, `sigma_robust` and `gamma_se_total` are NA/FALSE on every updated row.

Measured and **closed** (no change queued): the fn-14 weighting flags
(`--bw-lag raw`, `--exporter-weight bw_sum`), the reference-exporter rule,
λ. See `docs/methodology/stage2_country.md`.
