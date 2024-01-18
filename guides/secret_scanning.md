# Secret Scanning

GitHub Secret Scanning is a security feature for identifying and mitigating exposed secrets within your repository, such as  passwords or tokens. This automated process is enabled by default and systematically scans commits, pull requests, and the entire Git history.

Out of the box, GitHub Secret Scanning supports a wide range of secrets types, including those for Azure, AWS, Atlassian, and others. For a detailed list, refer to the [Github documentation](https://docs.github.com/en/code-security/secret-scanning/secret-scanning-patterns#supported-secrets)

Additional secret types can be added by configuring custom secret patterns. Please write a mail to ospo@allianz.com to register secret patterns not supported by Github.

If GitHub Secret Scanning detects exposed secrets, take prompt action to rotate or invalidate the compromised secret.
