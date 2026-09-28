# grid\run_grid.ps1 (v3, targeted split-half rerun) -- v0.8.0 design grid on a 2% product subsample (patches 0071/0072)
# Keeps every completed full-panel pass. Runs the A/B halves only for the decision configurations, and treats an A or B
# table whose hash equals the full table's (the pre-0072 void halves) as stale: it is deleted and rerun.
$ErrorActionPreference = 'Continue'
$REPO  = 'C:\Users\maxxj\OneDrive\Desktop\Projects\trade-elasticities\trade-elasticities'
$BACI  = 'C:\Users\maxxj\BACI_HS92_V202601'
$CACHE = 'C:\Users\maxxj\te_cache\baci_hs92_v202601_elast_country_hs4_raw_cache.rds'
$FRAC = 0.02; $SEED = 20260926; $NCORES = 8
$SPLIT_CONFIGS = @('log_l0.1_moments', 'level_l0.1_base', 'level_l0.1_moments', 'level_l0.01_moments')
$STAGE1 = Join-Path $REPO 'data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds'
$G = 'C:\Users\maxxj\te_grid'; New-Item -ItemType Directory -Force -Path $G | Out-Null
Set-Location $REPO
$env:Path = (Join-Path (Get-ItemProperty 'HKLM:\SOFTWARE\R-core\R').InstallPath 'bin') + ';' + $env:Path
if (-not (Test-Path $BACI)) { throw "BACI dir not found: $BACI" }; if (-not (Test-Path $CACHE)) { throw "cache not found: $CACHE" }
$CKPT = Join-Path $REPO 'baci_hs92_v202601_elast_country_hs4_fs_checkpoint.rds'
$OUT2A = 'baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds'; $OUT2B = 'baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds'
function Prep-Dir([string]$d, [string]$s2a) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $c = Join-Path $d 'baci_hs92_v202601_elast_country_hs4_raw_cache.rds'
  if (-not (Test-Path $c)) { New-Item -ItemType HardLink -Path $c -Target $CACHE | Out-Null }
  if (-not (Test-Path (Join-Path $d 'baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds'))) { Copy-Item $STAGE1 (Join-Path $d 'baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds') }
  if ($s2a -and -not (Test-Path (Join-Path $d $OUT2A))) { Copy-Item $s2a (Join-Path $d $OUT2A) }
}
function File-Hash([string]$p) { if (Test-Path $p) { (Get-FileHash $p -Algorithm SHA256).Hash } else { '' } }
$log = Join-Path $G 'grid_session.log'
"### grid v3 start/resume : $(Get-Date -Format s) ###" | Tee-Object -FilePath $log -Append
$nDone = 0; $nRun = 0; $nFail = 0; $nStale = 0
foreach ($prior in @('log', 'level', 'share')) {
  $d2a = Join-Path $G "2a_$prior"; Prep-Dir $d2a $null
  $s2a = Join-Path $d2a $OUT2A
  if (Test-Path $s2a) { "=== 2a $prior : already done, skipping ===" | Tee-Object -FilePath $log -Append; $nDone++ }
  else {
    Remove-Item $CKPT -ErrorAction SilentlyContinue
    "=== 2a $prior : $(Get-Date -Format s) ===" | Tee-Object -FilePath $log -Append
    Rscript scripts\run_estimation.R --data $BACI --out-dir $d2a --stage 2a --product-sample $FRAC --product-seed $SEED --stage2-prior $prior --ncores $NCORES *> (Join-Path $d2a 'run.log')
    if (Test-Path $s2a) { $nRun++ } else { "2a $prior FAILED -- see $d2a\run.log" | Tee-Object -FilePath $log -Append; $nFail++; continue }
  }
  $runs = Join-Path $G "runs_$prior.csv"; 'config,split,path,prior,lambda,mode' | Set-Content $runs
  foreach ($lam in @('0.1', '0.01', '0.001')) {
    foreach ($mode in @('base', 'moments')) {
      $name = "${prior}_l${lam}_${mode}"
      $fullHash = File-Hash (Join-Path (Join-Path $G "${name}_full") $OUT2B)
      $splits = @('full'); if ($SPLIT_CONFIGS -contains $name) { $splits += @('A', 'B') }
      foreach ($split in $splits) {
        $d = Join-Path $G "${name}_$split"; $out = Join-Path $d $OUT2B
        if ($split -ne 'full' -and (Test-Path $out) -and $fullHash -ne '' -and (File-Hash $out) -eq $fullHash) {
          "=== $name $split : stale (identical to full), rerunning ===" | Tee-Object -FilePath $log -Append
          Remove-Item $d -Recurse -Force; $nStale++
        }
        Prep-Dir $d $s2a
        if (Test-Path $out) { "$name,$split,$out,$prior,$lam,$mode" | Add-Content $runs; $nDone++; continue }
        $extra = @(); if ($mode -eq 'moments') { $extra += @('--stage2-ref-export-moment', 'on', '--stage2-import-constant', 'on') }
        if ($split -eq 'A') { $extra += @('--maxyear', '2009') }; if ($split -eq 'B') { $extra += @('--minyear', '2010') }
        Remove-Item $CKPT -ErrorAction SilentlyContinue
        "=== $name $split : $(Get-Date -Format s) ===" | Tee-Object -FilePath $log -Append
        & Rscript scripts\run_estimation.R --data $BACI --out-dir $d --stage 2b --product-sample $FRAC --product-seed $SEED --stage2-prior $prior --shrinkage-lambda $lam --ncores $NCORES @extra *> (Join-Path $d 'run.log')
        if (Test-Path $out) { "$name,$split,$out,$prior,$lam,$mode" | Add-Content $runs; $nRun++ } else { "$name $split FAILED -- see $d\run.log" | Tee-Object -FilePath $log -Append; $nFail++ }
      }
    }
  }
  "=== scoring $prior : $(Get-Date -Format s) ===" | Tee-Object -FilePath $log -Append
  Rscript analysis\stage2_reliability.R --runs $runs --stage2a $s2a --out "results\stage2_reliability_$prior.json" --md "docs\results\stage2_reliability_$prior.md" *> (Join-Path $G "score_$prior.log")
}
"GRID DONE $(Get-Date -Format s) -- passes already complete: $nDone, stale halves rerun: $nStale, run now: $nRun, failed: $nFail" | Tee-Object -FilePath $log -Append
