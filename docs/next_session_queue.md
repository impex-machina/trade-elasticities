# Next estimation session: queued default changes

Changes that have been measured, cleared their pre-registered rule for
adoption, and wait for the next Stage-2 session that happens for another
reason. None of them justifies a session on its own. When a session is
planned, flip each default in one patch before it, re-measure the
configuration **as it will ship** on the 2% subsample (the 2026-10-12
lesson), and remove the entry here.

| change | flag and new default | measured | evidence | prerequisite |
|---|---|---|---|---|
| Eq. (11)'s export moment on log export values (Eq. (8) holds exactly on values; on shares it omits $(\rho_I - \rho_V)\,\Delta\ln V_j$); replaces the export-share denominator change, which is moot under `value` | `--stage2-export-moment value` (default `share`) | 2026-10-13 | $\Delta r_{\text{within}}$ −0.008 (0.368 → 0.360), rank ρ −0.006, step p50 0.0056 / p99 0.64 (`docs/methodology/stage2_country.md`, "The export moment on values, measured"; `docs/results/stage2_reliability_m_expval.md`) | none |
| Stage-2a rows handed to Stage 2b: the published rows only (bug: since v0.10.0 the rows the Stage-2a tail trim flagged entered Stage 2b's priors, regional γ_V and starting values) | `--stage2a-handoff-rows published` (default `all`) | correctness fix, no rule | `docs/methodology/stage2_country.md`, "Stage-2a rows handed to Stage 2b"; sizing `results/stage2a_handoff_census.json` | none |

**Superseded:** `--stage2-export-total all` (the export-share denominator over all value; measured 2026-10-13, $\Delta r_{\text{within}}$ −0.001). Under `--stage2-export-moment value` the exporter total enters nothing; flip it only if the export moment stays `share`.

Measured and **closed** (no change queued): the fn-14 weighting flags
(`--bw-lag raw`, `--exporter-weight bw_sum`), the reference-exporter rule,
λ. See `docs/methodology/stage2_country.md`.
