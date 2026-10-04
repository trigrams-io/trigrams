import { randomUUID } from 'node:crypto';
import { Container, TuiAltScreen, Editor, CombinedAutocompleteProvider, type Terminal, type Component, type EditorComponent, type AutocompleteProvider } from '@earendil-works/pi-tui';
import { type ExtensionUIContext, type ExtensionUIDialogOptions } from '@earendil-works/pi-coding-agent';
import type { EditorFactory } from '../node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.js';
import { KeybindingsManager } from '../node_modules/@earendil-works/pi-coding-agent/dist/core/keybindings.js';
import { FooterDataProvider } from '../node_modules/@earendil-works/pi-coding-agent/dist/core/footer-data-provider.js';
import * as themes from '../node_modules/@earendil-works/pi-coding-agent/dist/modes/interactive/theme/theme.js';
import { ProtocolError, type Params } from './transport.js';

type DisposableComponent = Component & { dispose?(): void };
type PendingDialog = { resolve: (value: unknown) => void; cancel: () => void };

/** Real pi-tui terminal seam. Frames are ANSI writes, not pretend incremental text. */
class NativeTerminal implements Terminal {
  columns = 100; rows = 30; kittyProtocolActive = false;
  input?: (data: string) => void; resize?: () => void;
  constructor(private emit: (event: string, params: unknown) => void) {}
  start(input: (data: string) => void, resize: () => void) { this.input = input; this.resize = resize; }
  stop() { this.input = undefined; this.resize = undefined; }
  async drainInput() {}
  write(data: string) { this.emit('ui.tui.frame', { data, columns: this.columns, rows: this.rows }); }
  moveBy(lines: number) { this.write(`\x1b[${Math.abs(lines)}${lines < 0 ? 'A' : 'B'}`); }
  hideCursor() { this.write('\x1b[?25l'); } showCursor() { this.write('\x1b[?25h'); }
  clearLine() { this.write('\x1b[2K'); } clearFromCursor() { this.write('\x1b[J'); }
  clearScreen() { this.write('\x1b[2J\x1b[H'); }
  setTitle(title: string) { this.emit('ui.update', { method: 'setTitle', text: title }); }
  setProgress(active: boolean) { this.emit('ui.update', { method: 'setProgress', active }); }
}

