# Releasing an Open Source Project 🛳️

The following steps must be taken to release a new open source project:

1. **Register your release**. Complete the registration form to express your intent to release non-product code (such as utility libraries, tools, and sample code).
2. **Get approval**. Obtain business line approval.

3. **Name your project**. 
   - Check that it does [not conflict with an existing project](http://ivantomic.com/projects/ospnc/) or infringe on any [trademarks](https://www.uspto.gov). 
   - Don’t use a Allianz brand name.
   - Avoid using a third-party brand name. In certain cases you can use them as descriptors. For example, you can use “Test Libraries for Java” but don’t call something “Java Test Libraries.”
   - Don’t use unclear names. e.g. “Foundation Server”

4. **Remove sensitive assets**.
     - Remove any trademarks or product icons.
     - Remove all internal dependencies or references in your code and documentation. This includes any references to server names, binaries, databases, or email addresses. 
     - Remove comments or documentation references to JIRA links, internal code names, and anything else that wouldn’t make sense to external developers.
     - Remove embarrassing content (curse words, poor coding practices).
     - Remove all embedded credentials, passwords, or other secrets that may be mistakenly added to the code or a configuration file. (Note: we expect secrets to be managed outside of source code, but we ask you to check nonetheless.)
     - Drop the revision history.
     - Conduct a static code analysis for vulnerabilities.

4. **Prepare code for release**.

     - Use consistent code conventions, clear function/method/variable names, and a sensible public API.
     - Keep clear comments, document intentions and edge cases.
     - Ensure the distribution mechanism is as convenient, standard, and low-overhead as possible (RubyGems, Homebrew, Bower, Maven, NuGet, etc.)
     - Enable GitHub Actions for continuous integration.
     - Use inclusive language.

5. **Code license**. 
     - Pick on of the prefered licenses - other licenses must be cleared with legal.
     - Review all license dependencies for compatibility with the chosen license.
     - If your repository vendors third-party OSS which is not managed/vendored by a dependency manager (e.g. `RubyGems`), describe its use and its license 
in a `NOTICE` file. 
     - Add copyright and license headers  at the top of each file (optional):

     ```javascript
     // SPDX-FileCopyrightText: Allianz and others
     // SPDX-License-Identifier: MIT
     ```

6. **Publish the code**. Once business approval is granted and code is prepared, create an issue in `XXX` repo and request that a new GitHub repository is created
7. **Going forward**. Ensure:
   - **Staffing**. Ensure at least one team member is committed to managing community interactions merging pull requests, giving feedback, releasing new versions.
   - **Maintaining**. Make your life easier as an open source maintainer, [from documenting processes to leveraging your community](https://opensource.guide/best-practices/).
   - **Build welcoming communities**. [Build a community that encourages people](https://opensource.guide/building-community/) to use, contribute to, and share your project.


## Attribution

This release process is adapted from the GitHub [relase process template](https://github.com/github/github-ospo/blob/main/policies/releasing.md) and the [Yahoo release process](https://yahoo.github.io/oss-guide/docs/publishing/prepare.html)
