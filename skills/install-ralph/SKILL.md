---
name: install-ralph
description: "Install Ralph globally to your PATH. Use when you want to run 'ralph' from any directory. Triggers on: install ralph globally, setup ralph, make ralph available system-wide"
user-invocable: true
---

# Install Ralph Globally

Help the user install the Ralph script globally to their PATH.

## Steps

1. First, find the Ralph plugin installation path. It should be in:
   - `~/.claude/plugins/cache/ralph-marketplace/ralph-skills/`
   
2. Locate the latest version directory (the numbered directory, e.g., `1.0.0`)

3. Check if `ralph.sh` exists there

4. Ask the user where they want to install it (common options):
   - `/usr/local/bin/ralph` (requires sudo)
   - `~/.local/bin/ralph` (user-level, no sudo needed)
   - `~/bin/ralph` (user-level, no sudo needed)
   - Custom path

5. Verify the target directory is in the user's PATH

6. Copy or symlink the script to the target location

7. Make sure it's executable: `chmod +x <target-path>`

8. Verify the installation by running `which ralph` and `ralph --help`

## Notes

- If using symlink, the plugin path must not change (don't uninstall/reinstall the plugin without re-linking)
- If using copy, the user will need to re-install when the plugin updates
- Always ask for confirmation before modifying the filesystem
- On macOS, `/usr/local/bin` is usually in PATH by default
- `~/.local/bin` may need to be added to PATH manually if not already there
