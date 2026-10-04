import { randomUUID } from 'node:crypto';
import { Ajv } from 'ajv';
import { createAssistantMessageEventStream, getCurrentSystemPrompt, getCurrentTools, type AssistantMessage, type Model, type Provider, type SimpleStreamOptions, type TranscriptContext, type ToolCall } from '@earendil-works/pi-ai';
import { ProtocolError, type Params } from './transport.js';
import { inferenceMessages } from './context.js';

export const AFM_MODEL: Model<'trigrams-afm'> = {
  id: 'apple-foundation-model', name: 'Apple Foundation Models', api: 'trigrams-afm', provider: 'trigrams-afm',
  baseUrl: 'local://foundation-models', reasoning: false, input: ['text'],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 1024,
};
type Response = { text: string; toolCalls: { name: string; arguments: Record<string, unknown> }[]; contextBudget?: Record<string, number | boolean> };
type Pending = { resolve: (response: Response) => void; reject: (error: Error) => void; delta: (text: string) => void };
const ajv = new Ajv({ allErrors: true, strict: false, validateFormats: false });

/** Inference only: pi retains exclusive ownership of all executable tools. */
export class NativeProvider {
  private pending = new Map<string, Pending>();
  constructor(private emit: (event: string, params: unknown) => void) {}
  complete(params: Params) {
    const id = params.id;
    const pending = typeof id === 'string' ? this.pending.get(id) : undefined;
    if (!pending) throw new ProtocolError('model.stale', 'Generation is no longer active.');
    const r = params.response as Partial<Response> | undefined;
    if (!r || typeof r.text !== 'string' || !Array.isArray(r.toolCalls) || r.toolCalls.some(call => !call || typeof call.name !== 'string' || !call.arguments || typeof call.arguments !== 'object' || Array.isArray(call.arguments))) {
      throw new ProtocolError('model.response', 'Expected response {text,toolCalls:[{name,arguments}]}.');
    }
    pending.resolve(r as Response);
    this.pending.delete(id as string);
    return { accepted: true };
  }
  delta(params: Params) {
    const pending = typeof params.id === 'string' ? this.pending.get(params.id) : undefined;
    if (!pending) throw new ProtocolError('model.stale', 'Generation is no longer active.');
    if (typeof params.text !== 'string') throw new ProtocolError('model.response', 'Delta text must be a string.');
    pending.delta(params.text); return { accepted: true };
  }
  fail(params: Params) {
    const pending = typeof params.id === 'string' ? this.pending.get(params.id) : undefined;
    if (!pending) throw new ProtocolError('model.stale', 'Generation is no longer active.');
    pending.reject(new ProtocolError(String(params.code ?? 'model.failed'), String(params.message ?? 'Model generation failed.')));
    this.pending.delete(params.id as string); return { accepted: true };
  }
  disconnect() {
    for (const pending of this.pending.values()) pending.reject(new ProtocolError('transport.disconnected', 'Native model connection closed.'));
    this.pending.clear();
  }
  readonly provider: Provider<'trigrams-afm'> = {
    id: 'trigrams-afm', name: 'Apple Foundation Models',
    auth: { apiKey: { name: 'On-device model', resolve: async () => ({ auth: {}, source: 'Apple Intelligence' }) } },
    getModels: () => [AFM_MODEL],
    stream: (model, context, options) => this.stream(model, context, options),
    streamSimple: (model, context, options) => this.stream(model, context, options),
  };
  private stream(model: Model<'trigrams-afm'>, context: TranscriptContext, options?: SimpleStreamOptions) {
    const stream = createAssistantMessageEventStream();
    const message: AssistantMessage = { role: 'assistant', content: [], api: model.api, provider: model.provider, model: model.id,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: 'stop', timestamp: Date.now(), diagnostics: [{ type: 'usage.unavailable', timestamp: Date.now(), details: { message: 'Foundation Models does not report token usage; zero values are unknown, not measured.' } }] };
    const id = randomUUID();
    let accumulated = '';
    let textStarted = false;
    const append = (text: string) => {
      if (!text || options?.signal?.aborted) return;
      if (!textStarted) { textStarted = true; message.content.push({ type: 'text', text: '' }); stream.push({ type: 'text_start', contentIndex: 0, partial: message }); }
      accumulated += text; (message.content[0] as { text: string }).text = accumulated;
      stream.push({ type: 'text_delta', contentIndex: 0, delta: text, partial: message });
    };
    const cancel = () => {
      const pending = this.pending.get(id);
      if (!pending) return;
      this.pending.delete(id); pending.reject(new ProtocolError('model.cancelled', 'Generation cancelled.'));
      try { this.emit('model.cancel', { id }); } catch { /* A disconnected peer already cancelled its task. */ }
    };
    stream.push({ type: 'start', partial: message });
    void (async () => {
      try {
        if (options?.signal?.aborted) throw new ProtocolError('model.cancelled', 'Generation cancelled.');
        if (options?.reasoning) throw new ProtocolError('model.unsupported', 'Foundation Models does not expose thinking levels.');
        if (options?.deferred) throw new ProtocolError('model.unsupported', 'Foundation Models does not support deferred generation.');
        if (context.messages.some(m => m.role !== 'system' && typeof m.content !== 'string' && m.content.some(c => c.type === 'image'))) throw new ProtocolError('model.unsupported', 'Foundation Models accepts text only.');
        const tools = getCurrentTools(context.messages);
        const response = await new Promise<Response>((resolve, reject) => {
          this.pending.set(id, { resolve, reject, delta: append });
          options?.signal?.addEventListener('abort', cancel, { once: true });
          try { this.emit('model.generate', { id, instructions: getCurrentSystemPrompt(context.messages),
            prompt: JSON.stringify(inferenceMessages(context.messages)), tools,
            maxTokens: Math.min(options?.maxTokens ?? model.maxTokens, model.maxTokens) }); }
          catch (error) { reject(error); }
        });
        if (options?.signal?.aborted) throw new ProtocolError('model.cancelled', 'Generation cancelled.');
        // Validate the entire batch before exposing any executable tool-call event.
        if (response.contextBudget) message.diagnostics!.push({ type: 'context.budget', timestamp: Date.now(), details: response.contextBudget });
        const calls: ToolCall[] = response.toolCalls.map(call => {
          const tool = tools.find(tool => tool.name === call.name);
          if (!tool) throw new ProtocolError('model.tool', `Model requested undeclared tool ${call.name}.`);
          const validate = ajv.compile(tool.parameters);
          if (!validate(call.arguments)) throw new ProtocolError('model.arguments', `${call.name}: ${ajv.errorsText(validate.errors)}`);
          return { type: 'toolCall', id: randomUUID(), name: call.name, arguments: call.arguments as ToolCall['arguments'] };
        });
        if (!response.text.startsWith(accumulated)) throw new ProtocolError('model.response', 'Final text does not match streamed text.');
        append(response.text.slice(accumulated.length));
        if (textStarted) stream.push({ type: 'text_end', contentIndex: 0, content: accumulated, partial: message });
        for (const call of calls) {
          const index = message.content.length; message.content.push(call);
          stream.push({ type: 'toolcall_start', contentIndex: index, partial: message });
          stream.push({ type: 'toolcall_end', contentIndex: index, toolCall: call, partial: message });
        }
        message.stopReason = calls.length ? 'toolUse' : 'stop';
        stream.push({ type: 'done', reason: message.stopReason, message });
      } catch (error) {
        message.stopReason = options?.signal?.aborted ? 'aborted' : 'error';
        message.errorMessage = error instanceof ProtocolError ? `${error.code}: ${error.message}` : String(error);
        stream.push({ type: 'error', reason: message.stopReason, error: message });
      } finally { this.pending.delete(id); options?.signal?.removeEventListener('abort', cancel); stream.end(); }
    })();
    return stream;
  }
}
