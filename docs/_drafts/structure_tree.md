# Repository structure

> **N+7 status.** This tree is verified for `R/`, `scripts/`, and `tests/`
> (the modularized code, as of the N+6 conventions pass). Directories
> created empty per D3 (`data/`, `docs/`, `analysis/`, `validation/`,
> `inst/`) are shown with their *intended* contents annotated but marked
> `[CONFIRM]` where the actual populated state is filled in by later
> sections. Replace markers as each section lands.

```
trade-elasticities/
├── README.md                      # Project README (core authored N+7; completed Section 6b)
├── R/                             # Pipeline source — flat, organized by concern (D10)
│   ├── dependencies.R             # Consolidated package attachment (data.table, parallel, Rcpp, optparse) (C3/D14)
│   ├── feen94_het_baci.R          # Thin wrapper; sources dependencies.R + the splits, preserves source contract
│   ├── liml_estimator.R           # Stage 1 HLIML / Fuller LIML core (Grant & Soderbery 2024)
│   ├── stage1_liml_wrapper.R      # Stage 1 orchestration over PSOCK workers
│   ├── estimate_stage1_feenstra.R # Alternative Stage 1 (Feenstra 1994 NLS) — optional baseline
│   ├── estimate_cell_homogeneous.R# Homogeneous (single-γ) cell estimation
│   ├── estimate_cell_fixed_sigma.R# Fixed-σ cell estimation + penalized Gauss-Newton SE
│   ├── estimate_parallel.R        # Parallel engine (heterogeneous + fixed-σ passes)
│   ├── prepare_data.R             # Raw BACI → cell-level estimation panel
│   ├── load_baci.R                # BACI loader (.csv/.rds/.dta; .dta via optional haven)
│   ├── load_rcpp.R                # Loads Rcpp objectives from an explicit cpp_dir
│   ├── hs_codes.R                 # HS6 leading-zero-safe padding + HS6→HS4 rollup
│   ├── region_map.R               # Exporter → regional aggregate mapping (Stage 2a)
│   ├── lambda_calibration.R       # Shrinkage-λ calibration diagnostic + sweep
│   ├── iteration_helpers.R        # Starting-value seeding across passes
│   ├── quality_log.R              # Data-quality / cell-drop tracker
│   ├── output_paths.R             # parse_baci_source() + build_output_prefix() (see note)
│   ├── build_config.R             # CLI opts → cfg list
│   ├── parse_cli.R                # CLI argument parsing (optparse)
│   ├── validate_config.R          # cfg completeness/consistency checks
│   ├── summary.R                  # Results tables, within-pair stats, variance decomp, summary I/O
│   └── utils_general.R            # Topic-independent helpers (renamed from helpers.R, N+6)
├── scripts/
│   └── run_estimation.R           # CLI-driven three-stage pipeline entry point
├── tests/
│   ├── testthat.R                 # testthat runner
│   ├── testthat/
│   │   ├── helper-paths.R         # locate_source_dir() / cpp-dir resolution for tests
│   │   ├── helper-synthetic-data.R# Synthetic DGP for unit tests
│   │   ├── test-cli-parsing.R     # CLI parsing tests
│   │   ├── test-stage2b-e2e.R     # Stage 2b end-to-end schema/SE test
│   │   └── _snaps/                # testthat snapshots
│   ├── validate_liml.R            # 4-tier HLIML validation harness (854 lines)
│   ├── monte_carlo_se.R           # SE calibration Monte Carlo (Pillar 3)
│   ├── capture_liml_validation.R  # Tier 1+2 capture → methodology docs
│   ├── capture_tier4_validation.R # Tier 4 capture → methodology docs
│   ├── tier4_adjust_join.R        # Tier 4 join to Stage 1 adjust flags
│   ├── tier4_recompute_with_adjust.R
│   └── sanity_check_tier4.R
│
│   # ── Directories below exist per D3; populated by later sections ──
├── data/                          # [CONFIRM] Cache + manifest pattern (Section 3/N+9). manifest.csv in git; rest gitignored
│   ├── raw/                       # [CONFIRM] BACI HS92 V202601 (reader downloads from CEPII; off git/HF)
│   └── derived/                   # [CONFIRM] Pipeline cache (gitignored)
├── analysis/                      # [CONFIRM] Figure/table reproducers (Section 4/N+10): master.R + numbered scripts
├── validation/                    # [CONFIRM] Migrated from tests/ at N+10 (Section 4); now populated
├── docs/
│   ├── methodology/               # [CONFIRM] Four-pillar evidence base + README (Section 7/N+8)
│   └── audits/                    # [CONFIRM] Diagnostic/audit docs moved here at N+5
├── inst/                          # [CONFIRM] Soderbery/Grant-Soderbery PDFs (moved here Section 7/N+8, D48)
├── renv/                          # [CONFIRM] renv library (Section 5/N+11); renv/library gitignored
├── renv.lock                      # [CONFIRM] Lockfile (Section 5/N+11)
├── LICENSE                        # [CONFIRM] MIT
└── .gitignore                     # [CONFIRM]
```

## Notes

- `R/` is intentionally flat and organized by concern, not nested (D10).
  Function lookup is at call time, so the `feen94_het_baci.R` source
  order is for human auditability, not correctness.
- `R/.gitkeep` and `scripts/.gitkeep` are now **dead placeholders** —
  both directories contain real files. They should be removed (carried
  over from the N+5 punch list; not yet done as of this N+7 snapshot).
- The `tests/ -> validation/` migration (D91, Section 4/N+10) moved the
  validation harnesses out of `tests/` into `validation/` (done at N+10);
  `tests/` now holds testthat assertions only.
