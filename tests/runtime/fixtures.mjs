export const extension = `
import { Type } from 'typebox';
import { Text, Key } from '@earendil-works/pi-tui';
export default function(pi) {
  pi.registerTool({ name:'fixture_echo', label:'Echo', description:'Echo text for integration', parameters:Type.Object({text:Type.String()}), execute:async(id,p)=>({content:[{type:'text',text:'Extension says '+p.text}],details:{echo:p.text}}) });
  pi.registerCommand('fixture', { description:'Native extension command', handler:async(args,ctx)=>{
    pi.appendEntry('fixture-entry', {args,mode:ctx.mode});
    ctx.ui.notify('Fixture command '+args);
    ctx.ui.setStatus('fixture','ready');
    ctx.ui.setWorkingMessage('working'); ctx.ui.setWorkingVisible(false); ctx.ui.setWorkingVisible(true);
    ctx.ui.setWorkingIndicator({frames:['*'],intervalMs:100}); ctx.ui.setHiddenThinkingLabel('Thought');
    ctx.ui.setWidget('strings',['one','two']); ctx.ui.setToolsExpanded(true);
    ctx.ui.setEditorText('editor seed'); ctx.ui.pasteToEditor(' + paste');
    ctx.ui.notify(ctx.ui.getEditorText());
    const yes=await ctx.ui.confirm('Confirm','Continue?');
    const pick=await ctx.ui.select('Choose',['one','two']);
    const input=await ctx.ui.input('Input','type');
    const edited=await ctx.ui.editor('Editor','prefill');
    pi.appendEntry('fixture-dialogs',{yes,pick,input,edited,expanded:ctx.ui.getToolsExpanded(),themes:ctx.ui.getAllThemes().length,theme:ctx.ui.theme.name});
    ctx.ui.setStatus('fixture',undefined); ctx.ui.setWidget('strings',undefined);
  }});
  pi.registerCommand('timeout', {handler:async(args,ctx)=>{const value=await ctx.ui.input('Timed','',{timeout:10});pi.appendEntry('timeout-result',{value});}});
  pi.registerCommand('abort-dialog', {handler:async(args,ctx)=>{const controller=new AbortController();setTimeout(()=>controller.abort(),10);const value=await ctx.ui.select('Abort',['one'],{signal:controller.signal});pi.appendEntry('abort-dialog-result',{value});}});
  pi.registerCommand('tui-fixture', {handler:async(args,ctx)=>{
    if(ctx.mode!=='tui') throw new Error('Fixture needs genuine tui mode');
    ctx.ui.setHeader((tui,theme)=>new Text(theme.bold('Fixture header'),0,0));
    ctx.ui.setFooter((tui,theme,footer)=>new Text('Footer '+footer.getGitBranch(),0,0));
    ctx.ui.setWidget('component',(tui,theme)=>new Text('Component widget',0,0));
    const off=ctx.ui.onTerminalInput(data=>data==='x'?{consume:true}:undefined);
    const result=await ctx.ui.custom((tui,theme,keybindings,done)=>({render:width=>[theme.fg('accent','Overlay fixture '+width)],handleInput:data=>{if(data==='y')done('accepted')},invalidate(){},dispose(){pi.appendEntry('fixture-disposed',{value:true})}}),{overlay:true,overlayOptions:{width:'60%',anchor:'center'},onHandle:handle=>{handle.setHidden(false);handle.focus();handle.getBounds();handle.isHidden();handle.isFocused()}});
    pi.appendEntry('fixture-tui-result',{result}); off();
    ctx.ui.setHeader(undefined);ctx.ui.setFooter(undefined);ctx.ui.setWidget('component',undefined);
  }});
  pi.registerCommand('custom-editor', {handler:async(args,ctx)=>{ctx.ui.addAutocompleteProvider(current=>current);ctx.ui.setEditorComponent((tui,theme,keybindings)=>{let text='';return {render:w=>['Custom editor '+text],handleInput:data=>{text+=data},getText:()=>text,setText:value=>text=value,invalidate(){},dispose(){pi.appendEntry('editor-disposed',{})}}});ctx.ui.notify(String(Boolean(ctx.ui.getEditorComponent())));ctx.ui.setEditorText('custom');ctx.ui.pasteToEditor('!');ctx.ui.notify(ctx.ui.getEditorText());}});
  pi.registerCommand('restore-editor', {handler:async(args,ctx)=>ctx.ui.setEditorComponent(undefined)});
  pi.registerCommand('theme-fixture', {handler:async(args,ctx)=>{const dark=ctx.ui.getTheme('dark');if(!dark)throw new Error('Missing built-in dark theme');ctx.ui.setTheme(dark);ctx.ui.setTheme('light');const result=ctx.ui.setTheme('does-not-exist');pi.appendEntry('theme-result',result)}});
}
`;
export const mcp = `
let buffer='';process.stdin.setEncoding('utf8');process.stdin.on('data',data=>{buffer+=data;let i;while((i=buffer.indexOf('\\n'))>=0){const r=JSON.parse(buffer.slice(0,i));buffer=buffer.slice(i+1);if(r.id===undefined)continue;let result={};if(r.method==='initialize')result={protocolVersion:'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'fixture',version:'1'},instructions:'Fixture echo MCP'};if(r.method==='tools/list')result={tools:[{name:'echo',description:'Echo fixture text',inputSchema:{type:'object',properties:{text:{type:'string'}},required:['text'],additionalProperties:false}}]};if(r.method==='tools/call')result={content:[{type:'text',text:'MCP says '+r.params.arguments.text}]};process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:r.id,result})+'\\n')}});
`;
