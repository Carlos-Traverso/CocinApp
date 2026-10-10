# Project Agent Workflow

## Orchestration and model preferences

- For substantial coding tasks, use the primary agent as the orchestrator. The user's preferred orchestrator model is GPT-6.1 Sol when the host allows choosing it.
- Delegate bounded, independent modules or investigations to subagents. Prefer GPT-6 Luna for subagents when model selection is available.
- Parallelize implementation and review when useful: let an implementation agent own a clearly bounded module while another agent audits completed changes or investigates risks. Keep the auditor independent and have it report findings; do not let it edit the same files as the implementation agent.
- Avoid overlapping write ownership. The orchestrator integrates results, resolves conflicts, and reports which work was delegated and reviewed.
- If a requested model is unavailable or the task is too small to benefit from delegation, explain the limitation briefly and proceed with the available setup.

## Engineering practices

- Follow this repository's existing architecture, conventions, and documentation.
- For complex changes, make a concise plan before implementation.
- When tests are part of the requested work, prefer test-first development and verify the behavior after implementation. Do not impose an arbitrary coverage target without project-specific evidence.
- Validate untrusted input at system boundaries, handle errors explicitly, and avoid exposing secrets or sensitive details.
- Review changes for correctness, security, and maintainability. Keep the review proportional to the change and report verification performed and any remaining risks.
- Use focused ECC-style skills and workflows when available and relevant; do not assume ECC is installed just because these practices are documented here.
