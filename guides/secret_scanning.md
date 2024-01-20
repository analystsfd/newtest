# Secret Scanning

GitHub Secret Scanning is a security feature designed to identify and address exposed secrets, such as passwords or tokens. The process systematically scans commits, pull requests, and the entire Git history. GitHub Secret Scanning is enabled by default for all repositories within the Allianz GitHub organization.

By default, GitHub Secret Scanning supports a wide range of secret types, including those for Azure, AWS, Atlassian, and others. For a detailed list, refer to the [Github documentation](https://docs.github.com/en/code-security/secret-scanning/secret-scanning-patterns#supported-secrets)

Additional secret types can be added by configuring custom secret patterns. To register secret patterns not supported by GitHub, please send an email to [ospo@allianz.com](mailto:ospo@allianz.com).

In the event that GitHub Secret Scanning identifies exposed secrets, promptly take action to rotate or invalidate the compromised secret.