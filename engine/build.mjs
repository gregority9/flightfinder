import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const pinned = '881aee5ff4321e81ea2157cb44be94ce6a21dc1b';
const temp = mkdtempSync(path.join(tmpdir(), 'flightfinder-fli-'));
try {
  const source = process.env.FLI_SOURCE || path.join(temp, 'fli');
  if (!process.env.FLI_SOURCE) {
    execFileSync('git', ['init', source], {stdio:'ignore'});
    execFileSync('git', ['-C', source, 'fetch', '--depth', '1', 'https://github.com/punitarani/fli.git', pinned], {stdio:'inherit'});
    execFileSync('git', ['-C', source, 'checkout', '--detach', 'FETCH_HEAD'], {stdio:'ignore'});
  }
  if (execFileSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim() !== pinned) throw Error('Fli revision mismatch');
  const output = path.join(root, 'ios/FlightDeck/Engine');
  mkdirSync(output, {recursive:true});
  await build({
    entryPoints:[path.join(root,'engine/adapter.ts')], outfile:path.join(output,'fli-engine.js'),
    bundle:true, format:'iife', globalName:'FlightEngine', platform:'browser', target:'safari17',
    minify:true, legalComments:'eof', nodePaths:[path.join(root,'node_modules')],
    alias:{'@fli':path.join(source,'fli-js/src'), 'node:buffer':path.join(root,'engine/no-node.ts')},
  });
  // Polyfills must execute before the bundled dependency's top-level TextEncoder construction.
  const fs = await import('node:fs/promises');
  const bundled = await fs.readFile(path.join(output,'fli-engine.js'),'utf8');
  const polyfills = await fs.readFile(path.join(root,'engine/polyfills.js'),'utf8');
  writeFileSync(path.join(output,'fli-engine.js'), '/* Fli MIT, pinned '+pinned+' */\n'+polyfills+'\n'+bundled);
  copyFileSync(path.join(source,'LICENSE.txt'),path.join(output,'FLI-LICENSE.txt'));
} finally { rmSync(temp,{recursive:true,force:true}); }
