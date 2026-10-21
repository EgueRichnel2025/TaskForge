\# TaskForge Development Workflow



\## Purpose



This document defines the workflow used to develop, test, document, and maintain TaskForge.



The goal is to make every change understandable, verifiable, and traceable.



\## Development Lifecycle



Every meaningful change follows these steps:



1\. Understand the requirement and identify the expected result.

2\. Implement a small, focused change.

3\. Run the appropriate tests and quality checks.

4\. Review the changes before committing.

5\. Create a descriptive Git commit.

6\. Push the commit to GitHub.

7\. Update the documentation when necessary.



\## Commit Convention



Commit messages follow this structure:



`<type>(optional scope): <description>`



Common types:



\- `feat`: introduce a feature.

\- `fix`: correct a defect.

\- `test`: add or improve tests.

\- `docs`: add or update documentation.

\- `refactor`: restructure code without changing its intended behavior.

\- `build`: update build configuration or dependencies.

\- `ci`: modify continuous integration or delivery workflows.

\- `chore`: perform project maintenance.



Examples:



\- `docs: add project overview`

\- `feat(api): add health endpoint`

\- `test(api): cover health endpoint`

\- `fix(api): handle invalid task input`

\- `ci: automate test execution`



Each commit should represent one coherent change.



\## Change Review



Before creating a commit, review the working tree:



```bash

git status

git diff
