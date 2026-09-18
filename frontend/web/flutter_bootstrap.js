{{flutter_js}}
{{flutter_build_config}}
const deployedVersion = '__DEPLOY_VERSION__';
if (!deployedVersion.startsWith('__')) {
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) build.mainJsPath += '?v=' + deployedVersion;
  }
}
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(console.error);
}
_flutter.loader.load();
