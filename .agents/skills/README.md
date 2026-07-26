# Repository-local agent skills

These skills follow the [Agent Skills](https://agentskills.io/) directory format and are kept with the homelab source so coding-agent harnesses can use the same operational guidance as Hermes.

## Included skills

- `k3s-homelab-gitops` — repository/cluster topology, Flux workflows, safe rollout recipes, and homelab-specific verification.
- `stateful-database-gitops-rollouts` — backup-first rollout discipline for schema-changing stateful applications.

Harnesses that discover `.agents/skills/` can load these directly. In harnesses without automatic discovery, read the matching `SKILL.md` before changing manifests or operating the cluster. Supporting material is under each skill's `references/` directory and should be loaded only when relevant.

Secrets are deliberately excluded. Never add kubeconfig data, plaintext Kubernetes Secrets, credentials, tokens, or decrypted SealedSecret content here.
