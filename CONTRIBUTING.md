# Contributing

Thank you for contributing to this construct.

## Structure

```
construct.yaml              # Manifest — skills, commands, metadata
identity/
  persona.yaml              # Cognitive frame and voice
  expertise.yaml            # Domain knowledge and boundaries
skills/                     # Skill implementations
  <skill-name>/
    index.yaml              # Metadata + capability routing hints
    SKILL.md                # Instructions and workflow
commands/                   # Slash command prompt templates
schemas/                    # Validation schemas
```

## Adding a Skill

1. Create the skill directory: `skills/my-skill/`

2. Define metadata in `skills/my-skill/index.yaml`:
   ```yaml
   slug: my-skill
   name: "My Skill"
   description: "What this skill does"
   version: 1.0.0

   capabilities:
     model_tier: sonnet          # haiku | sonnet | opus
     danger_level: safe          # safe | moderate | high | critical
     effort_hint: small          # small | medium | large
     downgrade_allowed: true
     execution_hint: sequential  # parallel | sequential
     requires:
       native_runtime: false
       tool_calling: true
       thinking_traces: false
       vision: false
   ```

3. Write instructions in `skills/my-skill/SKILL.md`:
   - **Purpose** — when and why to use this skill
   - **Workflow** — step-by-step execution instructions
   - **Boundaries** — what the skill does NOT do

4. Register in `construct.yaml`:
   ```yaml
   skills:
     - slug: my-skill
       path: skills/my-skill
   ```

5. Optionally create a command in `commands/my-command.md` that invokes it

## Adding a Command

Commands are markdown prompt templates in `commands/`. Each command should:

- Establish the agent identity
- Reference which skill to execute
- Define constraints and output expectations

Register in `construct.yaml`:
```yaml
commands:
  - name: my-command
    path: commands/my-command.md
```

## Updating Identity

When expanding the construct's scope:

- Add new domains to `identity/expertise.yaml` with honest depth ratings (1-5)
- Update boundaries when the construct's refusal scope changes
- Update persona only if the construct's cognitive approach fundamentally shifts

## Validation

CI runs on every push and PR. Validate locally:

```bash
yq eval '.' construct.yaml
yq eval '.' identity/persona.yaml
yq eval '.' identity/expertise.yaml
```

## Guidelines

- **One skill, one responsibility** — keep skills focused and composable
- **Capability metadata on every skill** — `model_tier`, `danger_level`, `effort_hint` enable intelligent routing
- **Document boundaries** — what a skill does NOT do is as important as what it does
- **Be honest about depth** — a depth-3 domain that's accurate is better than a depth-5 that overpromises
- **Write SKILL.md for experts** — specific inputs, outputs, edge cases, not vague descriptions
