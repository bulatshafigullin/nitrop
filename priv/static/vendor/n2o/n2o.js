
// N2O CORE
//
// Vendored, minimally modified fork of the n2o hex package's own
// priv/n2o.js (deps/n2o/priv/n2o.js) -- deliberate, not accidental drift:
// upstream hardcodes the WebSocket path as the literal string "/ws" inside
// N2O_start(), with no way to point a client at a different server-side
// route. The only change here is pulling that into its own `wsPath`
// variable, given the exact same "declare a default here, let the
// embedding page override it with a plain assignment after this script
// loads" treatment upstream already gives `host`/`debug`/`persistent` --
// see priv/static/live.htm, which sets `host`/`port`/`debug` that way
// already; `wsPath` follows the same convention, not a new one.
//
// Everything else below is byte-for-byte the same as upstream.

var active = false,
    debug = false,
    persistent = false,
    tokenStorage = persistent ? window.localStorage : window.sessionStorage,
    protocol = window.location.protocol == 'https:' ? "wss://" : "ws://",
    querystring = window.location.pathname + window.location.search,
    host = window.location.hostname,
    wsPath = "/ws";

function client() { return ''; }
function token()  { return tokenStorage.getItem("token")  || ''; };
function qi(name) { return document.getElementById(name); }
function qs(name) { return document.querySelector(name); }
function qa(name) { return document.querySelectorAll(name); }
function qn(name) { return document.createElement(name); }
function is(x, num, name) { return x == undefined ? false : (x.t == 106 ? false : (x.v.length === num && x.v[0].v === name)); }
function co(name) { match = document.cookie.match(new RegExp(name + '=([^;]+)')); return match ? match[1] : undefined; }

function N2O_start() {
    document.cookie = 'X-Auth-Token=' + token() + '; SameSite=Lax; path=/';
    ws = new bullet(protocol + host + (port==""?"":":"+port) + wsPath + querystring);
    ws.onmessage = function (evt) { // formatters loop
    for (var i=0;i<protos.length;i++) { p = protos[i]; if (p.on(evt, p.do).status == "ok") return; } };
    ws.onopen = function() { if (!active) { ws.send('N2O,'+token()); console.log('WS Connect'); active=true; } };
    ws.onclose = function() { active = false; console.log('WS Disconnect'); }; next(); }

/// N2O Protocols

var $io = {}; $io.on = function onio(r, cb) {
    if (is(r, 3, 'io')) {
        if (r.v[2].v != undefined && r.v[2].v[1] != undefined && r.v[2].v.length == 2 &&
           (r.v[2].v[0].v == "Token" || r.v[2].v[0].v == "Auth"))
         { tokenStorage.setItem("token",utf8_arr(r.v[2].v[1].v)); }
        if (typeof cb == 'function') cb(r.v[2]);
        var evalex = utf8_arr(r.v[1].v);
        if (debug) console.log(evalex);
        try { eval(evalex); return { status: "ok" }; }
        catch (e) { console.log(evalex);
                    console.error("Eval failed:",e);
                    return { status: '' }; }
    } else return { status: '' };
}

var $file = {}; $file.on = function onfile(r, cb) {
    if (is(r, 11, 'ftpack')) {
        if (typeof cb == 'function') cb(r); return { status: "ok" };
    } else return { status: '' };
}

// BERT Formatter

var $bert = {}; $bert.protos = [$io, $file]; $bert.on = function onbert(evt, cb) {
    if (ArrayBuffer.prototype.isPrototypeOf(evt.data) &&
       (evt.data.byteLength > 0)) {
        try {
            var erlang = dec(evt.data);
            if (typeof cb == 'function') cb(erlang);
            for (var i = 0; i < $bert.protos.length; i++) {
                var p = $bert.protos[i];
                var ret = p.on(erlang, p.do);
                if (ret != undefined && ret.status == "ok") return ret;
            }
        } catch (e) { console.error(e); }
        return { status: "ok" };
    } else return { status: "error", desc: "data" };
}

var protos = [$bert];
