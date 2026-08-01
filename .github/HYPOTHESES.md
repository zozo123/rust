# EverInit GitHub Actions hypothesis lab

Disposable workflows on branch `validation/everinit-ci` for
[rust-lang/rust#160033](https://github.com/rust-lang/rust/pull/160033)
(`InitIndex` → `Local` for `EverInitializedPlaces`).

**Not for merge into rust-lang/rust.** Evidence collection only.

## SHAs

| Role | SHA |
| --- | --- |
| Base (pre-#160033) | `09ee43b2d6055539771bee8ac30a6e56eb4db773` |
| Candidate (#160033 tip) | `e7339de13da94243e4e0f0ee173be9be44164ab2` |

## Workflows (fan-out)

| Workflow | Jobs (approx) | Purpose |
| --- | ---: | --- |
| `everinit-lab.yml` | 2 builds + 50 hyp + 12 repro + 20 scale + 2 time-passes + report | Mega matrix |
| `everinit-ab.yml` | 2 builds + measure | Original full A/B |
| `everinit-hypotheses.yml` | 2 builds + 48 A/B cells + report | Family × N |
| `everinit-scale-curve.yml` | 2 builds + 42 points + report | Fine N curve |
| `everinit-await-cliff.yml` | 2 builds + 15 await + 7 hold + report | Async cliff |
| `everinit-falsify-unique.yml` | 2 builds + 18 cells + report | Unique locals falsify |
| `everinit-cfg-joins.yml` | 2 builds + 30 cells + report | CFG/join shapes |
| `everinit-base-only.yml` | 1 build + sweep | Base baseline |

Push to `validation/everinit-ci` triggers **all** of the above (high concurrency).

## Hypotheses

| ID | Family | Prediction under #160033 |
| --- | --- | --- |
| H1 | `same_local_loops` | ratio ≪ 1 (lattice collapse) |
| H2 | `unique_locals` (1 init each) | ratio ≈ 1 (falsify domain-width-only) |
| H2b | unique × k inits | ratio drops as k grows |
| H3 | `storage_dead_reuse` | medium win |
| H4 | `awaits` | large win; base superlinear |
| H5 | `seq_loops` | large win |
| H6 | `nested_loops` | large win |
| H7 | `diamond_join` / CFG | win if multi InitIndex same Local |
| H8 | `multi_assign_block` | win (many InitIndex, one Local) |
| H9 | `branch_partial` | moderate |
| H10 | public hold/drop suite | scout for #159943 adjacency |

## Gates

- Primary: `awaits_800/1600` or generated awaits n≥800 → cand/base **&lt; 0.5**
- Falsify: unique n large, k=1 → ratio **&gt; 0.8**
- Scale: base time grows superlinear in n; cand near-linear

## How to re-run

```bash
gh workflow run "EverInit lab (mega matrix)" --repo zozo123/rust --ref validation/everinit-ci
gh workflow run "EverInit scale curve A/B" --repo zozo123/rust --ref validation/everinit-ci
gh workflow run "EverInit await cliff A/B" --repo zozo123/rust --ref validation/everinit-ci
gh workflow run "EverInit falsify unique-locals" --repo zozo123/rust --ref validation/everinit-ci
gh workflow run "EverInit CFG joins A/B" --repo zozo123/rust --ref validation/everinit-ci
gh workflow run "EverInit hypotheses (candidate + A/B matrix)" --repo zozo123/rust --ref validation/everinit-ci
gh run list --repo zozo123/rust --branch validation/everinit-ci
```

## Note on concurrency / minutes

Each workflow rebuilds stage1 (~1–3h × 2 variants). Many parallel workflows burn a lot of
GitHub Actions minutes. Prefer the single **EverInit lab** mega matrix if minutes are tight;
use the full set when maximizing parallel evidence collection.
