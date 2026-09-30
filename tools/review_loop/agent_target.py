"""Resolve an explicit agent identity without mixing provider namespaces."""
import os
from typing import Optional, Tuple
from uuid import UUID

AGENT_PROVIDERS = ("antigravity", "codex")


def validate_target(conversation_id: str, agent_provider: str) -> Tuple[str, str]:
    conversation_id = str(conversation_id or "").strip()
    if agent_provider not in AGENT_PROVIDERS:
        raise ValueError(f"Unsupported agent provider: {agent_provider}")
    if not conversation_id:
        raise ValueError("A conversation ID is required.")
    if agent_provider == "codex":
        try:
            if str(UUID(conversation_id)) != conversation_id.lower():
                raise ValueError()
        except ValueError as exc:
            raise ValueError("Codex requires the exact thread UUID, not a name or --last.") from exc
    return conversation_id, agent_provider


def resolve_agent_target(
    explicit_id: Optional[str], agent_provider: Optional[str], state, branch: str
) -> Tuple[str, str]:
    if agent_provider is not None and agent_provider not in AGENT_PROVIDERS:
        raise ValueError(f"Unsupported agent provider: {agent_provider}")
    environment = {
        "antigravity": (os.environ.get("ANTIGRAVITY_CONVERSATION_ID") or "").strip(),
        "codex": (os.environ.get("CODEX_THREAD_ID") or "").strip(),
    }
    present = [name for name, value in environment.items() if value]
    remembered = state.get_branch_target(branch)
    explicit_id = (explicit_id or "").strip()
    if agent_provider is None:
        if explicit_id:
            matching = [name for name, value in environment.items() if value == explicit_id]
            if len(matching) > 1:
                raise ValueError("Conversation matches both environments; specify --agent explicitly.")
            provider = matching[0] if matching else (
                remembered[1] if remembered and remembered[0] == explicit_id else "antigravity"
            )
            return validate_target(explicit_id, provider)
        if len(present) > 1:
            raise ValueError("Both agent environments are set; specify --agent explicitly.")
        if present:
            provider = present[0]
            return validate_target(environment[provider], provider)
        if remembered:
            return validate_target(*remembered)
    else:
        if explicit_id or environment[agent_provider]:
            return validate_target(explicit_id or environment[agent_provider], agent_provider)
        if remembered and remembered[1] == agent_provider:
            return validate_target(*remembered)
    raise ValueError("No matching agent conversation. Supply --agent and --conversation-id, or the matching agent environment variable.")
