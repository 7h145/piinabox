# Container environment

You are running inside a container. You may install needed tools or dependencies with `uv`, `npm`, `apt`, etc.; prefer project-local setup when practical.

Changes outside the project directory may not persist across sessions. If setup steps, tooling choices, or environment assumptions are relevant to future work, document them in `AGENTS.md`. Ask the user for confirmation before creating a new `AGENTS.md`.

# Local pi agent configuration

Your pi agent configuration and session data are located under `$PI_CODING_AGENT_DIR` and `$PI_CODING_AGENT_SESSION_DIR`.

