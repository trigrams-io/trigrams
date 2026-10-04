import { writeFile, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { ExtensionFactory } from '@earendil-works/pi-coding-agent';

/** pi discovers resources; only the model-facing catalogue is paged. */
export function createSkillIndexExtension(agentDir: string): ExtensionFactory {
  const path = join(agentDir, 'skills-index.jsonl');
  let previous = '';
  return pi => {
    pi.on('before_agent_start', async event => {
      const skills = event.systemPromptOptions.skills.filter(skill => !skill.disableModelInvocation);
      const contents = skills.map(skill => JSON.stringify({ name: skill.name, description: skill.description, path: skill.filePath })).join('\n') + '\n';
      if (contents !== previous) {
        const scratch = `${path}.${randomUUID()}`;
        await writeFile(scratch, contents, { mode: 0o600, flag: 'wx' });
        await rename(scratch, path);
        previous = contents;
      }
      // Use the SDK's mutable sections. Original skills and slash commands are
      // retained by the resource loader, with no second context/agent loop.
      event.systemPromptOptions.skills = [];
      if (skills.length) {
        const names = skills.map(skill => skill.name).join(', ');
        const preview = names.length <= 1600 ? names : names.slice(0, Math.max(0, names.lastIndexOf(', ', 1600))) + ', …';
        event.systemPromptOptions.sections.skills = `${skills.length} skills: ${preview}\nFull names, descriptions and SKILL.md paths: ${JSON.stringify(path)} (one JSON object per line). Search relevant lines with bash; read the selected original SKILL.md in small pages before acting. Resolve relative resources from its directory.`;
      } else delete event.systemPromptOptions.sections.skills;
    });
  };
}

/** Keep semantic content and tool identity, omit billing/UI/timestamp metadata. */
export function inferenceMessages(messages: readonly { role: string; content: unknown }[]) {
  return messages.filter(message => message.role !== 'system').map(message => {
    const source = message as Record<string, unknown>;
    const result: Record<string, unknown> = { role: message.role, content: message.content };
    for (const key of ['toolCallId', 'toolName', 'isError']) if (source[key] !== undefined) result[key] = source[key];
    if (Array.isArray(message.content)) result.content = message.content.map(block => {
      if (block.type === 'text') return { type: 'text', text: block.text };
      if (block.type === 'toolCall') return { type: 'toolCall', id: block.id, name: block.name, arguments: block.arguments };
      return block;
    });
    return result;
  });
}
