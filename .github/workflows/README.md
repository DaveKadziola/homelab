# workflows

CI Validate does not touch a host. It runs beside the others.

A push to `homelab-v2` starts Infra Apply Dev. If that push also changes a deploy path, Apps Deploy Dev starts at the same time, not after the apply. The tests inside Apps Deploy Dev run only after that deploy job. Tests Dev starts only for a push that changes test files and does not also deploy.

On `main`, Infra Apply Prod runs after the one approval. A successful apply starts Apps Deploy Prod, and its tests run after the deploy.

| Workflow | Does |
| --- | --- |
| `ci-validate.yml` | Format, lint, and the script self-tests. On a pull request and on a push to `homelab-v2` |
| `infra-plan-dev.yml` | Read-only plan of the dev workspace. Required before a merge to `homelab-v2` |
| `infra-plan.yml` | Read-only plan of the prod workspace. Required before a merge to `main` |
| `infra-apply-dev.yml` | Apply the dev workspace on every push to `homelab-v2`, or by hand |
| `infra-apply-prod.yml` | Apply prod. Asks once. A risky plan asks again |
| `apps-deploy-dev.yml` | Ansible, Compose, and Home Assistant on DEV, then the tests. On a push that changes a deploy path, or by hand |
| `apps-deploy-prod.yml` | The same on prod, after a successful prod apply, or by hand (that hand run asks once) |
| `tests-dev.yml` | The DEV suites when no deploy is going to run, or by hand |
