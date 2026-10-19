# Security

Sofa is experimental software for a trusted home network. It is not a replacement for network isolation and is not an audited security product. TV firmware and remote-control services vary.

The bridge pins the TV’s certificate after the user verifies its address. Pairing secrets are kept in macOS Keychain and are not intentionally logged. Volume uses the TV’s local UPnP service; that service is not encrypted. Public client certificate material in Resources/certs is intentionally shared protocol material from the credited upstream project, not a personal signing key or a user’s pairing token.

Please report vulnerabilities privately through the repository’s Security → Report a vulnerability option. Include a minimal reproduction with synthetic data, not real pairing credentials. Only the latest beta receives fixes. No response-time guarantee is offered.
