# Code Review Process

Git workflows are an important part of the code review processes. [Github Flow](https://docs.github.com/en/get-started/quickstart/github-flow) and Gitflow are the two most used processes. GitHub Flow is a more modern and simpler approach compared to Gitflow's comprehensive branching model. Given its extensive adoption by open-source projects, it is recommended to utilize GitHub Flow.

Working with Github Flow:
1. Create an issue, if not existing yet, to discuss what you want to implement
2. Fork the repository and create your branch from master
3. Push changes to your fork and open a pull request 
    * Fill in the required PR template, if exists
    * Add a summary of all major changes in the description
    * [Link](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue)  the pull request and the issue being resolved
    * Enable the option [allow maintainers edits](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/allowing-changes-to-a-pull-request-branch-created-from-a-fork) for faster merging
    * Apply [suggest changes](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/incorporating-feedback-in-your-pull-request) from reviewers. You can do so directly in the Github UI or commit changes to your fork
    * Mark each suggested change as [resolved](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/commenting-on-a-pull-request#resolving-conversations)
    * [Re-request a review](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/incorporating-feedback-in-your-pull-request#re-requesting-a-review) when you are done with all changes
5. Make sure automated tests do not have errors
    * With errors a PR might be ignored and not receive reviews. 
    * If you need a review despite test errors, then mark your PR as draft.