---
controls: [ir-8.1]
owner: CEO
---

# Incident response plan: breaches involving PII

Effective 2026-10-07. Reviewed at least every 3 months.

## What PII exists

The environment holds only workforce identity data: the names, email
addresses and sign-in history of its Okta users, and the GitHub
accounts of its contributors. Substrate hashes GitHub author identities
before writing them anywhere. No customer or federal data exists in the
environment (`security-plan.md`).

A breach is any loss of control over that data, for example:

- unauthorized access to the Okta org or its System Log;
- exposure of an Okta export or a substrate artifact holding raw
  identity data.

## Deciding whether to notify (IR-8(1)(a))

Within 2 business days of discovering a suspected breach, the
Administrator:

1. Records what data was involved, whose it was, and how it was
   exposed.
2. Decides, using the privacy requirements below, whether notice is
   owed to:
   - the affected individuals;
   - any organization whose data was involved;
   - any oversight body.
3. Records the decision and its reasons, even when the decision is not
   to notify.
4. Has the Independent Reviewer check the decision before it is final.

## Assessing harm (IR-8(1)(b))

For each affected individual, the assessment considers:

- **Harm:** could the data be used for account takeover, phishing or
  impersonation?
- **Embarrassment or inconvenience:** what was revealed, and does the
  person need to take action?
- **Unfairness:** could the exposure affect how the person is treated?

Mitigations offered according to the assessment:

- reset the affected credentials and re-enroll authenticators;
- revoke exposed tokens and keys;
- tell the individual exactly what was exposed and what to watch for.

## Applicable privacy requirements (IR-8(1)(c))

- The breach notification law of each US state where an affected
  individual lives.
- The terms of any supplier whose service was involved: AWS, Okta or
  GitHub.
- If the environment ever holds federal information, which it does
  not today, the incident reporting requirements of the agency
  customer and of FedRAMP. This plan must be revised before that
  happens.
