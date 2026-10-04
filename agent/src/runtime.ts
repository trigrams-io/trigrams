import { mkdir, readFile, rename, writeFile, chmod, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createAgentSessionRuntime, createAgentSessionServices, createAgentSessionFromServices, SessionManager, SettingsManager, ModelRuntime, createCodemodeExtension, createToolSearchExtension, createMcpExtension, type AgentSessionRuntime, type AgentSession, type Skill, ProjectTrustStore } from '@earendil-works/pi-coding-agent';
import { resolveProjectTrusted } from '../node_modules/@earendil-works/pi-coding-agent/dist/core/project-trust.js';
import { NativeProvider, AFM_MODEL } from './provider.js';
import { NativeUI } from './ui.js';
import { ProtocolError, stringParam, type Params } from './transport.js';

type HostSettings = { systemPrompt: string; skillDirectories: string[]; disabledSkills: string[]; theme: string };
export type RuntimeOptions = { cwd: string; agentDir: string; profile: 'community' | 'store' };
export class Runtime {
  private sdk?: AgentSessionRuntime;
  private ui?: NativeUI;
  private unsubscribe?: () => void;
  private sequence = 0;
  private snapshotRevision = 0;
  private nativeTUI = false;
  private defaultPrompt = '';
  private settings: HostSettings = { systemPrompt: '', skillDirectories: [], disabledSkills: [], theme: 'system' };
  private allSkills: Skill[] = [];
  private mutation: Promise<unknown> = Promise.resolve();
  private run?: Promise<unknown>;
  private provider: NativeProvider;
  private stopped = false;
  private modelRuntime?: ModelRuntime;
  constructor(private options: RuntimeOptions, private emit: (event: string, params: unknown) => void) {
    this.provider = new NativeProvider(emit);
  }
  private get session(): AgentSession {
    if (!this.sdk) throw new ProtocolError('session.required', 'Create or open a session first.');
    return this.sdk.session;
  }
  private get settingsPath() { return join(this.options.agentDir, 'trigrams-host.json'); }
  private safeEmit(event: string, params: unknown) { try { this.emit(event, params); } catch (error) { if (!(error instanceof ProtocolError && error.code === 'transport.disconnected')) throw error; } }
  async initialize() {
    await mkdir(this.options.agentDir, { recursive: true, mode: 0o700 });
    await chmod(this.options.agentDir, 0o700);
    this.defaultPrompt = await readFile(new URL('../resources/system-prompt.md', import.meta.url), 'utf8');
    try { this.settings = this.validateSettings(JSON.parse(await readFile(this.settingsPath, 'utf8'))); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
  }
  private validateSettings(value: Params, current = this.settings): HostSettings {
    const result = { ...current };
    for (const key of ['systemPrompt', 'theme'] as const) {
      if (key in value) { if (typeof value[key] !== 'string') throw new ProtocolError('settings.invalid', `${key} must be text.`); result[key] = value[key]; }
    }
    for (const key of ['skillDirectories', 'disabledSkills'] as const) {
      if (key in value) {
        if (!Array.isArray(value[key]) || value[key].some(v => typeof v !== 'string')) throw new ProtocolError('settings.invalid', `${key} must contain only strings.`);
        result[key] = [...new Set(value[key] as string[])];
      }
    }
    if (!['system', 'light', 'dark'].includes(result.theme)) throw new ProtocolError('settings.theme', 'theme must be system, light, or dark.');
    result.skillDirectories = result.skillDirectories.map(path => resolve(path));
    return result;
  }
  private async createRuntime(cwd: string, manager: SessionManager) {
    if (this.options.profile === 'store') throw new ProtocolError('profile.unsupported', 'The Store runtime is not enabled until its sandbox and executable resource policy have been audited.');
    if (!this.modelRuntime) {
      this.modelRuntime = await ModelRuntime.create({ authPath: join(this.options.agentDir, 'auth.json'), modelsPath: join(this.options.agentDir, 'models.json'), modelsStorePath: join(this.options.agentDir, 'models-cache.json'), refreshOnCreate: false });
      this.modelRuntime.registerNativeProvider(this.provider.provider);
    }
    const factory = async (target: { cwd: string; agentDir: string; sessionManager: SessionManager; sessionStartEvent?: Parameters<typeof createAgentSessionFromServices>[0]['sessionStartEvent'] }) => {
      const settingsManager = SettingsManager.create(target.cwd, this.options.agentDir);
      // AFM has a small context; upstream compaction remains responsible for history.
      settingsManager.applyOverrides({ compaction: { enabled: true, reserveTokens: 1024, keepRecentTokens: 1536 }, defaultTools: ['+codemode', '+tool_search'] });
      const trustUI = new NativeUI((event, params) => this.safeEmit(event, params), target.cwd, this.options.agentDir, () => {});
      this.ui = trustUI;
      const services = await createAgentSessionServices({ cwd: target.cwd, agentDir: this.options.agentDir, modelRuntime: this.modelRuntime!, settingsManager,
        resourceLoaderReloadOptions: { resolveProjectTrust: async ({extensionsResult}) => resolveProjectTrusted({ cwd: target.cwd, trustStore: new ProjectTrustStore(this.options.agentDir), defaultProjectTrust: settingsManager.getDefaultProjectTrust(), extensionsResult, projectTrustContext: { cwd: target.cwd, mode: this.nativeTUI ? 'tui' : 'rpc', hasUI: true, ui: trustUI.context }, onExtensionError: message => this.safeEmit('extension.error', { message }) }) },
        resourceLoaderOptions: {
          extensionFactories: [createCodemodeExtension({ mode: 'on' }), createToolSearchExtension(), createMcpExtension()],
          additionalSkillPaths: this.settings.skillDirectories,
          systemPromptOverride: base => this.settings.systemPrompt || base || this.defaultPrompt,
          skillsOverride: base => { this.allSkills = base.skills; return { ...base, skills: base.skills.filter(skill => !this.settings.disabledSkills.includes(skill.name) && !this.settings.disabledSkills.includes(skill.filePath)) }; },
        },
      });
      const applyHostOverrides = () => settingsManager.applyOverrides({ compaction: { enabled: true, reserveTokens: 1024, keepRecentTokens: 1536 }, defaultTools: ['+codemode', '+tool_search'] });
      // pi reload reconstructs merged settings, so reapply host-local inference defaults afterward.
      const reloadResources = services.resourceLoader.reload.bind(services.resourceLoader);
      services.resourceLoader.reload = async options => { await reloadResources(options); applyHostOverrides(); };
      applyHostOverrides();
      trustUI.dispose(); this.ui = undefined;
      return { ...(await createAgentSessionFromServices({ services, sessionManager: target.sessionManager, sessionStartEvent: target.sessionStartEvent, model: AFM_MODEL, thinkingLevel: 'off' })), services, diagnostics: services.diagnostics };
    };
    this.sdk = await createAgentSessionRuntime(factory, { cwd, agentDir: this.options.agentDir, sessionManager: manager });
    this.sdk.setRebindSession(async () => this.bind());
    this.sdk.setBeforeSessionInvalidate(() => { this.unsubscribe?.(); this.ui?.dispose(); this.ui = undefined; });
    await this.bind();
  }
  private async bind() {
    this.unsubscribe?.(); this.ui?.dispose();
    const session = this.session;
    this.ui = new NativeUI((event, params) => this.safeEmit(event, params), session.sessionManager.getCwd(), this.options.agentDir, text => { void this.prompt({ text }).catch(error => this.safeEmit('runtime.error', { message: String(error) })); });
    
    this.unsubscribe = session.subscribe(event => {
      this.safeEmit('session.event', { sessionID: session.sessionId, sequence: ++this.sequence, event });
      if (event.type === 'agent_settled') void this.snapshot(session, this.finalStatus(session));
    });
    await session.bindExtensions({ uiContext: this.ui.context, mode: this.nativeTUI ? 'tui' : 'rpc',
      abortHandler: () => { void session.abort(); },
      shutdownHandler: () => { this.safeEmit('runtime.shutdown', {}); void this.dispose(); },
      onError: error => this.safeEmit('extension.error', error),
      commandContextActions: {
        waitForIdle: () => session.waitForIdle(),
        newSession: options => this.sdk!.newSession(options),
        switchSession: path => this.sdk!.switchSession(path),
        fork: (entryId, options) => this.sdk!.fork(entryId, options),
        navigateTree: (entryId, options) => session.navigateTree(entryId, options),
        reload: () => session.reload(),
      },
    });
  }
  private async describe(session = this.session) {
    const path = session.sessionFile ?? '';
    const updatedAt = path ? await stat(path).then(s => s.mtime.toISOString()).catch(() => new Date().toISOString()) : new Date().toISOString();
    const first = session.messages.find(m => m.role === 'user');
    const title = session.sessionManager.getSessionName() || (first && typeof first.content === 'string' ? first.content.slice(0, 80) : 'New chat');
    return { id: session.sessionId, path, title, cwd: session.sessionManager.getCwd(), updatedAt };
  }
  private finalStatus(session: AgentSession): 'stopped' | 'error' | 'idle' {
    if (this.stopped) return 'stopped';
    const last = session.messages.findLast(message => message.role === 'assistant') as { stopReason?: string } | undefined;
    return last?.stopReason === 'error' ? 'error' : 'idle';
  }
  private async snapshot(session = this.session, status: 'idle' | 'working' | 'stopped' | 'error' = 'idle') {
    if (this.sdk?.session !== session) return;
    const revision = ++this.snapshotRevision;
    const description = await this.describe(session);
    if (revision !== this.snapshotRevision || this.sdk?.session !== session) return;
    this.safeEmit('session.snapshot', { session: description, messages: session.messages, status, revision });
  }
  private async view() { return { session: await this.describe(), messages: this.session.messages }; }
  private exclusive<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.mutation.then(operation, operation); this.mutation = next.catch(() => {}); return next;
  }
  private async stop() {
    this.stopped = true;
    if (this.sdk) { await this.session.abort(); await this.run?.catch(() => {}); }
  }
  disconnect() { this.provider.disconnect(); this.ui?.dispose(); this.ui = undefined; void this.stop(); }
  async handle(method: string, params: Params): Promise<unknown> {
    if (method === 'hello') { this.nativeTUI = Array.isArray(params.capabilities) && params.capabilities.includes('terminal-v1'); return { version: 1, piVersion: '1.0.2', profile: this.options.profile,
      capabilities: this.options.profile === 'store' ? ['sessions.read', 'store.unsupported'] : ['sessions', 'skills', 'extensions', 'mcp', 'codemode', 'tool_search', 'model.delta', 'ui.dialogs', 'ui.tui.experimental'] }; }
    if (method === 'model.complete') return this.provider.complete(params);
    if (method === 'model.delta') return this.provider.delta(params);
    if (method === 'model.fail') return this.provider.fail(params);
    if (method === 'ui.reply') { if (!this.ui) throw new ProtocolError('ui.unavailable', 'No active UI.'); return this.ui.reply(params); }
    if (method === 'ui.tui.input') return this.ui?.input(params) ?? { accepted: false };
    if (method === 'ui.tui.resize') return this.ui?.resize(params) ?? { accepted: false };
    if (method === 'ui.tui.close') { if (!this.ui) throw new ProtocolError('ui.unavailable', 'No active UI.'); return this.ui.closeTerminal(); }
    if (method === 'ui.editor.set') return this.ui?.setComposer(stringParam(params, 'text')) ?? { accepted: false };
    if (method === 'session.prompt') return this.prompt(params);
    if (method === 'session.steer') return this.prompt({...params, mode:'steer'});
    if (method === 'session.followUp') return this.prompt({...params, mode:'followUp'});
    if (method === 'session.abort') { await this.stop(); await this.snapshot(this.session, 'stopped'); return { accepted: true }; }
    if (method === 'settings.get') return this.currentSettings();
    if (method === 'session.list') {
      const sessions = (await SessionManager.listAll(join(this.options.agentDir, 'sessions'))).map(s => ({ id: s.id, path: s.path, title: s.name || s.firstMessage.slice(0, 80) || 'New chat', cwd: s.cwd, updatedAt: s.modified.toISOString() }));
      if (this.sdk && !sessions.some(s => s.id === this.session.sessionId)) sessions.unshift(await this.describe());
      return { sessions };
    }
    return this.exclusive(async () => {
      switch (method) {
        case 'session.create': {
          await this.stop();
          const cwd = params.cwd === undefined ? this.options.cwd : resolve(stringParam(params, 'cwd'));
          await stat(cwd).then(s => { if (!s.isDirectory()) throw new ProtocolError('session.cwd', 'Working directory is not a directory.'); });
          const manager = SessionManager.create(cwd, join(this.options.agentDir, 'sessions'));
          if (this.sdk) await this.sdk.dispose();
          await this.createRuntime(cwd, manager); this.stopped = false; return this.view();
        }
        case 'session.open': {
          await this.stop(); const path = resolve(stringParam(params, 'path'));
          if (this.sdk?.session.sessionFile === path) { if (!this.ui) await this.bind(); return this.view(); }
          await stat(path);
          if (this.sdk) await this.sdk.switchSession(path);
          else { const manager = SessionManager.open(path, join(this.options.agentDir, 'sessions')); await this.createRuntime(manager.getCwd(), manager); }
          this.stopped = false; return this.view();
        }
        case 'session.rename': this.session.setSessionName(stringParam(params, 'title')); await this.snapshot(); return this.view();
        case 'session.tree': return { entries: this.session.sessionManager.getEntries(), tree: this.session.sessionManager.getTree(), leafId: this.session.sessionManager.getLeafId() };
        case 'session.fork': {
          await this.stop(); const result = await this.sdk!.fork(stringParam(params, 'entryId'), { position: params.position === 'at' ? 'at' : 'before' });
          this.stopped = false; return { ...(await this.view()), ...result };
        }
        case 'session.navigate': await this.stop(); return { ...(await this.session.navigateTree(stringParam(params, 'entryId'), { summarize: params.summarize === true })), ...(await this.view()) };
        case 'session.compact': await this.stop(); await this.session.compact(typeof params.instructions === 'string' ? params.instructions : undefined); await this.snapshot(); return this.view();
        case 'session.export': return { path: await this.session.exportToHtml(typeof params.path === 'string' ? params.path : undefined) };
        case 'session.tools': return { tools: this.session.getAllTools(), active: this.session.getActiveToolNames() };
        case 'resources.list': return this.resources();
        case 'resources.reload': await this.stop(); await this.session.reload(); return this.resources();
        case 'settings.update': {
          const settings = this.validateSettings(params);
          const resourceChange = settings.systemPrompt !== this.settings.systemPrompt || JSON.stringify(settings.skillDirectories) !== JSON.stringify(this.settings.skillDirectories) || JSON.stringify(settings.disabledSkills) !== JSON.stringify(this.settings.disabledSkills);
          if (resourceChange && this.sdk?.session.isStreaming) throw new ProtocolError('session.busy', 'Wait until the agent is idle before changing prompt or skill resources.');
          
          const scratch = `${this.settingsPath}.${randomUUID()}`;
          await writeFile(scratch, JSON.stringify(settings, null, 2) + '\n', { mode: 0o600, flag: 'wx' }); await rename(scratch, this.settingsPath); this.settings = settings;
          // SDK recreation keeps the same authoritative tree, and recreates cwd-bound resource services.
          if (this.sdk && resourceChange) { const manager = this.session.sessionManager; const cwd = manager.getCwd(); await this.sdk.dispose(); await this.createRuntime(cwd, manager); }
          return this.currentSettings();
        }
        case 'models.list': return { models: this.modelRuntime?.getModels() ?? [AFM_MODEL], current: this.sdk?.session.model ?? AFM_MODEL };
        case 'models.select': {
          const model = this.modelRuntime?.getModel(stringParam(params, 'provider'), stringParam(params, 'id'));
          if (!model) throw new ProtocolError('model.unknown', 'Model is not in the configured pi catalog.');
          await this.session.setModel(model); return { model: this.session.model };
        }
        case 'models.thinking': {
          if (params.level !== 'off' && this.session.model?.provider === 'trigrams-afm') throw new ProtocolError('model.unsupported', 'Foundation Models does not expose thinking levels.');
          const levels = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh'];
          if (!levels.includes(String(params.level))) throw new ProtocolError('model.thinking', 'Invalid thinking level.');
          this.session.setThinkingLevel(params.level as 'off'); return { level: this.session.thinkingLevel };
        }
        default: throw new ProtocolError('method.unsupported', `Unsupported method ${method}.`);
      }
    });
  }
  private currentSettings() { return { ...this.settings, defaultSystemPrompt: this.defaultPrompt }; }
  private resources() {
    const loader = this.sdk?.services.resourceLoader;
    return { skills: this.allSkills.map(s => ({ name: s.name, description: s.description, path: s.filePath, enabled: !this.settings.disabledSkills.includes(s.name) && !this.settings.disabledSkills.includes(s.filePath), source: s.sourceInfo.source })),
      diagnostics: [...(loader?.getSkills().diagnostics ?? []), ...(loader?.getPrompts().diagnostics ?? []), ...(loader?.getThemes().diagnostics ?? [])],
      commands: this.sdk?.session.extensionRunner.getRegisteredCommands().map(c => ({ name: c.name, description: c.description })) ?? [], prompts: loader?.getPrompts().prompts ?? [], contextFiles: loader?.getAgentsFiles().agentsFiles.map(f => ({ path: f.path })) ?? [] };
  }
  private async prompt(params: Params) {
    if (this.options.profile === 'store') throw new ProtocolError('profile.unsupported', 'The Store runtime has not completed its executable resource audit.');
    const text = stringParam(params, 'text');
    if (!text.trim()) throw new ProtocolError('session.prompt', 'Prompt cannot be empty.');
    if (params.mode !== undefined && params.mode !== 'steer' && params.mode !== 'followUp') throw new ProtocolError('session.prompt', 'mode must be steer or followUp.');
    const session = this.session;
    if (session.isStreaming && !params.mode) throw new ProtocolError('session.busy', 'Choose steer or followUp while the agent is working.');
    if (!session.isStreaming && text.startsWith('/') && !text.startsWith('/skill:')) {
      const [command, ...args] = text.slice(1).split(' '); const argument = args.join(' ');
      const methods: Record<string, [string, Params]> = { reload: ['resources.reload', {}], name: ['session.rename', { title: argument }], new: ['session.create', {}], compact: ['session.compact', { instructions: argument }], tree: ['session.tree', {}], settings: ['settings.get', {}], session: ['session.tree', {}], export: ['session.export', { path: argument || undefined }] };
      if (command in methods) { const [method, p] = methods[command]; const result = await this.handle(method, p); this.safeEmit('command.result', { command, result }); return { accepted: true }; }
      const hostCommands = ['model', 'thinking', 'scoped-models', 'login', 'logout', 'llama', 'resume', 'fork', 'clone', 'import', 'copy', 'share', 'bug', 'trust', 'hotkeys', 'changelog', 'quit'];
      if (hostCommands.includes(command)) throw new ProtocolError('command.unsupported', `/${command} requires a host action that is not implemented yet.`);
      if (!session.extensionRunner.getCommand(command) && !this.sdk!.services.resourceLoader.getPrompts().prompts.some(template => template.name === command)) throw new ProtocolError('command.unknown', `Unknown command /${command}.`);
    }
    this.stopped = false;
    if (text.startsWith('!') && !session.isStreaming) {
      const excluded = text.startsWith('!!'); const command = text.slice(excluded ? 2 : 1).trim();
      if (!command) throw new ProtocolError('session.prompt', 'Shell command cannot be empty.');
      this.run = session.executeBash(command, chunk => this.safeEmit('shell.delta', { text: chunk }), { excludeFromContext: excluded });
    } else this.run = session.prompt(text, { streamingBehavior: params.mode as 'steer' | 'followUp' | undefined });
    const run = this.run;
    void run.then(() => { if (!session.isStreaming) return this.snapshot(session, this.finalStatus(session)); }, error => { this.safeEmit('runtime.error', { message: String(error) }); void this.snapshot(session, 'error'); });
    if (session.isStreaming) void this.snapshot(session, 'working');
    return { accepted: true };
  }
  async dispose() {
    await this.stop(); this.provider.disconnect(); this.unsubscribe?.(); this.ui?.dispose(); this.ui = undefined; await this.sdk?.dispose(); this.sdk = undefined;
  }
}
