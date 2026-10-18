---
name: spec-idea
description: Use when someone wants to propose an idea for the INITE Triad (or one that spans Auth, Billing and Brain) without writing code — turns it into a plain-language spec and files it as an issue in the right repo.
---

# /spec-idea — propose, don't build

Explain in plain words as you go. No code, no branches.

1. Restate the idea; ask at most 3 clarifying questions.
2. Route it with AGENTS.md "Which repo owns what". Cross-service or
   deployment/contract ideas are filed **here** (`inite-ai/inite-triad`);
   a single-service idea is filed in that service's repo
   (`inite-ai/inite-auth-service`, `inite-ai/inite-billing-service`,
   `inite-ai/inite-brain-service`). Say which and why.
3. Search first: `gh issue list -R <repo> --search "<key words>" --state all`.
4. Write the issue body with these headings: **What do you want to be
   possible?** · **Who is it for / why** · **How would you know it works?** ·
   **Which parts does it touch?** (Auth / Billing / Brain / the Triad
   deployment / not sure) · **Spec** (problem, visible behaviour, changes per
   repo, contract impact with rule ids — §7 overlap, B-3 verifiers first —
   risks, out of scope).
5. Show it, get a yes, then file:
   `gh issue create -R <repo> --title "<title>" --body-file <file>` (add
   `--label idea` for this repo). Without `gh`, give the person
   `https://github.com/<repo>/issues/new` and the text to paste.
6. Share the issue link and what happens next (a maintainer reviews it).
