# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through GitHub: open the repository's **Security** tab
and choose **Report a vulnerability**. Do not open a public issue, pull request or
discussion for a suspected vulnerability.

Please include:

- what is affected (version, commit or deployment),
- how to reproduce it, or a proof of concept,
- the impact you expect.

You can expect an acknowledgement within 3 working days and a status update at
least every 7 days until the report is resolved. Please give us a reasonable
chance to release a fix before disclosing publicly.

## If a secret is exposed

1. Revoke and rotate the credential immediately. Removing it from the repository does
   not make it safe again.
2. Check the provider's audit logs for use of the credential.
3. Remove it from the repository history if the repository is, or may become, public.
4. Report it through the channel above so the cause can be fixed.

## Supported versions

Only the latest release and the `main` branch receive security fixes unless stated
otherwise in the README.
