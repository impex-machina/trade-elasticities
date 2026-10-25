# Cell-level opt_tariff under the precision-scaled ridge, on real data (patch 0135)

The block halves of patch 0133 (2% product subsample): the candidate at tau2_eb against the shipped ridge; rev 550a763, 2026-10-25 17:28:45 EDT.

- Cell-level ln opt_tariff, split-half correlation: 0.344 at tau2_eb against 0.391 shipped (3,912 cells in all four tables).
- Row-level ln gamma, for information: 0.240 against 0.337 (71,734 rows).

**Reading (fixed in patch 0135, before the numbers): do not release.** Proceed if the candidate's tariff correlation is no more than 0.02 below the shipped's.
