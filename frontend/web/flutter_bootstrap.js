{{flutter_js}}
{{flutter_build_config}}
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(console.error);
}
_flutter.loader.load();
