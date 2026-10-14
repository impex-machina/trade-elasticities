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

Measured and **closed** (no change queued): the fn-14 weighting flags
(`--bw-lag raw`, `--exporter-weight bw_sum`), the reference-exporter rule,
λ. See `docs/methodology/stage2_country.md`.
