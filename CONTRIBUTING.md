# Contributing

1. `main` is protected: nobody pushes to it directly.
2. Branch per task: `week<N>/m<member>-<topic>`, e.g. `week1/m2-alb`.
3. Commit messages: `type(scope): short description` – `feat`, `fix`, `docs`, `chore`; e.g. `feat(compute): private RDS subnet group`.
4. Before pushing: `terraform fmt -recursive terraform` and `terraform -chdir=terraform/envs/dev validate` (or `make check`).
5. Open a pull request with the template, paste the `plan` summary (no secrets), get one teammate's approval, wait for green CI, **Squash and merge**.
6. Only one person runs `apply` at a time – announce it in the team chat.
7. Evidence goes in `docs/evidence/week<N>/`. Blur account IDs, keys and public IPs in screenshots you publish.
8. Never commit: `*.tfstate`, `terraform.tfvars`, AWS keys, `.pem` files, the downloaded VPN configuration.
9. End of session: `make sleep` and note it in the team chat.
