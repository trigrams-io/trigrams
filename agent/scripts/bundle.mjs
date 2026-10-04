// Keep the SDK's dynamic extension loader, workers, WASM, and native binaries intact.
// Packaging copies dist/ + production node_modules/ as one self-contained sidecar.
import { readFile } from 'node:fs/promises';
const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
if (pkg.dependencies['@earendil-works/pi-coding-agent'] !== '1.0.2') throw new Error('Update the compatibility fixtures before upgrading pi.');
