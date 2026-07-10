# Security Policy

## Supported Versions

Security fixes are developed on `yime-stable` and included in the next published Yime installer. The latest published release and the current `yime-stable` branch receive security attention; older development snapshots are not maintained as separate supported versions.

## Reporting A Vulnerability

Do not publish exploit details, private user data, signing material, or a working proof of concept in a public issue.

Preferred reporting path:

1. Use GitHub's private vulnerability reporting / Security Advisory feature for this repository.
2. Include the affected version or commit, Windows version, impact, prerequisites, and minimal reproduction steps.
3. Attach logs only after removing user text, paths, dictionary contents, account names, and other identifying data.

If private vulnerability reporting is unavailable, open a public issue containing only a request for a private maintainer contact channel. Do not include sensitive technical details in that issue.

## Relevant Security Boundaries

Reports are especially useful when they involve:

- TSF/COM registration or loading of `PIMETextService.dll`
- PIMELauncher or `server.exe` process creation and IPC
- execution of packaged tools or `rime_deployer.exe`
- installer/uninstaller privilege boundaries and Program Files writes
- untrusted dictionary, YAML, TSV, JSON, log, or import-file parsing
- command-line argument quoting or path traversal
- Authenticode signing, certificate handling, or release artifact tampering
- exposure of user input, user dictionaries, logs, or synchronized Rime data

## Handling Expectations

- Maintainers will first confirm receipt and determine whether the report is security-sensitive.
- Fixes should include a regression test when a safe automated reproduction is possible.
- Release artifacts must follow [the release and signing guide](docs/YIME_RELEASE_AND_SIGNING.md).
- Public disclosure should wait until a fix or mitigation is available and affected users have a reasonable update path.

## Development Builds

Development builds may be unsigned and can be blocked by Smart App Control. Do not disable platform security protections as a project-wide workaround. Public release binaries should use a trusted RSA code-signing certificate; self-signed development certificates are not a substitute for public distribution signing.

