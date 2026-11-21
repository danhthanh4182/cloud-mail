# Harness / orchestration / guardrails

The harness is executable project validation plus a declarative DAG, not a claim of an autonomous running service. `verify` checks document/source integrity; `release-check` is a separate blocking gate and is expected to fail during design.

Handoff protocol: coordinator assigns task/revision/spec/allowed files/commands → worker implements one tested slice → Standards and Spec reviewers report independently → coordinator resolves findings → QA records actual evidence → user authorizes merge/deploy when relevant. Parallel tasks require no shared files or unresolved contract dependencies. Never make workers wait on circular dependencies.

Worker output must include changed files, requirement IDs, exact checks/results, known gaps and blockers. Failed checks return to the owning task; escalation reports the concrete missing decision/configuration. No auto-retry that spends API quotas, sends mail or mutates production. Reviewers cannot approve their own work. Any local orchestration runner must preserve these gates.

Approval/evidence JSON are auditable records, not proof that a user said something. Automation must not mark them approved or passed without the referenced actual event. Current Orca status is unavailable; installing/running a real scheduler is separate from these checked-in files.
