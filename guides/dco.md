# Developer Certificate of Origin (DCO)

The Developer Certificate of Origin (DCO) is a mechanism used to confirm that contributors have the legal right to submit their work. It is a simple declaration stating that you have the right to submit your contributions, either because the work is yours or you have the appropriate permissions and are willing to contribute under the project's licensing terms.

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

When making contributions to any repository in the Allianz Github organizations, contributors are required to include a sign-off statement in their commit messages. This sign-off is an explicit agreement to the DCO above.

To include the DCO sign-off in a Git commit, use the following command:

```bash
git commit -s -m "Your commit message here"
```

Adding the `-s` option appends a "Signed-off-by: Joe Doe joe.doe@example.com" line to the end of the commit message, signaling your compliance with the DCO. Ensure your real name is set in the git config `user.name` and a valid email address in `user.email`.