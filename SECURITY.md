# Security Policy

## Supported versions

Menu Hub is currently in active early development. Security fixes are provided
for the latest published release only. Before reporting a problem, please
confirm that it is reproducible with the newest release available from the
[Releases page](https://github.com/Talljack/menu-hub/releases/latest).

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please do not disclose a suspected vulnerability in a public issue, discussion,
social-media post, or pull request.

Report it privately through
[GitHub Private Vulnerability Reporting](https://github.com/Talljack/menu-hub/security/advisories/new).
Include the following when possible:

- the affected Menu Hub and macOS versions;
- the Mac architecture (Apple Silicon or Intel);
- steps to reproduce the issue;
- the impact and any proof of concept;
- relevant logs with personal information and local paths removed; and
- any suggested mitigation.

You should receive an acknowledgement within 5 business days. After the report
is validated, maintainers will coordinate a fix and disclosure timeline with
the reporter. Please allow a reasonable remediation period before publishing
details.

## Security scope

Reports about unauthorized Accessibility actions, unsafe restoration of menu
bar state, local-data exposure, code-signing or notarization failures, update or
release-artifact tampering, and privilege-boundary mistakes are in scope.

General feature requests, expected limitations of public macOS APIs, and
problems that require a modified or unsupported macOS installation should use a
regular GitHub issue instead.

Menu Hub does not request passwords, message contents, account credentials, or
network access. Never include those secrets in a report.
