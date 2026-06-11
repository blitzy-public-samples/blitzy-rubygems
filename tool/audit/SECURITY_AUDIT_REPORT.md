# RubyGems + Bundler — Dependency Security Audit Report

This report documents a dependency security audit of the bundled development,
linting, RuboCop, Standard, release, test, and vendoring tool gemsets that ship
under `tool/bundler/*_gems.rb.lock`, the remediation applied, the triage of the
total dependency risk surface, and the CI integration that keeps the result
green going forward.

- **Scanner:** [`bundler-audit`](https://github.com/rubysec/bundler-audit) `~> 0.9` against the community [`ruby-advisory-db`](https://github.com/rubysec/ruby-advisory-db).
- **Harness:** [`tool/audit/audit.rb`](./audit.rb) — scans all seven lockfiles at once, de-duplicates advisories, counts the risk surface, and acts as a CI fail-gate.
- **Triage policy:** [`.bundler-audit.yml`](../../.bundler-audit.yml) (fix-first; ignore list empty).
- **CI:** [`.github/workflows/security-audit.yml`](../../.github/workflows/security-audit.yml) (daily schedule + pull-request + manual dispatch).

> **Scope note.** This audit is the accepted deliverable for this repository.
> The original Agent Action Plan referenced advisory **GHSA-gqqj-85qm-8qhf**
> against the unrelated npm package `paperclipai/paperclip`; that advisory does
> **not** apply to this pure-Ruby RubyGems + Bundler repository (an exhaustive
> search found zero occurrences of every artifact it names). The work captured
> here is the RubyGems/Bundler dependency security scan and remediation that was
> requested in its place.

## 1. Result transition (before → after)

| Metric | Baseline | After remediation |
|---|---:|---:|
| Unique advisories (total) | **34** | **0** |
| Unique advisories (actionable) | 34 | 0 |
| Unique advisories (triaged/accepted) | 0 | 0 |
| Vulnerable gems | **9** | **0** |
| Insecure sources | 0 | 0 |
| Risk surfaces (resolved gem specs) | 213 | 214 |
| Fail-gate result | **FAIL** (exit 1) | **PASS** (exit 0) |

The single-unit increase in risk surfaces (213 → 214) is the expected
consequence of re-resolving the upgraded graphs: `release_gems` gained
`bigdecimal` (a new transitive dependency of the newer `aws-sdk-core`), while
`test_gems` dropped the now-unneeded `ruby2_keywords` — a net of +1.

The post-remediation scan was re-run against a freshly-updated advisory database
to rule out a stale-database false negative; it remained at **0 actionable
advisories**.

## 2. Risk surface by lockfile

| Lockfile | Baseline specs | After specs | Advisories fixed |
|---|---:|---:|---:|
| `dev_gems.rb.lock` | 30 | 30 | 6 (nokogiri ×5, rexml ×1) |
| `lint_gems.rb.lock` | 33 | 33 | 1 (rexml ×1) |
| `release_gems.rb.lock` | 20 | 22 | 5 (addressable, aws-sdk-s3, faraday ×2, uri) |
| `test_gems.rb.lock` | 26 | 25 | 23 (rack ×20, rack-session ×2, sinatra ×1) |
| `rubocop_gems.rb.lock` | 43 | 43 | 0 (already clean) |
| `standard_gems.rb.lock` | 47 | 47 | 0 (already clean) |
| `vendor_gems.rb.lock` | 14 | 14 | 0 (already clean) |
| **Total** | **213** | **214** | **34** (raw count is 35 because `rexml` appears in two lockfiles; 34 are unique advisory IDs) |

> The per-lockfile "advisories fixed" column sums to 35 because the single
> `rexml` advisory (`GHSA-c2f4-jgmc-q2r5`) appears in both `dev_gems` and
> `lint_gems`. There are **34 unique advisory IDs**.

## 3. Remediation summary

Every advisory had a published fix. Remediation was performed by re-resolving
each affected lockfile with the project's development Bundler
(`ruby bundler/bin/bundle lock --update <gems>`), which upgrades the named gems
(and only the transitive dependencies required to satisfy them), regenerates the
`CHECKSUMS`, and preserves `BUNDLED WITH 4.0.0.dev`. The three already-clean
lockfiles were left untouched (minimal, targeted change).

| Gem | Advisories | From | To | Direct/Transitive | Lockfile(s) |
|---|---:|---|---|---|---|
| `addressable` | 1 | 2.8.7 | 2.9.0 | transitive | release_gems |
| `aws-sdk-s3` | 1 | 1.182.0 | 1.225.1 | direct (`~> 1.87`) | release_gems |
| `faraday` | 2 | 2.12.2 | 2.14.2 | transitive | release_gems |
| `nokogiri` | 5 | 1.18.6 | 1.19.3 | transitive | dev_gems |
| `rack` | 20 | 3.1.15 | 3.2.6 | direct (`~> 3.1`) | test_gems |
| `rack-session` | 2 | 2.1.0 | 2.1.2 | transitive | test_gems |
| `rexml` | 1 | 3.4.1 | 3.4.4 | transitive | dev_gems, lint_gems |
| `sinatra` | 1 | 4.1.1 | 4.2.1 | direct (`~> 4.1`) | test_gems |
| `uri` | 1 | 1.0.3 | 1.1.1 | transitive | release_gems |

All upgrades stay within each gemfile's existing version constraint, so the
public dependency requirements were not changed — only the resolved versions.

## 4. Risk surface triage (214 surfaces)

The total third-party attack surface was enumerated and classified:

- **By source:** 210 specs resolve from `rubygems.org` (HTTPS); 4 resolve from
  `github.com` (HTTPS, the `vendor_gems` `github:` pins). **0 insecure
  (non-HTTPS / `git://`) sources.**
- **By platform:** 188 generic-platform specs + 26 precompiled platform-variant
  binaries (native gems such as `nokogiri`, `racc`, `json`, `psych`, `date`,
  shipping per-OS/arch builds). The 26 variants are alternate builds of the same
  logical dependency, not additional gems.
- **Unique gem names:** 107.

**Triage decisions:**

| Class | Count | Disposition |
|---|---:|---|
| Surfaces with a known advisory at baseline | 9 gems / 34 advisories | **Remediated** (upgraded to patched versions) |
| Surfaces from non-HTTPS sources | 0 | No action required |
| Surfaces accepted/ignored (suppressed) | 0 | Nothing suppressed — every advisory was fixable |
| Remaining surfaces (no known advisory) | balance | **Monitored** by the daily CI fail-gate |

The triage policy is codified in `.bundler-audit.yml` with an intentionally
empty `ignore:` list. Should an advisory ever need to be accepted, it must be
listed there with an inline justification; the harness still prints ignored
advisories (labelled "triaged"), so nothing is ever silently suppressed.

## 5. Continuous enforcement (CI)

`.github/workflows/security-audit.yml` keeps the result green:

- **Schedule:** daily at 07:00 UTC — detects newly-disclosed advisories against
  already-locked gems, independent of code changes.
- **Pull request / push:** runs when any dependency lockfile or the audit tooling
  changes, blocking regressions before merge.
- **Manual:** `workflow_dispatch`.
- **Steps:** set up Ruby 3.4.5 → install `bundler-audit` → **refresh the
  advisory database** (`bundler-audit update`) → generate the Markdown report
  (uploaded as a build artifact) → **fail-gate** (`ruby tool/audit/audit.rb`,
  which exits non-zero on any actionable advisory).

## 6. How to run and regenerate this report

```bash
# One-time: install the scanner and fetch the advisory database
gem install bundler-audit
bundler-audit update

# Scan every lockfile (text report + fail-gate; exit 1 if anything is found)
ruby tool/audit/audit.rb

# Refresh the advisory DB and scan in one step
ruby tool/audit/audit.rb --update

# Regenerate this report
ruby tool/audit/audit.rb --format markdown --output tool/audit/SECURITY_AUDIT_REPORT.md

# Machine-readable output
ruby tool/audit/audit.rb --format json
```

To remediate a future finding, upgrade the affected gem in its lockfile and
re-install frozen:

```bash
# Re-resolve only the affected gem(s), preserving BUNDLED WITH
BUNDLE_GEMFILE="$PWD/tool/bundler/<name>_gems.rb" BUNDLE_PATH__SYSTEM=true \
  ruby "$PWD/bundler/bin/bundle" lock --update <gem> [<gem> ...]

# Verify the lockfile is consistent and install the patched versions
BUNDLE_GEMFILE="$PWD/tool/bundler/<name>_gems.rb" BUNDLE_PATH__SYSTEM=true \
  BUNDLE_FROZEN=true ruby "$PWD/bundler/bin/bundle" install
```

## Appendix A — Remediated advisories (34)

| Gem | GHSA | CVE | Severity | Fixed by |
|---|---|---|---|---|
| addressable | GHSA-h27x-rffw-24p4 | CVE-2026-35611 | high | `>= 2.9.0` |
| aws-sdk-s3 | GHSA-2xgq-q749-89fq | CVE-2025-14762 | medium | `>= 1.208.0` |
| faraday | GHSA-33mh-2634-fwr2 | CVE-2026-25765 | medium | `~> 1.10.5 OR >= 2.14.1` |
| faraday | GHSA-5rv5-xj5j-3484 | CVE-2026-33637 | medium | `>= 2.14.2` |
| nokogiri | GHSA-353f-x4gh-cqq8 | — | unknown | `>= 1.18.9` |
| nokogiri | GHSA-5w6v-399v-w3cc | — | unknown | `>= 1.18.8` |
| nokogiri | GHSA-c4rq-3m3g-8wgx | — | high | `>= 1.19.3` |
| nokogiri | GHSA-v2fc-qm4h-8hqv | — | medium | `>= 1.19.3` |
| nokogiri | GHSA-wx95-c6cv-8532 | — | medium | `>= 1.19.1` |
| rack | GHSA-47m2-26rw-j2jw | CVE-2025-49007 | unknown | `>= 3.1.16` |
| rack | GHSA-p543-xpfm-54cp | CVE-2025-61770 | high | `>= 3.2.2` |
| rack | GHSA-w9pc-fmgc-vxvw | CVE-2025-61771 | high | `>= 3.2.2` |
| rack | GHSA-wpv5-97wm-hp9c | CVE-2025-61772 | high | `>= 3.2.2` |
| rack | GHSA-r657-rxjc-j557 | CVE-2025-61780 | medium | `>= 3.2.3` |
| rack | GHSA-6xw4-3v39-52mm | CVE-2025-61919 | high | `>= 3.2.3` |
| rack | GHSA-mxw3-3hh2-x2mh | CVE-2026-22860 | high | `>= 3.2.5` |
| rack | GHSA-whrj-4476-wvmp | CVE-2026-25500 | medium | `>= 3.2.5` |
| rack | GHSA-vgpv-f759-9wx3 | CVE-2026-26961 | low | `>= 3.2.6` |
| rack | GHSA-qfgr-crr9-7r49 | CVE-2026-32762 | medium | `>= 3.2.6` |
| rack | GHSA-v569-hp3g-36wr | CVE-2026-34230 | medium | `>= 3.2.6` |
| rack | GHSA-7mqq-6cf9-v2qp | CVE-2026-34763 | medium | `>= 3.2.6` |
| rack | GHSA-h2jq-g4cq-5ppq | CVE-2026-34785 | high | `>= 3.2.6` |
| rack | GHSA-q4qf-9j86-f5mh | CVE-2026-34786 | medium | `>= 3.2.6` |
| rack | GHSA-x8cg-fq8g-mxfx | CVE-2026-34826 | medium | `>= 3.2.6` |
| rack | GHSA-v6x5-cg8r-vv6x | CVE-2026-34827 | high | `>= 3.2.6` |
| rack | GHSA-8vqr-qjwx-82mw | CVE-2026-34829 | high | `>= 3.2.6` |
| rack | GHSA-qv7j-4883-hwh7 | CVE-2026-34830 | medium | `>= 3.2.6` |
| rack | GHSA-q2ww-5357-x388 | CVE-2026-34831 | medium | `>= 3.2.6` |
| rack | GHSA-g2pf-xv49-m2h5 | CVE-2026-34835 | medium | `>= 3.2.6` |
| rack-session | GHSA-9j94-67jr-4cqj | CVE-2025-46336 | medium | `>= 2.1.1` |
| rack-session | GHSA-33qg-7wpp-89cq | CVE-2026-39324 | unknown | `>= 2.1.2` |
| rexml | GHSA-c2f4-jgmc-q2r5 | CVE-2025-58767 | unknown | `>= 3.4.2` |
| sinatra | GHSA-mr3q-g2mv-mr4q | CVE-2025-61921 | unknown | `>= 4.2.0` |
| uri | GHSA-j4pr-3wm6-xx2r | CVE-2025-61594 | high | `>= 1.0.4` |

_The "Fixed by" column shows the minimum applicable patched requirement for the
3.x / current series; the resolved versions (Section 3) meet or exceed these._
