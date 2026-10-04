# System prompt

The default [prompt](../agent/resources/system-prompt.md) defines Trigrams as a general-purpose macOS assistant. It adopts pi's concise tool-driven workflow, progressive skill loading, and project instructions, while adding source boundaries and evidence-based completion. It is written for Trigrams rather than copied from another product's private instructions.

The prompt is an editable preamble, not a replacement for pi's entire assembled context. `DefaultResourceLoader` still supplies discovered skills, project `AGENTS.md`, `SYSTEM.md` / `APPEND_SYSTEM.md`, and the working directory under pi's normal trust and resource rules. Changing or resetting the preamble must preserve those sections.

Settings → System prompt saves the user's version in Trigrams' agent configuration. Reset restores the shipped prompt. Changes apply to the next inference; they do not rewrite persisted messages. The actual effective system prompt can differ from the editor because of project instructions and extension hooks.

The model's instructions guide behavior; they are not an OS sandbox or a replacement for resource trust and distribution policy. Community extensions and scripts execute with the user's permissions.

Reference: [pi system prompt construction, pinned 1.0.2 source](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/src/core/system-prompt.ts), [pi skills](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/skills.md).
