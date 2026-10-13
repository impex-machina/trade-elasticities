# Next estimation session: queued default changes

Changes that have been measured, cleared their pre-registered rule for
adoption, and wait for the next Stage-2 session that happens for another
reason. None of them justifies a session on its own. When a session is
planned, flip each default in one patch before it, re-measure the
configuration **as it will ship** on the 2% subsample (the 2026-10-12
lesson), and remove the entry here.

| change | flag and new default | measured | evidence | prerequisite |
|---|---|---|---|---|
| Export-share denominator over all value, including flows without a quantity (Eq. (11)'s $V_j$ as the model defines it) | `--stage2-export-total all` (default `quantity`) | 2026-10-13 | $\Delta r_{\text{within}}$ −0.001, step p50 2.6e-4 / p99 0.06 (`docs/methodology/stage2_country.md`, "The export-share denominator, measured") | the totals table on S3 `cache/baci_hs92_v202601_elast_country_hs4_export_totals.rds` (placed by `scripts/box/setup.sh`) |

Measured and **closed** (no change queued): the fn-14 weighting flags
(`--bw-lag raw`, `--exporter-weight bw_sum`), the reference-exporter rule,
λ. See `docs/methodology/stage2_country.md`.
