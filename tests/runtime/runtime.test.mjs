import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmod, readFile, stat, writeFile } from 'node:fs/promises';
import { createConnection } from 'node:net';
import { once } from 'node:events';
import { join } from 'node:path';
import { fixture, start, save, answer, respond, pause } from './peer.mjs';
import { extension, mcp } from './fixtures.mjs';

// These tests launch the production sidecar and speak the same protocol as Swift.
// The deterministic inference peer replaces AFM, while the full pi SDK executes tools.
test('a large skill catalogue stays local and selected instructions load through pi tools', async t => {
  const f = await fixture(); t.after(() => f.dispose());
  const description = 'Use for a catalogue paging scenario. '.repeat(20);
  for (let i = 0; i < 80; i++) {
    const name = `indexed-${String(i).padStart(3, '0')}`;
    await save(join(f.agentDir, `skills/${name}/SKILL.md`), `---\nname: ${name}\ndescription: ${description}\n---\nWrite VERIFIED after reading this original instruction.\n`);
  }
  const peer = await start(f); t.after(() => peer.stop());
  await peer.request('session.create');
  const after = peer.events.length;
  await peer.request('session.prompt', { text: 'Find the indexed-079 skill and follow it.' });
  const first = await peer.event('model.generate', () => true, after);
  assert(first.instructions.length < 3500, 'Descriptions and per-skill paths must not fill the initial window.');
  assert(!first.instructions.includes(description));
  assert(!first.tools.some(tool => tool.name === 'codemode'));
  const indexPath = join(f.agentDir, 'skills-index.jsonl');
  const catalogue = (await readFile(indexPath, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(catalogue.filter(skill => skill.name.startsWith('indexed-')).length, 80);
  assert.equal(catalogue.find(skill => skill.name === 'indexed-079').description, description.trim());
  const quotedIndex = "'" + indexPath.replaceAll("'", "'\\''") + "'";
  await peer.request('model.complete', { id: first.id, response: { text: '', toolCalls: [{ name: 'bash', arguments: { command: `rg -F '"name":"indexed-079"' ${quotedIndex}` } }] } });
  const second = await peer.event('model.generate', p => p.id !== first.id, after);
  const skillPath = join(f.agentDir, 'skills/indexed-079/SKILL.md');
  assert(second.prompt.includes(skillPath));
  await peer.request('model.complete', { id: second.id, response: { text: '', toolCalls: [{ name: 'read', arguments: { path: skillPath, offset: 1, limit: 10 } }] } });
  const third = await peer.event('model.generate', p => p.id !== first.id && p.id !== second.id, after);
  assert(third.prompt.includes('Write VERIFIED after reading this original instruction.'));
  await peer.request('model.complete', { id: third.id, response: { text: 'VERIFIED', toolCalls: [] } });
  await peer.event('session.snapshot', p => p.status === 'idle', after);
  await peer.request('settings.update', { disabledSkills: ['indexed-079'] });
  const next = peer.events.length;
  await peer.request('session.prompt', { text: 'Catalogue after disabling a skill' });
  const updated = await peer.event('model.generate', () => true, next);
  assert(!(await readFile(indexPath, 'utf8')).includes('"name":"indexed-079"'));
  await peer.request('model.complete', { id: updated.id, response: { text: 'Done', toolCalls: [] } });
  const summary = await peer.event('model.generate', p => p.tools.length === 0, next);
  assert(summary.instructions.includes('summarization assistant'));
  await peer.request('model.complete', { id: summary.id, response: { text: 'The user requested indexed-079. Its original instructions were read and VERIFIED was reported. The skill was subsequently disabled.', toolCalls: [] } });
  await peer.event('session.snapshot', p => p.status === 'idle', next);
  assert((await peer.request('session.tree')).entries.some(entry => entry.type === 'compaction'));
});

test('large Unicode tool output is paged before the next model step and remains inspectable', async t => {
  const f = await fixture(); t.after(() => f.dispose());
  const contents = Array.from({ length: 80 }, (_, i) => `${i}: 工具返回需要完整保存和按需分页。`.repeat(8)).join('\n') + '\nVERBATIM_END';
  await save(join(f.cwd, 'large.txt'), contents);
  const peer = await start(f); t.after(() => peer.stop());
  await peer.request('session.create');
  const after = peer.events.length;
  await peer.request('session.prompt', { text: 'Inspect the end of large.txt' });
  const first = await peer.event('model.generate', () => true, after);
  await peer.request('model.complete', { id: first.id, response: { text: '', toolCalls: [{ name: 'read', arguments: { path: 'large.txt' } }] } });
  const next = await peer.event('model.generate', p => p.id !== first.id, after);
  assert(next.prompt.length < 2300);
  assert(next.prompt.includes('Paged tool output'));
  assert(!next.prompt.includes('VERBATIM_END'));
  const messages = JSON.parse(next.prompt);
  const result = messages.findLast(message => message.role === 'toolResult');
  const complete = await peer.request('tool.output', { id: result.toolCallId });
  assert(complete.result.content[0].text.includes('VERBATIM_END'));
  assert.equal((await peer.request('tool.output', { id: '../../outside' })).result, null);
  const match = result.content[0].text.match(/Complete text: (".*?")\./);
  const path = JSON.parse(match[1]);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.equal(await readFile(path, 'utf8'), contents);
  await peer.request('model.complete', { id: next.id, response: { text: '', toolCalls: [{ name: 'read', arguments: { path, offset: 81, limit: 1 } }] } });
  const page = await peer.event('model.generate', p => p.id !== first.id && p.id !== next.id, after);
  assert(page.prompt.includes('VERBATIM_END'));
  await peer.request('model.complete', { id: page.id, response: { text: 'The final line is VERBATIM_END.', toolCalls: [] } });
  await peer.event('session.snapshot', p => p.status === 'idle', after);
});

test('real pi discovers skills/context, executes built-in and extension tools, preserves JSONL trees', async t => {
  const f = await fixture(); t.after(() => f.dispose());
  await save(join(f.cwd,'AGENTS.md'),'Always preserve the project marker PROJECT_CONTEXT.');
  await save(join(f.agentDir,'skills/example/SKILL.md'),'---\nname: example\ndescription: Integration skill\n---\nRead references/data.txt with read.\n');
  await save(join(f.agentDir,'skills/example/references/data.txt'),'skill payload');
  await save(join(f.agentDir,'extensions/fixture.ts'),extension);
  await save(join(f.agentDir,'mcp-fixture.mjs'),mcp);
  await save(join(f.agentDir,'mcp.json'),JSON.stringify({mcpServers:{fixture:{command:process.execPath,args:[join(f.agentDir,'mcp-fixture.mjs')],exposure:'direct'}}}));
  const peer = await start(f); t.after(() => peer.stop());
  assert.equal(peer.hello.piVersion,'1.0.2');
  assert.equal((await stat(peer.path)).mode & 0o777,0o600);
  const initial = await peer.request('session.create');
  const resources = await peer.request('resources.list');
  assert(resources.skills.some(s=>s.name==='example'&&s.enabled));
  assert(resources.contextFiles.some(s=>s.path.endsWith('AGENTS.md')));
  assert(resources.commands.some(c=>c.name==='fixture'));
  const after=peer.events.length;
  await peer.request('session.prompt',{text:'/skill:example use fixture'});
  const generation=await peer.event('model.generate',()=>true,after);
  assert(generation.instructions.includes('PROJECT_CONTEXT'));
  assert(generation.instructions.includes('example'));
  assert(!generation.instructions.includes('Integration skill'));
  const index = await readFile(join(f.agentDir, 'skills-index.jsonl'), 'utf8');
  assert(index.includes('Integration skill'));
  assert.equal((await stat(join(f.agentDir, 'skills-index.jsonl'))).mode & 0o777, 0o600);
  assert(generation.prompt.includes('Read references/data.txt'));
  const toolNames=generation.tools.map(t=>t.name);
  assert(toolNames.includes('read'));assert(toolNames.includes('fixture_echo'));assert(!toolNames.includes('codemode'));assert(toolNames.includes('tool_search'));assert(toolNames.includes('mcp__fixture__echo'));
  await peer.request('model.complete',{id:generation.id,response:{text:'Reading',toolCalls:[{name:'read',arguments:{path:join(f.agentDir,'skills/example/references/data.txt')}},{name:'fixture_echo',arguments:{text:'hello'}},{name:'mcp__fixture__echo',arguments:{text:'world'}}]}});
  const second=await peer.event('model.generate',p=>p.id!==generation.id,after);
  assert(second.prompt.includes('skill payload'));assert(second.prompt.includes('Extension says hello'));assert(second.prompt.includes('MCP says world'));
  await peer.request('model.delta',{id:second.id,text:'Com'});
  await peer.request('model.complete',{id:second.id,response:{text:'Completed',toolCalls:[]}});
  const final=await peer.event('session.snapshot',p=>p.status==='idle',after);
  assert.equal(final.session.title, (await peer.request('session.list')).sessions.find(session => session.id === initial.session.id).title);
  assert.equal(final.messages.at(-1).content[0].text,'Completed');
  const deltas=peer.events.slice(after).filter(e=>e.event==='session.event'&&e.params.event.type==='message_update'&&e.params.event.assistantMessageEvent.type==='text_delta').map(e=>e.params.event.assistantMessageEvent.delta);
  assert.deepEqual(deltas.slice(-2),['Com','pleted']);
  await peer.request('session.rename',{title:'Named integration'});
  const listed=(await peer.request('session.list')).sessions;
  assert(listed.some(s=>s.title==='Named integration'));
  const tree=await peer.request('session.tree');
  assert(tree.entries.some(e=>e.type==='message'&&e.message.role==='toolResult'));
  const fork=await peer.request('session.fork',{entryId:tree.entries.find(e=>e.type==='message'&&e.message.role==='user').id,position:'at'});
  assert.notEqual(fork.session.id,initial.session.id);
  await answer(peer,'fork answer');
  await peer.request('session.open',{path:final.session.path});
  assert.equal((await peer.request('session.tree')).entries.filter(e=>e.type==='message'&&e.message.role==='assistant').length,2);
  const raw=await readFile(final.session.path,'utf8'); assert(raw.includes('"type":"session"'));assert(raw.includes('"parentId"'));
  await peer.stop();
  const restarted=await start(f); t.after(()=>restarted.stop());
  const restored=await restarted.request('session.open',{path:final.session.path});
  assert.equal(restored.messages.at(-1).content[0].text,'Completed');
  assert.equal(restored.session.title,'Named integration');
});

test('native dialogs, actual pi-tui overlay input, editor, theme and dispose all share one pi session',async t=>{
  const f=await fixture();t.after(()=>f.dispose());await save(join(f.agentDir,'extensions/fixture.ts'),extension);
  const peer=await start(f);t.after(()=>peer.stop());await peer.request('session.create');
  let after=peer.events.length;await peer.request('session.prompt',{text:'/fixture args'});
  for(const [type,value] of [['confirm',true],['select','two'],['input','entered'],['editor','edited']]){
    const request=await peer.event('ui.request',p=>p.type===type,after);await peer.request('ui.reply',{id:request.id,value});
  }
  await peer.event('ui.dismiss',()=>true,after);
  for(let i=0;i<100;i++){const entries=(await peer.request('session.tree')).entries;if(entries.some(e=>e.type==='custom'&&e.customType==='fixture-dialogs'))break;await pause(10)}
  let tree=await peer.request('session.tree');const dialogs=tree.entries.find(e=>e.customType==='fixture-dialogs');assert(dialogs);assert.equal(dialogs.data.pick,'two');assert.equal(dialogs.data.edited,'edited');
  assert(peer.events.some(e=>e.event==='ui.update'&&e.params.method==='setEditorText'&&e.params.text.includes('paste')));
  await peer.request('ui.editor.set',{text:'typed native'});
  await peer.request('session.prompt',{text:'/timeout'});await peer.event('ui.dismiss',()=>true,after);
  await peer.request('session.prompt',{text:'/abort-dialog'});await pause(30);
  after=peer.events.length;await peer.request('session.prompt',{text:'/tui-fixture'});
  await peer.event('ui.tui.open',()=>true,after);await peer.event('ui.tui.frame',p=>p.data.includes('Overlay fixture'),after);
  await peer.request('ui.tui.resize',{columns:80,rows:24});await peer.request('ui.tui.input',{data:'x'});await peer.request('ui.tui.input',{data:'y'});
  await pause(50);tree=await peer.request('session.tree');assert(tree.entries.some(e=>e.customType==='fixture-tui-result'&&e.data.result==='accepted'));assert(tree.entries.some(e=>e.customType==='fixture-disposed'));
  await peer.request('session.prompt',{text:'/custom-editor'});await peer.event('ui.notify',p=>p.message==='custom!',after);
  await peer.request('ui.tui.input',{data:'z'});await peer.request('session.prompt',{text:'/restore-editor'});
  await peer.request('session.prompt',{text:'/theme-fixture'});await pause(30);assert((await peer.request('session.tree')).entries.some(e=>e.customType==='theme-result'&&e.data.success===false));
  await peer.request('ui.tui.close');await peer.event('ui.tui.close',()=>true,after);
});

test('cancel/steer/follow-up, provider validation/failure, secure config and reload reject unsafe inputs',async t=>{
  const f=await fixture();t.after(()=>f.dispose());const peer=await start(f);t.after(()=>peer.stop());await peer.request('session.create');
  let after=peer.events.length;await peer.request('session.prompt',{text:'first'});const first=await peer.event('model.generate',()=>true,after);
  await assert.rejects(peer.request('session.prompt',{text:'busy'}),e=>e.code==='session.busy');
  await peer.request('settings.update',{theme:'light'});
  await assert.rejects(peer.request('settings.update',{systemPrompt:'changed'}),e=>e.code==='session.busy');
  await peer.request('session.prompt',{text:'steering',mode:'steer'});await peer.request('session.prompt',{text:'follow up',mode:'followUp'});
  await peer.request('model.complete',{id:first.id,response:{text:'first response',toolCalls:[]}});
  const second=await peer.event('model.generate',p=>p.id!==first.id,after);assert(second.prompt.includes('steering'));await peer.request('model.complete',{id:second.id,response:{text:'second response',toolCalls:[]}});
  const third=await peer.event('model.generate',p=>p.id!==first.id&&p.id!==second.id,after);assert(third.prompt.includes('follow up'));await peer.request('model.complete',{id:third.id,response:{text:'third response',toolCalls:[]}});await peer.event('session.snapshot',p=>p.status==='idle',after);
  after=peer.events.length;await peer.request('session.prompt',{text:'cancel'});const cancelling=await peer.event('model.generate',()=>true,after);await peer.request('session.abort');await peer.event('model.cancel',p=>p.id===cancelling.id,after);await peer.event('session.snapshot',p=>p.status==='stopped',after);await assert.rejects(peer.request('model.complete',{id:cancelling.id,response:{text:'late',toolCalls:[]}}),e=>e.code==='model.stale');
  after=peer.events.length;await peer.request('session.prompt',{text:'invalid tool'});const invalid=await peer.event('model.generate',()=>true,after);await peer.request('model.complete',{id:invalid.id,response:{text:'',toolCalls:[{name:'write',arguments:{path:join(f.cwd,'must-not-exist')}}]}});const errored=await peer.event('session.snapshot',p=>p.status==='error',after);assert(errored.messages.at(-1).errorMessage.includes('model.arguments'));await assert.rejects(stat(join(f.cwd,'must-not-exist')));
  after=peer.events.length;await peer.request('session.prompt',{text:'model fail'});const failed=await peer.event('model.generate',()=>true,after);await peer.request('model.fail',{id:failed.id,code:'model.unavailable',message:'No local model'});await peer.event('session.snapshot',p=>p.status==='error',after);
  const settings=await peer.request('settings.update',{systemPrompt:'General local assistant',skillDirectories:[],disabledSkills:[],theme:'system'});assert(settings.defaultSystemPrompt.length>0);assert.equal((await stat(join(f.agentDir,'trigrams-host.json'))).mode&0o777,0o600);
  await save(join(f.agentDir,'skills/reloaded/SKILL.md'),'---\nname: reloaded\ndescription: Reloaded fixture\n---\nFixture body\n');
  assert((await peer.request('resources.reload')).skills.some(s=>s.name==='reloaded'));
  const disabled=await peer.request('settings.update',{disabledSkills:['reloaded']});assert.deepEqual(disabled.disabledSkills,['reloaded']);assert.equal((await peer.request('resources.list')).skills.find(s=>s.name==='reloaded').enabled,false);
  await assert.rejects(peer.request('settings.update',{theme:'invalid'}),e=>e.code==='settings.theme');await assert.rejects(peer.request('settings.update',{skillDirectories:[3]}),e=>e.code==='settings.invalid');
  await assert.rejects(peer.request('session.prompt',{text:'/not-a-command'}),e=>e.code==='command.unknown');
  await assert.rejects(peer.request('unknown.method'),e=>e.code==='method.unsupported');await assert.rejects(peer.request('session.prompt',{text:'/login'}),e=>e.code==='command.unsupported');await assert.rejects(peer.request('session.prompt',{text:'x',mode:'bad'}));await assert.rejects(peer.request('session.prompt',{text:''}));await assert.rejects(peer.request('ui.reply',{id:'stale'}),e=>e.code==='ui.stale');await assert.rejects(peer.request('ui.tui.input',{data:1}));await assert.rejects(peer.request('ui.tui.resize',{columns:0,rows:0}));
  assert((await peer.request('models.list')).models.some(m=>m.id==='apple-foundation-model'));await assert.rejects(peer.request('models.select',{provider:'missing',id:'none'}),e=>e.code==='model.unknown');await assert.rejects(peer.request('models.thinking',{level:'high'}),e=>e.code==='model.unsupported');await peer.request('models.thinking',{level:'off'});
  const shellAfter=peer.events.length;await peer.request('session.prompt',{text:'!printf integration-shell'});await peer.event('shell.delta',p=>p.text.includes('integration-shell'),shellAfter);await pause(30);const shell=await peer.request('session.tree');assert(shell.entries.some(e=>e.type==='message'&&e.message.role==='bashExecution'));
  await peer.request('session.prompt',{text:'!!printf excluded-shell'});await pause(30);
  const exported=await peer.request('session.export',{path:join(f.dir,'chat.html')});const html=await readFile(exported.path,'utf8');assert(html.includes('<!DOCTYPE html>'));const encoded=html.match(/<script id="session-data" type="application\/json">([^<]+)<\/script>/)[1];assert(Buffer.from(encoded,'base64').toString().includes('integration-shell')); 
});

test('project trust is upstream gated and Store profile never loads executable extensions',async t=>{
  const f=await fixture();t.after(()=>f.dispose());await save(join(f.cwd,'.pi/extensions/project.ts'),extension);
  const peer=await start(f);t.after(()=>peer.stop());const creating=peer.request('session.create');
  const trust=await peer.event('ui.request',p=>p.title.includes('Trust project folder?'));
  await peer.request('ui.reply',{id:trust.id,value:trust.options.find(v=>v.includes('this session'))??trust.options[0]});await creating;
  assert((await peer.request('resources.list')).commands.some(c=>c.name==='fixture'));
  await peer.stop();
  await save(join(f.agentDir,'extensions/store-marker.ts'),`import {writeFileSync} from 'node:fs';export default function(){writeFileSync(${JSON.stringify(join(f.dir,'executed'))},'unsafe')}`);
  const store=await start(f,{profile:'store'});t.after(()=>store.stop());assert(store.hello.capabilities.includes('store.unsupported'));await assert.rejects(store.request('session.create'),e=>e.code==='profile.unsupported');await assert.rejects(store.request('session.prompt',{text:'execute'}),e=>e.code==='profile.unsupported');await assert.rejects(stat(join(f.dir,'executed')));assert(Array.isArray((await store.request('session.list')).sessions));
});

test('authentication, malformed NDJSON and private socket lifecycle',async t=>{
  const f=await fixture();t.after(()=>f.dispose());const peer=await start(f);t.after(()=>peer.stop());
  const outsider=createConnection(peer.path);await once(outsider,'connect');outsider.setEncoding('utf8');outsider.write(JSON.stringify({id:'attack',method:'hello',params:{version:1,token:'not-the-secret-token'}})+'\n');const [data]=await once(outsider,'data');assert.equal(JSON.parse(data).error.code,'protocol.authentication');outsider.destroy();
  const response=once(peer.socket,'data');peer.socket.write('{bad}\n');assert.equal(JSON.parse((await response)[0]).error.code,'protocol.json');
  await assert.rejects(peer.request('hello',{version:1,token:'any'}),e=>e.code==='protocol.handshake');
  await peer.stop();await assert.rejects(stat(peer.path));
});

test('an oversized outbound result returns an error without disconnecting the sidecar', async t => {
  const f = await fixture(); t.after(() => f.dispose());
  await save(join(f.agentDir, 'trigrams-host.json'), JSON.stringify({ systemPrompt: 'x'.repeat(5 * 1024 * 1024), skillDirectories: [], disabledSkills: [], theme: 'system' }));
  const peer = await start(f); t.after(() => peer.stop());
  await assert.rejects(peer.request('settings.get'), error => error.code === 'transport.frame');
  assert((await peer.request('models.list')).models.some(model => model.id === 'apple-foundation-model'));
  await peer.request('settings.update', { systemPrompt: '' });
  assert.equal((await peer.request('settings.get')).systemPrompt, '');
});
