# EverInit lab status (honest)

## Valid

- Workflow: `everinit-valid-ab.yml`
- Pinned patch under `.github/pinned/` (SHA-256 verified)
- Public `awaits_N` / `loops_N` (ashi009)
- MIR-valid sequential loops with opaque continue/exit (real backedge)
- Alternating A/B pairs; identities in every JSON row

## Invalid / retired (do not trust)

| Family | Why invalid |
| --- | --- |
| `same_local_loops` with unconditional `break` | No MIR backedge; straight-line |
| `storage_dead_reuse` lexical `{ let y }` | New MIR Local each block; not one local + StorageDead |
| Unconditional nested loops | No nested SCC convergence |
| Mutable `pull/160033.patch` URL | Not archival A/B |
| Block base-then-cand, 3 samples | Weak protocol |

## Pin

See `.github/pinned/IDENTITIES.md`.
