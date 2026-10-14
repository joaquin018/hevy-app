import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const file = name => path.join(root, name);
const read = name => readFileSync(file(name), 'utf8');
const write = (name, value) => writeFileSync(file(name), value);
const [command = 'check', argument] = process.argv.slice(2);

function releaseNotes(tag) {
  if (!/^v[1-9]\d*$/.test(tag)) throw new Error('Usa una etiqueta como v16.');
  const changelog = read('CHANGELOG.md');
  const marker = `## [${tag}]`;
  const start = changelog.indexOf(marker + ' —');
  if (start === -1) throw new Error(`Faltan las notas de ${tag} en CHANGELOG.md.`);
  const bodyStart = changelog.indexOf('\n', start) + 1;
  const next = changelog.indexOf('\n## ', bodyStart);
  return changelog.slice(bodyStart, next === -1 ? undefined : next).trim();
}

try {
  const current = read('VERSION').trim();
  if (!/^[1-9]\d*\.0\.0$/.test(current)) throw new Error('VERSION debe corresponder a la numeración vN: N.0.0.');
  const number = Number(current.split('.')[0]);
  const tag = `v${number}`;
  if (command === 'prepare') {
    if (!/^[1-9]\d*$/.test(argument ?? '') || Number(argument) !== number + 1) {
      throw new Error(`La siguiente versión debe ser ${number + 1}: bun scripts/version.mjs prepare ${number + 1}`);
    }
    const version = `${argument}.0.0`;
    const backend = JSON.parse(read('backend/package.json'));
    const frontend = read('frontend/pubspec.yaml');
    const readme = read('README.md');
    if (!/^version: .+$/m.test(frontend)) throw new Error('No se encontró la versión de Flutter.');
    if (!/^Versión actual: \*\*v\d+\*\*/m.test(readme)) throw new Error('No se encontró la versión en README.md.');
    backend.version = version;
    write('backend/package.json', JSON.stringify(backend, null, 2) + '\n');
    write('frontend/pubspec.yaml', frontend.replace(/^version: .+$/m, `version: ${version}+${argument}`));
    write('VERSION', version + '\n');
    write('README.md', readme.replace(/^Versión actual: \*\*v\d+\*\*/m, `Versión actual: **v${argument}**`));
    console.log(`Preparada v${argument}. Añade sus notas a CHANGELOG.md y ejecuta check antes del commit.`);
  } else if (command === 'check') {
    if (argument && argument !== tag) throw new Error(`La etiqueta ${argument} no corresponde a VERSION (${tag}).`);
    const backend = JSON.parse(read('backend/package.json')).version;
    const frontend = /^version: (.+)$/m.exec(read('frontend/pubspec.yaml'))?.[1].trim();
    if (backend !== current || frontend !== `${current}+${number}`) throw new Error('VERSION, backend y Flutter no coinciden.');
    if (!read('README.md').includes(`Versión actual: **${tag}**`)) throw new Error('La versión de README.md no coincide.');
    releaseNotes(tag);
    console.log(`${tag}: VERSION ${current}, backend ${backend}, Flutter ${frontend}. Notas verificadas.`);
  } else if (command === 'notes') {
    process.stdout.write(releaseNotes(argument ?? tag) + '\n');
  } else {
    throw new Error('Uso: bun scripts/version.mjs check [vN] | prepare N | notes [vN]');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
