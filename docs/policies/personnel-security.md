---
controls: [ps-2, ps-9]
owner: CEO
---

# Position risk and position descriptions

Effective 2026-10-07. Reviewed at least every 3 months.

## Position risk designations (PS-2)

| Position | Risk designation | Why |
|---|---|---|
| Administrator | High | Full administrative access to every component, and the ability to temporarily lift branch protection |
| Independent Reviewer | Moderate | No administrative access, but approval authority over every change to `main`, including these documents |

These two are the only positions. Machine identities are not positions;
`access-control.md` covers them.

**Screening criteria.**

- **Administrator:** a Rookwright founder whose identity is known
  personally to the company.
- **Independent Reviewer:**
  - identity known personally to the Administrator;
  - not the author of any change they approve;
  - willing to read each change before approving it.

The environment holds no customer or federal data, so no formal
background investigation is required. Before it ever does, these
criteria must be raised to what the agency customer and FedRAMP
require.

Designations and criteria are reviewed at each quarterly review, and
whenever a position is added or its access changes.

## Position descriptions (PS-9)

**Administrator.** Builds and operates the environment. Security and
privacy responsibilities:

- keep administrator sign-in phishing-resistant and device-bound;
- keep collector identities read-only;
- run substrate as `continuous-monitoring.md` requires, and fix or
  explain findings;
- never approve their own changes, and record any branch-protection
  bypass;
- lead breach response under `incident-response-pii.md`;
- keep these documents current.

**Independent Reviewer.** Security and privacy representative on
change control (`change-management.md`). Security and privacy
responsibilities:

- read each pull request before approving it, and refuse any that
  weakens a property in `security-plan.md` without saying so;
- check that a change touching the boundary, suppliers, critical
  assets or PII updates the matching document;
- check notification decisions under `incident-response-pii.md`;
- review these documents at least every 3 months.
