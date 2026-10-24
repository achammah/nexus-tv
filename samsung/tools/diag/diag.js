// Temporary diagnostics, added only to a DIAG=1 package: sends player events to the Mac on the LAN.
(function () {
    var SINK = 'http://__MAC__:8815/log';
    window.diag = function (o) {
        try { o.t = new Date().toISOString(); var x = new XMLHttpRequest(); x.open('POST', SINK, true); x.setRequestHeader('Content-Type', 'text/plain'); x.send(JSON.stringify(o)); } catch (e) { /* never break the app */ }
    };
    window.addEventListener('error', function (e) { diag({ ev: 'window.error', msg: e.message, src: (e.filename || '').split('/').pop(), line: e.lineno }); });
    diag({ ev: 'boot' });
})();
