# workflows

CI Validate does not touch a host. It runs beside the others.

A push to `develop` starts Infra Apply Dev. When that apply succeeds, Apps Deploy Dev starts as its own run, the same way Apps Deploy Prod follows Infra Apply Prod. Its tests are the next job. A README under `ansible/` or `compose/` does not deploy. Tests Dev starts only for a push that changes test files and does not also deploy. GitHub reads the dev deploy trigger from `main`.

On `main`, Infra Apply Prod runs after the one approval. A successful apply starts Apps Deploy Prod, and its tests run after the deploy.

| Workflow | Does |
| --- | --- |
| `ci-validate.yml` | Format, lint, and the script self-tests. On a pull request and on a push to `develop` |
| `infra-plan-dev.yml` | Read-only plan of the dev workspace. Required before a merge to `develop` |
| `infra-plan.yml` | Read-only plan of the prod workspace. Required before a merge to `main` |
| `infra-apply-dev.yml` | Apply the dev workspace on every push to `develop`, or by hand |
| `infra-apply-prod.yml` | Apply prod. Asks once. A risky plan asks again |
| `apps-deploy-dev.yml` | Ansible, Compose, and Home Assistant on DEV, then the tests. After Infra Apply Dev succeeds, or by hand. A README does not deploy |
| `apps-deploy-prod.yml` | The same on prod, after a successful prod apply, or by hand (that hand run asks once) |
| `tests-dev.yml` | The DEV suites when no deploy is going to run, or by hand |