export class NativeUI {
  private dialogs = new Map<string, PendingDialog>();
  private terminal: NativeTerminal;
  private tui: TuiAltScreen;
  private components = new Map<string, DisposableComponent>();
  private root = new Container();
  private footer: FooterDataProvider;
  private editor: EditorComponent;
  private editorFactory?: EditorFactory;
  private autocomplete: AutocompleteProvider;
  private started = false;
  private frameSequence = 0;
  private expanded = false;
  private closed = false;
  private hooks = new Set<() => void>();
  readonly context: ExtensionUIContext;
  constructor(private emit: (event: string, params: unknown) => void, cwd: string, agentDir: string, private submit: (text: string) => void) {
    themes.initTheme('dark', false);
    this.terminal = new NativeTerminal((event, params) => emit(event, event === 'ui.tui.frame' ? { ...(params as Params), sequence: ++this.frameSequence } : params));
    this.tui = new TuiAltScreen(this.terminal, false, undefined, { mouse: true, copyOnSelect: false });
    this.tui.setLayoutRoot(this.root);
    this.footer = new FooterDataProvider(cwd);
    this.editor = new Editor(this.tui, themes.getEditorTheme());
    this.autocomplete = new CombinedAutocompleteProvider([], cwd);
    this.bindEditor();
    const update = (method: string, data: Params = {}) => emit('ui.update', { method, ...data });
    this.context = {
      select: async (title, options, opts) => {
        const value = await this.dialog('select', { title, options }, opts);
        if (value === undefined) return undefined;
        if (typeof value !== 'string' || !options.includes(value)) throw new ProtocolError('ui.response', 'Selection is not one of the offered options.');
        return value;
      },
      confirm: async (title, message, opts) => (await this.dialog('confirm', { title, message }, opts)) === true,
      input: async (title, placeholder, opts) => this.textDialog('input', { title, placeholder }, opts),
      editor: async (title, prefill) => this.textDialog('editor', { title, prefill }),
      notify: (message, type = 'info') => emit('ui.notify', { message, type }),
      onTerminalInput: handler => { this.startTerminal(); const remove = this.tui.addInputListener(handler); this.hooks.add(remove); return () => { remove(); this.hooks.delete(remove); }; },
      setStatus: (key, text) => { this.footer.setExtensionStatus(key, text); update('setStatus', { key, text }); },
      setWorkingMessage: text => update('setWorkingMessage', { text }),
      setWorkingVisible: visible => update('setWorkingVisible', { visible }),
      setWorkingIndicator: options => update('setWorkingIndicator', { options }),
      setHiddenThinkingLabel: text => update('setHiddenThinkingLabel', { text }),
      setWidget: (key: string, content: string[] | ((tui: typeof this.tui, theme: themes.Theme) => DisposableComponent) | undefined, options?: object) => {
        if (typeof content === 'function') this.setComponent(`widget:${key}`, content(this.tui, themes.theme));
        else { this.setComponent(`widget:${key}`, undefined); update('setWidget', { key, content, options }); }
      },
      setFooter: factory => this.setComponent('footer', factory?.(this.tui, themes.theme, this.footer)),
      setHeader: factory => this.setComponent('header', factory?.(this.tui, themes.theme)),
      setTitle: text => update('setTitle', { text }),
      custom: (factory, options) => {
        this.startTerminal();
        return new Promise((resolve, reject) => {
          const key = `custom:${randomUUID()}`;
          let settled = false;
          let hide: (() => void) | undefined;
          const done = (value: unknown) => { if (settled) return; settled = true; hide?.(); this.setComponent(key, undefined); this.dialogs.delete(key); resolve(value as never); };
          this.dialogs.set(key, { resolve: done, cancel: () => { settled = true; hide?.(); this.setComponent(key, undefined); reject(new ProtocolError('ui.disposed', 'Custom UI was disposed.')); } });
          void Promise.resolve(factory(this.tui, themes.theme, KeybindingsManager.create(agentDir), done)).then(component => {
            if (settled || this.closed) { component.dispose?.(); return; }
            if (options?.overlay) {
              this.components.set(key, component);
              const handle = this.tui.showOverlay(component, typeof options.overlayOptions === 'function' ? options.overlayOptions() : options.overlayOptions);
              hide = () => handle.hide(); options.onHandle?.(handle);
            } else { this.setComponent(key, component); this.tui.setFocus(component); }
            this.tui.requestRender();
          }, error => { settled = true; this.dialogs.delete(key); reject(error); });
        });
      },
      pasteToEditor: text => { this.editor.insertTextAtCursor ? this.editor.insertTextAtCursor(text) : this.editor.setText(this.editor.getText() + text); update('setEditorText', { text: this.editor.getText() }); this.tui.requestRender(); },
      setEditorText: text => { this.editor.setText(text); update('setEditorText', { text }); this.tui.requestRender(); },
      getEditorText: () => this.editor.getText(),
      addAutocompleteProvider: factory => { this.autocomplete = factory(this.autocomplete); this.editor.setAutocompleteProvider?.(this.autocomplete); },
      setEditorComponent: factory => {
        this.editorFactory = factory; this.setComponent('editor', undefined);
        this.editor = factory ? factory(this.tui, themes.getEditorTheme(), KeybindingsManager.create(agentDir)) : new Editor(this.tui, themes.getEditorTheme());
        this.bindEditor(); if (factory) { this.setComponent('editor', this.editor); this.tui.setFocus(this.editor); }
      },
      getEditorComponent: () => this.editorFactory,
      get theme() { return themes.theme; },
      getAllThemes: () => themes.getAvailableThemesWithPaths(),
      getTheme: name => themes.getThemeByName(name),
      setTheme: value => { const result = typeof value === 'string' ? themes.setTheme(value, false) : (themes.setThemeInstance(value), { success: true }); if (result.success) { this.tui.invalidate(); this.tui.requestRender(true); update('setTheme', { name: themes.theme.name }); } return result; },
      getToolsExpanded: () => this.expanded,
      setToolsExpanded: expanded => { this.expanded = expanded; update('setToolsExpanded', { expanded }); },
    };
  }
  private bindEditor() {
    this.editor.onSubmit = this.submit;
    this.editor.onChange = text => this.emit('ui.update', { method: 'setEditorText', text });
    this.editor.setAutocompleteProvider?.(this.autocomplete);
  }
  setComposer(text: string) { this.editor.setText(text); return { accepted: true }; }
  private startTerminal() {
    if (this.started) return;
    this.started = true; this.emit('ui.tui.open', { experimental: true }); this.tui.start();
  }
  private setComponent(key: string, component?: DisposableComponent) {
    const previous = this.components.get(key);
    if (previous) { this.root.removeChild(previous); previous.dispose?.(); this.components.delete(key); }
    if (component) { this.startTerminal(); this.components.set(key, component); this.root.addChild(component); }
    this.tui.requestRender();
  }
  input(params: Params) {
    if (!this.started) throw new ProtocolError('ui.unavailable', 'No terminal UI is active.');
    if (typeof params.data !== 'string') throw new ProtocolError('protocol.params', 'Terminal input data must be a string.');
    this.terminal.input?.(params.data); return { accepted: true };
  }
  resize(params: Params) {
    if (!Number.isInteger(params.columns) || !Number.isInteger(params.rows) || Number(params.columns) < 10 || Number(params.rows) < 3 || Number(params.columns) > 1000 || Number(params.rows) > 500) throw new ProtocolError('protocol.params', 'Invalid terminal dimensions.');
    this.terminal.columns = Number(params.columns); this.terminal.rows = Number(params.rows); this.terminal.resize?.(); return { accepted: true };
  }
  reply(params: Params) {
    const pending = typeof params.id === 'string' ? this.dialogs.get(params.id) : undefined;
    if (!pending) throw new ProtocolError('ui.stale', 'Dialog is no longer active.');
    pending.resolve(params.cancelled ? undefined : params.value); return { accepted: true };
  }
  private async textDialog(method: string, params: Params, opts?: ExtensionUIDialogOptions) {
    const value = await this.dialog(method, params, opts);
    if (value !== undefined && typeof value !== 'string') throw new ProtocolError('ui.response', 'Dialog result must be text.');
    return value as string | undefined;
  }
  private dialog(method: string, params: Params, opts?: ExtensionUIDialogOptions): Promise<unknown> {
    if (this.closed) return Promise.reject(new ProtocolError('ui.disposed', 'UI is no longer active.'));
    if (opts?.signal?.aborted) return Promise.resolve(undefined);
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      let timer: NodeJS.Timeout | undefined;
      const finish = (value: unknown) => { clearTimeout(timer); opts?.signal?.removeEventListener('abort', cancel); this.dialogs.delete(id); this.emit('ui.dismiss', { id }); resolve(value); };
      const cancel = () => finish(undefined);
      this.dialogs.set(id, { resolve: finish, cancel });
      opts?.signal?.addEventListener('abort', cancel, { once: true });
      if (opts?.timeout !== undefined) timer = setTimeout(cancel, Math.max(0, opts.timeout));
      try { this.emit('ui.request', { id, method, type: method, ...params, timeout: opts?.timeout }); }
      catch (error) { clearTimeout(timer); opts?.signal?.removeEventListener('abort', cancel); this.dialogs.delete(id); reject(error); }
    });
  }
  closeTerminal() {
    for (const [id, pending] of this.dialogs) if (id.startsWith('custom:')) { pending.cancel(); this.dialogs.delete(id); }
    for (const component of this.components.values()) component.dispose?.();
    this.components.clear(); this.root.clear();
    for (const remove of this.hooks) remove();
    this.hooks.clear(); this.tui.stop(); this.started = false;
    this.editorFactory = undefined; this.editor = new Editor(this.tui, themes.getEditorTheme()); this.bindEditor();
    this.emit('ui.tui.close', {}); return { accepted: true };
  }
  dispose() {
    this.closed = true;
    for (const pending of this.dialogs.values()) pending.cancel();
    this.dialogs.clear();
    for (const component of this.components.values()) component.dispose?.();
    this.components.clear(); this.root.clear(); this.tui.stop(); this.footer.dispose();
  }
}
