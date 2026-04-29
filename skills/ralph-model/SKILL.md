---
name: ralph-model
description: "Modify a user story's model/provider in prd.json. Use when you need to change which AI provider a specific story uses. Triggers on: change model, switch provider, update model, ralph model."
user-invocable: true
---

# Ralph Model Switcher

Change the AI model/provider for individual user stories in `prd.json`.

---

## Prerequisites

- `prd.json` must exist in the current working directory
- CC-Switch database at `~/.cc-switch/cc-switch.db` must be available

---

## Step 0: Read Current State

### Read prd.json

Read `prd.json` from the current working directory. Extract all user stories with their:
- `id` (e.g., "US-001")
- `title`
- `passes` status
- Current `model.providerName` (or "default" if `model` is null)

### Query CC-Switch Providers

```bash
sqlite3 -json ~/.cc-switch/cc-switch.db "SELECT id, name, settings_config FROM providers WHERE app_type = 'claude'"
```

If CC-Switch is unavailable (DB missing, sqlite3 not found, or empty result), inform the user and abort:
> "CC-Switch database not found or no providers configured. Cannot switch models."

---

## Step 1: Display Current Model Assignments

Show the user a summary table of all stories and their current model assignments:

```
Current model assignments:
  [US-001] Story Title — Provider Name (or "default")
  [US-002] Story Title — Provider Name (or "default")
  ...
```

---

## Step 2: Select Story to Modify

Use `AskUserQuestion` to ask which story's model to change:

```
Question: "Which story's model do you want to change?"
Options: [one option per story, using "[ID] Title (current: ProviderName)" as label]
```

Allow `multiSelect: true` so the user can select multiple stories at once.

---

## Step 3: Select New Provider

Use `AskUserQuestion` to ask which provider to assign:

```
Question: "Which provider should the selected story/stories use?"
Options: [one option per provider from CC-Switch, using provider `name` as label, plus "Clear — use default settings"]
```

- If user selects a provider, set the `model` field to:
  ```json
  {
    "providerId": "<provider id>",
    "providerName": "<provider name>",
    "settingsConfig": <parsed settings_config object>
  }
  ```
- If user selects "Clear — use default settings", set `model` to `null`.

---

## Step 4: Update prd.json

1. Read the full `prd.json`
2. Update ONLY the `model` field of the selected story/stories
3. Do NOT modify any other fields (title, description, acceptanceCriteria, passes, notes, etc.)
4. Write the updated `prd.json` back

---

## Step 5: Confirm Changes

Show the user what changed:

```
Updated model assignments:
  [US-XXX] Story Title — New Provider Name ✓
```

---

## Important

- This skill ONLY modifies the `model` field in user stories
- Never change story content, acceptance criteria, passes status, or any other field
- Always preserve the exact JSON structure and formatting of prd.json
