# Security policy

**Do not open a public issue for a vulnerability.** Email
**security@inite.ai** with what is wrong, how to reproduce it, and the
versions affected (`AUTH_VERSION`, `BRAIN_VERSION`, `BILLING_VERSION` from
your `.env`).

In scope here: the deployment wiring (`compose.yaml`, `bootstrap.sh`,
`verify.sh`) and the token & compatibility contract
([docs/compatibility.md](docs/compatibility.md)) — for example a rule that
lets a token reach a service it was not minted for. A flaw inside one
service's code is reported the same way; each service repo's own
`SECURITY.md` lists its scope.
