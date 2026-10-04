import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { ExtensionFactory } from '@earendil-works/pi-coding-agent';

const key = (id: string) => createHash('sha256').update(id).digest('hex');
const directory = (agentDir: string) => join(agentDir, 'tool-results');

/** Bound model-visible output before pi persists it or considers compaction.
 * Nested calls keep complete machine-readable data for codemode scripts. */
export function createToolOutputExtension(agentDir: string): ExtensionFactory {
  return pi => {
    pi.on('tool_result', async event => {
      if (event.parentToolCallId || event.content.some(block => block.type !== 'text')) return;
      const text = event.content.map(block => block.type === 'text' ? block.text : '').join('\n');
      // Conservative language-aware estimate; Apple's exact whole-request
      // token count (when available) remains the final check in Swift.
      let cost = 0;
      let preview = '';
      for (const character of text) {
        cost += character.codePointAt(0)! < 128 ? 1 / 3 : 1;
        if (cost <= 256) preview += character;
      }
      if (cost <= 600) return;
      const folder = directory(agentDir);
      await mkdir(folder, { recursive: true, mode: 0o700 });
      const stem = join(folder, key(event.toolCallId));
      await writeFile(stem + '.txt', text, { mode: 0o600 });
      await writeFile(stem + '.json', JSON.stringify({ content: event.content, details: event.details, structuredContent: event.structuredContent, isError: event.isError }), { mode: 0o600 });
      return {
        content: [{ type: 'text', text: `Paged tool output (${text.length} characters). Preview only:\n${preview}\n[…]\nComplete text: ${JSON.stringify(stem + '.txt')}. Read with offset/limit or search specific lines; never load the whole file into context.` }],
        structuredContent: event.structuredContent,
        isError: event.isError,
      };
    });
  };
}

export async function readToolOutput(agentDir: string, id: string) {
  try { return JSON.parse(await readFile(join(directory(agentDir), key(id) + '.json'), 'utf8')); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null; throw error; }
}
