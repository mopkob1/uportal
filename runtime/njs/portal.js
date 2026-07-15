import fs from 'fs';
import crypto from 'crypto';

var TEMPLATE_CAPTIONS = {
    en: {
        lang: 'en',
        fallbackTitle: 'Link unavailable',
        fallbackText: 'It may have expired, been disabled, or contain an error.',
        protectedDescription: 'A password is required to access this link.',
        passwordHintLabel: 'Hint',
        passwordPlaceholder: 'Enter password',
        continueText: 'Continue',
        invalidPassword: 'Invalid password',
        passwordCheckError: 'Password check failed',
        redirectStartsIn: 'Redirect starts in',
        downloadStartsIn: 'Download starts in',
        secondsLabel: 'sec.',
        fileLabel: 'File',
        poweredByPrefix: 'Powered by',
        poweredByCtaPrefix: 'Do the',
        poweredByCtaLink: 'same',
        loading: 'Loading...',
        accessDenied: 'Access denied',
        linkExpired: 'Link expired or invalid',
        pageTitle: 'Page',
        redirectTitle: 'Redirect',
        downloadTitle: 'Download',
        pixelTitle: 'Pixel'
    },
    ru: {
        lang: 'ru',
        fallbackTitle: 'Ссылка недоступна',
        fallbackText: 'Возможно, она истекла, была отключена или содержит ошибку.',
        protectedDescription: 'Для доступа нужен пароль.',
        passwordHintLabel: 'Подсказка',
        passwordPlaceholder: 'Введите пароль',
        continueText: 'Продолжить',
        invalidPassword: 'Неверный пароль',
        passwordCheckError: 'Ошибка проверки пароля',
        redirectStartsIn: 'Переход начнётся через',
        downloadStartsIn: 'Скачивание начнётся через',
        secondsLabel: 'сек.',
        fileLabel: 'Файл',
        poweredByPrefix: 'Работает на',
        poweredByCtaPrefix: 'Сделайте',
        poweredByCtaLink: 'так же',
        loading: 'Загрузка...',
        accessDenied: 'Доступ запрещён',
        linkExpired: 'Ссылка истекла или недействительна',
        pageTitle: 'Страница',
        redirectTitle: 'Redirect',
        downloadTitle: 'Download',
        pixelTitle: 'Pixel'
    },
    es: {
        lang: 'es',
        fallbackTitle: 'Enlace no disponible',
        fallbackText: 'Puede haber caducado, estar desactivado o contener un error.',
        protectedDescription: 'Se requiere una contraseña para acceder a este enlace.',
        passwordHintLabel: 'Pista',
        passwordPlaceholder: 'Introduce la contraseña',
        continueText: 'Continuar',
        invalidPassword: 'Contraseña incorrecta',
        passwordCheckError: 'Error al comprobar la contraseña',
        redirectStartsIn: 'La redirección empieza en',
        downloadStartsIn: 'La descarga empieza en',
        secondsLabel: 'seg.',
        fileLabel: 'Archivo',
        poweredByPrefix: 'Creado con',
        poweredByCtaPrefix: 'Hazlo',
        poweredByCtaLink: 'también',
        loading: 'Cargando...',
        accessDenied: 'Acceso denegado',
        linkExpired: 'Enlace caducado o no válido',
        pageTitle: 'Página',
        redirectTitle: 'Redirect',
        downloadTitle: 'Download',
        pixelTitle: 'Pixel'
    }
};

function jsStr(s) {
    return JSON.stringify(String(s || ''));
}

function cfg(r, name, fallback) {
    var v = r.variables[name];
    if (v === undefined || v === null || v === '') return fallback;
    return v;
}

function readText(path) {
    try { return fs.readFileSync(path, 'utf8'); } catch (e) { return null; }
}

function readBin(path) {
    try { return fs.readFileSync(path); } catch (e) { return null; }
}

function readJson(path) {
    var raw = readText(path);
    if (raw === null) return null;
    try { return JSON.parse(raw); } catch (e) { return null; }
}

function writeJson(path, value) {
    try {
        fs.writeFileSync(path, JSON.stringify(value, null, 2) + '\n');
        return true;
    } catch (e) {
        return false;
    }
}

function escHtml(s) {
    s = String(s || '');
    return s
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function escAttr(s) {
    return escHtml(s).replace(/'/g, '&#39;');
}

function replaceAllCompat(str, needle, value) {
    return String(str).split(needle).join(value);
}

function render(tpl, vars) {
    var out = String(tpl || '');
    for (var k in vars) {
        if (!Object.prototype.hasOwnProperty.call(vars, k)) continue;
        out = replaceAllCompat(out, '{{' + k + '}}', String(vars[k]));
    }
    return out;
}

function normalizeLang(value) {
    var lang = String(value || '').trim().toLowerCase().replace('_', '-').split('-')[0];
    return TEMPLATE_CAPTIONS[lang] ? lang : 'en';
}

function supportedLang(value) {
    var lang = String(value || '').trim().toLowerCase().replace('_', '-').split('-')[0];
    return TEMPLATE_CAPTIONS[lang] ? lang : '';
}

function metaLang(meta) {
    return normalizeLang(meta && meta.lang);
}

function requestLang(r) {
    if (r.args && r.args.lang) return normalizeLang(r.args.lang);

    var accept = String(r.headersIn['Accept-Language'] || '');
    var parts = accept.split(',');
    for (var i = 0; i < parts.length; i++) {
        var lang = supportedLang(parts[i].split(';')[0]);
        if (TEMPLATE_CAPTIONS[lang]) return lang;
    }

    return 'en';
}

function captions(lang) {
    return TEMPLATE_CAPTIONS[normalizeLang(lang)] || TEMPLATE_CAPTIONS.en;
}

function templateCaptionVars(lang) {
    var c = captions(lang);
    return {
        LANG: escAttr(c.lang),
        FALLBACK_TITLE: escHtml(c.fallbackTitle),
        FALLBACK_TEXT: escHtml(c.fallbackText),
        PASSWORD_HINT_LABEL: escHtml(c.passwordHintLabel),
        PASSWORD_PLACEHOLDER: escAttr(c.passwordPlaceholder),
        CONTINUE: escHtml(c.continueText),
        INVALID_PASSWORD: escHtml(c.invalidPassword),
        PASSWORD_CHECK_ERROR: escHtml(c.passwordCheckError),
        REDIRECT_STARTS_IN: escHtml(c.redirectStartsIn),
        DOWNLOAD_STARTS_IN: escHtml(c.downloadStartsIn),
        SECONDS_LABEL: escHtml(c.secondsLabel),
        FILE_LABEL: escHtml(c.fileLabel),
        POWERED_BY_PREFIX: escHtml(c.poweredByPrefix),
        POWERED_BY_CTA_PREFIX: escHtml(c.poweredByCtaPrefix),
        POWERED_BY_CTA_LINK: escHtml(c.poweredByCtaLink),
        LOADING: escHtml(c.loading),
        ACCESS_DENIED: escHtml(c.accessDenied),
        LINK_EXPIRED: escHtml(c.linkExpired)
    };
}

function normalizeText(s) {
    return String(s || '').replace(/\s+/g, ' ').trim();
}

function linkPreviewTitle(meta, fallback) {
    var title = normalizeText([
        meta && meta.pre,
        meta && meta.link,
        meta && meta.post
    ].filter(function (part) { return !!part; }).join(' '));

    return title || normalizeText(meta && meta.title) || fallback;
}

function linkPreviewDescription(meta) {
    return normalizeText(meta && meta.subj) || normalizeText(meta && meta.description);
}

function wantsHtmlPreview(r) {
    var accept = String(r.headersIn.Accept || '');
    if (accept.indexOf('text/html') >= 0) return true;
    return accept.indexOf('image/') < 0;
}

function publicAssetUrl(r, meta) {
    if (!meta || !meta.image) return '';
    var base = cfg(r, 'uportal_base_url', 'http://localhost:8080');
    return base + '/assets-public/' +
        meta.publication_id + '/' +
        meta.token + '/' +
        safeSeg(meta.image, 'cover.png');
}

function renderShortPreview(r, meta, fallbackTitle) {
    var lang = metaLang(meta);
    var image = publicAssetUrl(r, meta);
    var title = linkPreviewTitle(meta, fallbackTitle);
    var description = linkPreviewDescription(meta);

    r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';
    return r.return(200, '<!doctype html><html lang="' + escAttr(lang) + '"><head>' +
        '<meta charset="utf-8"/>' +
        '<meta name="viewport" content="width=device-width, initial-scale=1"/>' +
        '<title>' + escHtml(title) + '</title>' +
        '<meta property="og:type" content="website"/>' +
        '<meta property="og:title" content="' + escAttr(title) + '"/>' +
        '<meta property="og:description" content="' + escAttr(description) + '"/>' +
        '<meta property="og:image" content="' + escAttr(image) + '"/>' +
        '</head><body></body></html>');
}

function safeSeg(s, fallback) {
    s = String(s || '').trim();
    if (!s) return fallback;
    s = s.replace(/[^A-Za-z0-9._ \-]/g, '_');
    if (s.length > 200) s = s.slice(0, 200);
    return s || fallback;
}

function safeFileSeg(s, fallback) {
    s = String(s || '').trim();
    if (!s) return fallback;
    s = s.replace(/[^A-Za-z0-9._-]/g, '_');
    if (s.length > 200) s = s.slice(0, 200);
    return s || fallback;
}

function safeDownloadName(s, fallback) {
    s = String(s || '').trim();
    if (!s) return fallback;
    s = s.replace(/[\u0000-\u001f\u007f\/\\]/g, '_');
    s = s.replace(/"/g, "'");
    if (s.length > 200) s = s.slice(0, 200);
    s = s.trim();
    return s || fallback;
}

function publicAssetContentType(rel, bin) {
    if (bin && bin.length >= 3 && bin[0] === 0xff && bin[1] === 0xd8 && bin[2] === 0xff) {
        return 'image/jpeg';
    }
    if (bin && bin.length >= 8 &&
        bin[0] === 0x89 && bin[1] === 0x50 && bin[2] === 0x4e && bin[3] === 0x47 &&
        bin[4] === 0x0d && bin[5] === 0x0a && bin[6] === 0x1a && bin[7] === 0x0a) {
        return 'image/png';
    }
    if (bin && bin.length >= 6) {
        var gif = String.fromCharCode(bin[0], bin[1], bin[2], bin[3], bin[4], bin[5]);
        if (gif === 'GIF87a' || gif === 'GIF89a') return 'image/gif';
    }
    var lower = String(rel || '').toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
}

function b64url(buf) {
    return buf.toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/g, '');
}

function parseCookies(r) {
    var out = {};
    var src = r.headersIn.Cookie || '';
    if (!src) return out;
    src.split(';').forEach(function (part) {
        var idx = part.indexOf('=');
        if (idx < 0) return;
        var k = part.slice(0, idx).trim();
        var v = part.slice(idx + 1).trim();
        if (k) out[k] = v;
    });
    return out;
}

function signHmac(secret, value) {
    return crypto.createHmac('sha256', secret).update(value).digest('hex');
}

function sha256hex(value) {
    return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function metaPath(r, publicationId, token) {
    return cfg(r, 'uportal_meta_root', '/data/files/uportal/meta') + '/' + publicationId + '/' + token + '.json';
}

function shortPath(r, shortId) {
    return cfg(r, 'uportal_short_root', '/data/files/uportal/short') + '/' + shortId + '.json';
}

function payloadDir(r, publicationId, token) {
    return cfg(r, 'uportal_storage_root', '/data/files/uportal/storage') + '/' + publicationId + '/' + token + '/payload';
}

function stickyDir(r, publicationId) {
    return cfg(r, 'uportal_sticky_root', '/data/files/uportal/sticky') + '/' + publicationId;
}

function stickyPath(r, publicationId, token) {
    return stickyDir(r, publicationId) + '/' + token + '.json';
}

function inboxDir(r, publicationId, token) {
    var root = cfg(r, 'uportal_upload_root', '/data/files/inbox');
    if (root.indexOf('/data/') !== 0) root = '/data' + root;
    return root + '/' + publicationId + '/' + token;
}

function pageDir(r, publicationId, token) {
    return cfg(r, 'uportal_storage_root', '/data/files/uportal/storage') + '/' + publicationId + '/' + token + '/page';
}

function templatePath(r, name) {
    return cfg(r, 'uportal_template_root', '/data/files/uportal/templates') + '/' + name;
}

function addBrandVars(r, vars) {
    var logo = readText(templatePath(r, 'uportal-logo.svg'));
    vars.UPORTAL_GITHUB_URL = escAttr(cfg(r, 'uportal_github_url', 'https://github.com/mopkob1/uportal'));
    vars.UPORTAL_LOGO_SVG = logo || '<span>UPORTAL</span>';
    return vars;
}

function readMeta(r, publicationId, token) {
    return readJson(metaPath(r, publicationId, token));
}

function readShort(r, shortId) {
    return readJson(shortPath(r, shortId));
}

function isSticky(meta) {
    if (!meta) return false;
    return meta.sticky === true || meta.sticky === 1 || String(meta.sticky || '').toLowerCase() === 'true';
}

function ensureDir(path) {
    var parts = String(path || '').split('/');
    var current = '';

    for (var i = 0; i < parts.length; i++) {
        if (!parts[i]) continue;
        current += '/' + parts[i];

        try {
            fs.mkdirSync(current);
        } catch (e) {}
    }
}

function enforceSticky(r, meta) {
    if (!isSticky(meta)) return true;

    var publicationId = meta.publication_id || '';
    var token = meta.token || '';
    if (!publicationId || !token) return false;

    var uid = ensureUidCookie(r);
    var path = stickyPath(r, publicationId, token);
    var binding = readJson(path);

    if (binding && binding.uid) {
        return binding.uid === uid;
    }

    ensureDir(stickyDir(r, publicationId));
    if (!writeJson(path, {
        publication_id: publicationId,
        token: token,
        uid: uid,
        bound_at: new Date().toISOString()
    })) {
        r.error('failed to write sticky binding: ' + path);
        return false;
    }

    return true;
}

function isActive(meta) {
    if (!meta) return false;
    if (meta.status === undefined || meta.status === null || meta.status === '') return true;
    return String(meta.status).toLowerCase() === 'active';
}

function isFresh(meta) {
    if (!meta) return false;
    if (meta.fresh_until === undefined || meta.fresh_until === null || meta.fresh_until === '' || meta.fresh_until === -1 || meta.fresh_until === '-1') return true;
    var expires = Date.parse(meta.fresh_until);
    if (isNaN(expires)) return false;
    return Date.now() <= expires;
}

function hasClicks(meta) {
    if (!meta) return false;
    if (meta.remaining_clicks === undefined || meta.remaining_clicks === null || meta.remaining_clicks === '' || meta.remaining_clicks === -1 || meta.remaining_clicks === '-1') return true;
    var n = parseInt(meta.remaining_clicks, 10);
    if (isNaN(n)) return false;
    return n > 0;
}

function getFallback(r, meta) {
    var url = meta && meta.fallback_url ? meta.fallback_url : cfg(r, 'uportal_fallback_url', 'http://localhost:8080/link-fallback');
    var lang = supportedLang(meta && meta.lang);
    if (!lang) return url;
    if (url.indexOf('lang=') >= 0) return url;
    return url + (url.indexOf('?') >= 0 ? '&' : '?') + 'lang=' + encodeURIComponent(lang);
}

function safeRedirect(r, url) {
    r.return(302, url || cfg(r, 'uportal_fallback_url', 'http://localhost:8080/link-fallback'));
}

function statTtl(meta) {
    var v = parseInt(meta && meta.stat_ttl_sec, 10);
    if (!v || v < 5) return 15;
    return v;
}

function pageTtl(meta) {
    var v = parseInt(meta && meta.page_ttl_sec, 10);
    if (!v || v < 30) return 1800;
    return v;
}

function downloadTtl(meta) {
    var v = parseInt(meta && meta.download_ttl_sec, 10);
    if (!v || v < 10) return 60;
    return v;
}

function passwordTtl(meta) {
    var v = parseInt(meta && meta.password_ttl_sec, 10);
    if (!v || v < 30) return 1800;
    return v;
}

function statMd5(secret, expires, uri) {
    return crypto.createHash('md5').update(String(expires) + uri + secret).digest('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/g, '');
}

function signedTrackUrl(r, meta, event) {
    var uri = '/api/track/' + event + '/' + meta.publication_id + '/' + meta.token;
    var expires = Math.floor(Date.now() / 1000) + statTtl(meta);
    var secret = cfg(r, 'uportal_stat_secret', 'CHANGE_ME_STAT_SECRET');
    var md5 = statMd5(secret, expires, uri);
    return uri + '?e=' + expires + '&md5=' + md5;
}

function signedOpenUrl(r, meta) {
    return signedTrackUrl(r, meta, 'open');
}

function signedClickUrl(r, meta) {
    return signedTrackUrl(r, meta, 'click');
}

function signedPageViewUrl(r, meta) {
    return signedTrackUrl(r, meta, 'page_view');
}

function signedContentUrl(r, meta) {
    return signedTrackUrl(r, meta, 'content');
}

function signedPixelUrl(r, meta) {
    return signedTrackUrl(r, meta, 'pixel');
}

function signedDownloadUrl(r, meta) {
    return signedTrackUrl(r, meta, 'download');
}

async function trackPixelEvent(r, publicationId, token) {
    try {
        await r.subrequest(
            '/__uportal_track_pixel_shhoook/' +
            encodeURIComponent(publicationId) +
            '/' +
            encodeURIComponent(token),
            { method: 'POST' }
        );
    } catch (e) {
        r.error('pixel shhoook subrequest failed: ' + e);
    }

    try {
        await r.subrequest(
            '/__uportal_track_pixel_n8n/' +
            encodeURIComponent(publicationId) +
            '/' +
            encodeURIComponent(token),
            { method: 'POST' }
        );
    } catch (e) {}
}

function addSetCookie(r, cookie) {
    var cur = r.headersOut['Set-Cookie'];

    if (!cur) {
        r.headersOut['Set-Cookie'] = cookie;
        return;
    }

    if (Array.isArray(cur)) {
        cur.push(cookie);
        r.headersOut['Set-Cookie'] = cur;
        return;
    }

    r.headersOut['Set-Cookie'] = [cur, cookie];
}

function randomIdHex() {
    var seed = [
        Date.now(),
        Math.random(),
        Math.random(),
        Math.random()
    ].join('|');

    return crypto.createHash('sha256')
        .update(seed)
        .digest('hex')
        .slice(0, 32);
}

function ensureUidCookie(r) {
    var cookies = parseCookies(r);
    var raw = cookies.uportal_uid || '';
    var secret = cfg(r, 'uportal_uid_secret', cfg(r, 'uportal_page_secret', 'CHANGE_ME_PAGE_SECRET'));

    if (raw) {
        var parts = raw.split('|');
        if (parts.length === 2) {
            var uid = parts[0];
            var sig = parts[1];
            if (/^[a-f0-9]{32}$/.test(uid) && signHmac(secret, uid) === sig) {
                return uid;
            }
        }
    }

    var newUid = randomIdHex();
    var newSig = signHmac(secret, newUid);

    var cookie = 'uportal_uid=' + newUid + '|' + newSig + '; Path=/; Max-Age=31536000; HttpOnly; SameSite=Lax';
    if ((r.variables.scheme || '').toLowerCase() === 'https') cookie += '; Secure';

    addSetCookie(r, cookie);
    return newUid;
}


function setPageCookie(r, meta) {
    var ttl = pageTtl(meta);
    var exp = Math.floor(Date.now() / 1000) + ttl;
    var payload = meta.publication_id + '|' + meta.token + '|' + exp;
    var secret = cfg(r, 'uportal_page_secret', 'CHANGE_ME_PAGE_SECRET');
    var sig = signHmac(secret, payload);
    var cookie = 'uportal_page=' + payload + '|' + sig + '; Path=/; HttpOnly; SameSite=Lax';
    if ((r.variables.scheme || '').toLowerCase() === 'https') cookie += '; Secure';
    addSetCookie(r, cookie);
}

function checkPageCookie(r, publicationId, token) {
    var cookies = parseCookies(r);
    var raw = cookies.uportal_page;
    if (!raw) return false;
    var parts = raw.split('|');
    if (parts.length !== 4) return false;
    var pub = parts[0];
    var tok = parts[1];
    var exp = parts[2];
    var sig = parts[3];
    if (pub !== publicationId || tok !== token) return false;
    var payload = pub + '|' + tok + '|' + exp;
    var secret = cfg(r, 'uportal_page_secret', 'CHANGE_ME_PAGE_SECRET');
    if (signHmac(secret, payload) !== sig) return false;
    if (Math.floor(Date.now() / 1000) > parseInt(exp, 10)) return false;
    return true;
}

function hasPassword(meta) {
    return !!(meta && typeof meta.password_hash === 'string' && meta.password_hash.length > 0);
}

function normalizePasswordHash(meta) {
    var raw = String(meta && meta.password_hash || '').trim();
    if (!raw) return '';
    if (raw.indexOf('sha256:') === 0) return raw.slice(7).toLowerCase();
    return raw.toLowerCase();
}

function setPasswordCookie(r, meta) {
    var ttl = passwordTtl(meta);
    var exp = Math.floor(Date.now() / 1000) + ttl;
    var payload = meta.publication_id + '|' + meta.token + '|' + exp;
    var secret = cfg(r, 'uportal_pw_secret', cfg(r, 'uportal_page_secret', 'CHANGE_ME_PAGE_SECRET'));
    var sig = signHmac(secret, payload);
    var cookie = 'uportal_pw=' + payload + '|' + sig + '; Path=/; HttpOnly; SameSite=Lax';
    if ((r.variables.scheme || '').toLowerCase() === 'https') cookie += '; Secure';
    addSetCookie(r, cookie);
}

function clearPasswordCookie(r) {
    var cookie = 'uportal_pw=deleted; Path=/; Max-Age=0; HttpOnly; SameSite=Lax';
    if ((r.variables.scheme || '').toLowerCase() === 'https') cookie += '; Secure';
    addSetCookie(r, cookie);
}

function checkPasswordCookie(r, publicationId, token) {
    var cookies = parseCookies(r);
    var raw = cookies.uportal_pw;
    if (!raw) return false;
    var parts = raw.split('|');
    if (parts.length !== 4) return false;
    var pub = parts[0];
    var tok = parts[1];
    var exp = parts[2];
    var sig = parts[3];
    if (pub !== publicationId || tok !== token) return false;
    var payload = pub + '|' + tok + '|' + exp;
    var secret = cfg(r, 'uportal_pw_secret', cfg(r, 'uportal_page_secret', 'CHANGE_ME_PAGE_SECRET'));
    if (signHmac(secret, payload) !== sig) return false;
    if (Math.floor(Date.now() / 1000) > parseInt(exp, 10)) return false;
    return true;
}

function isPasswordAuthorized(r, meta) {
    if (!hasPassword(meta)) return true;
    return checkPasswordCookie(r, meta.publication_id, meta.token);
}

function requirePasswordPage(r, meta) {
    var tpl = readText(templatePath(r, 'password.html'));
    if (tpl === null) {
        return r.return(500, 'password template not found');
    }

    var lang = metaLang(meta);
    var c = captions(lang);
    var redirectTo = meta && meta.short_id ? '/s/' + meta.short_id : '/';
    var vars = templateCaptionVars(lang);
    vars.TITLE = escHtml(meta.title || c.fallbackTitle);
    vars.DESCRIPTION = escHtml(meta.description || c.protectedDescription);
    vars.PASSWORD_HINT = escHtml(meta.password_hint || '');
    vars.AUTH_URL = escAttr('/api/auth/' + meta.publication_id + '/' + meta.token);
    vars.REDIRECT_TO = escAttr(redirectTo);
    addBrandVars(r, vars);

    var html = render(tpl, vars);
    r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(200, html);
}

function extractPubToken(uri, rx) {
    var m = uri.match(rx);
    if (!m) return null;
    return { publication_id: m[1], token: m[2] };
}

function parseBodyParam(body, name) {
    var s = String(body || '');
    if (!s) return '';
    var parts = s.split('&');
    for (var i = 0; i < parts.length; i++) {
        var kv = parts[i].split('=');
        var k = decodeURIComponent((kv[0] || '').replace(/\+/g, ' '));
        if (k !== name) continue;
        var v = decodeURIComponent((kv.slice(1).join('=') || '').replace(/\+/g, ' '));
        return v;
    }
    return '';
}

async function dispatchShort(r) {
    var m = r.uri.match(/^\/s\/([A-Za-z0-9]{9})$/);
    if (!m) return safeRedirect(r, cfg(r, 'uportal_fallback_url', 'http://localhost:8080/link-fallback'));

    var shortId = m[1];
    var ref = readShort(r, shortId);
    if (!ref || !ref.publication_id || !ref.token) {
        return safeRedirect(r, cfg(r, 'uportal_fallback_url', 'http://localhost:8080/link-fallback'));
    }

    var meta = readMeta(r, ref.publication_id, ref.token);
    if (!meta || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return safeRedirect(r, getFallback(r, meta));
    }

    meta.publication_id = meta.publication_id || ref.publication_id;
    meta.token = meta.token || ref.token;
    meta.short_id = meta.short_id || shortId;

    ensureUidCookie(r);

    if (meta.type === 'pixel') {
        if (!enforceSticky(r, meta)) {
            return safeRedirect(r, getFallback(r, meta));
        }

        await trackPixelEvent(r, meta.publication_id, meta.token);
        return servePixelImage(r);
    }

    if (!isPasswordAuthorized(r, meta)) {
        return requirePasswordPage(r, meta);
    }

    if (!enforceSticky(r, meta)) {
        return safeRedirect(r, getFallback(r, meta));
    }

    if (meta.type === 'page') {
        setPageCookie(r, meta);

        var tplp = readText(templatePath(r, 'page-open.html'));
        var langp = metaLang(meta);
        var capsp = captions(langp);
        var base = cfg(r, 'uportal_base_url', 'http://localhost:8080');
        var targetUrl = '/p/' + meta.publication_id + '/' + meta.token + '/';
        var imageUrl = publicAssetUrl(r, meta);

        if (tplp === null) {
            return r.return(302, targetUrl);
        }

        var htmlp = render(tplp, {
            LANG: escAttr(langp),
            TITLE: escHtml(meta.title || capsp.pageTitle),
            DESCRIPTION: escHtml(meta.description || ''),
            IMAGE: escAttr(imageUrl),
            TARGET_URL: escAttr(targetUrl),
            CANONICAL_URL: escAttr(base + '/s/' + meta.short_id),
            OPEN_URL_JS: jsStr(signedOpenUrl(r, meta))
        });


        r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
        r.headersOut['Cache-Control'] = 'no-store';
        return r.return(200, htmlp);
    }

    if (meta.type === 'redirect') {
        var tplr = readText(templatePath(r, safeSeg(meta.template || 'redirect', 'redirect') + '.html'));
        if (tplr === null) return safeRedirect(r, getFallback(r, meta));
        var langr = metaLang(meta);
        var delay = parseInt(meta.delay || 0, 10);
        if (isNaN(delay) || delay < 0) delay = 0;

        var varsr = templateCaptionVars(langr);
        varsr.TITLE = escHtml(linkPreviewTitle(meta, captions(langr).redirectTitle));
        varsr.DESCRIPTION = escHtml(linkPreviewDescription(meta));
        varsr.IMAGE = escAttr(publicAssetUrl(r, meta));
        varsr.TARGET_URL = escAttr(meta.target_url || '');
        varsr.DELAY = String(delay);
        varsr.OPEN_URL_JS = jsStr(signedOpenUrl(r, meta));
        varsr.CLICK_URL_JS = jsStr(signedClickUrl(r, meta));
        addBrandVars(r, varsr);
        varsr.FILE_NAME = '';

        var htmlr = render(tplr, varsr);

        r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
        r.headersOut['Cache-Control'] = 'no-store';
        return r.return(200, htmlr);
    }

    if (meta.type === 'download') {
        var tpld = readText(templatePath(r, safeSeg(meta.template || 'download', 'download') + '.html'));
        if (tpld === null) return safeRedirect(r, getFallback(r, meta));
        var langd = metaLang(meta);
        var delayd = parseInt(meta.delay || 0, 10);
        if (isNaN(delayd) || delayd < 0) delayd = 0;

        var varsd = templateCaptionVars(langd);
        varsd.TITLE = escHtml(linkPreviewTitle(meta, captions(langd).downloadTitle));
        varsd.DESCRIPTION = escHtml(linkPreviewDescription(meta));
        varsd.IMAGE = escAttr(publicAssetUrl(r, meta));
        varsd.PUBLICATION_ID = escAttr(meta.publication_id);
        varsd.TOKEN = escAttr(meta.token);
        varsd.DELAY = String(delayd);
        varsd.OPEN_URL_JS = jsStr(signedOpenUrl(r, meta));
        varsd.DOWNLOAD_URL_JS = jsStr(signedDownloadUrl(r, meta));
        addBrandVars(r, varsd);
        varsd.FILE_NAME = escHtml(meta.filename || meta.file || meta.token);

        var htmld = render(tpld, varsd);

        r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
        r.headersOut['Cache-Control'] = 'no-store';
        return r.return(200, htmld);
    }

    return safeRedirect(r, getFallback(r, meta));
}

function authPassword(r) {
    var pt = extractPubToken(r.uri, /^\/api\/auth\/([^/]+)\/([^/]+)$/);
    if (!pt) return r.return(404);

    var meta = readMeta(r, pt.publication_id, pt.token);
    if (!meta || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        r.headersOut['Content-Type'] = 'application/json; charset=utf-8';
        return r.return(404, JSON.stringify({ ok: false, error: 'Link unavailable' }));
    }

    if (!hasPassword(meta)) {
        r.headersOut['Content-Type'] = 'application/json; charset=utf-8';
        return r.return(200, JSON.stringify({
            ok: true,
            redirect_to: meta.short_id ? '/s/' + meta.short_id : '/p/' + pt.publication_id + '/' + pt.token + '/'
        }));
    }

    var body = r.requestText || '';
    var password = parseBodyParam(body, 'password');
    if (!password && r.args && r.args.password) password = String(r.args.password);

    var actual = sha256hex(password);
    var expected = normalizePasswordHash(meta);

    r.headersOut['Content-Type'] = 'application/json; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';

    if (!password || actual !== expected) {
        clearPasswordCookie(r);
        return r.return(403, JSON.stringify({ ok: false, error: captions(metaLang(meta)).invalidPassword }));
    }

    setPasswordCookie(r, meta);

    var redirectTo;
    if (meta.short_id) {
        redirectTo = '/s/' + meta.short_id;
    } else if (meta.type === 'page') {
        setPageCookie(r, meta);
        redirectTo = '/p/' + pt.publication_id + '/' + pt.token + '/';
    } else if (meta.type === 'download' || meta.type === 'redirect') {
        redirectTo = '/s/' + (meta.short_id || '');
    } else {
        redirectTo = '/';
    }

    return r.return(200, JSON.stringify({ ok: true, redirect_to: redirectTo }));
}

function signDownload(r) {
    var pt = extractPubToken(r.uri, /^\/api\/sign\/([^/]+)\/([^/]+)$/);
    if (!pt) return r.return(404);

    var meta = readMeta(r, pt.publication_id, pt.token);
    if (!meta || meta.type !== 'download' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }
    if (!isPasswordAuthorized(r, meta)) {
        return r.return(403);
    }
    meta.publication_id = meta.publication_id || pt.publication_id;
    meta.token = meta.token || pt.token;
    if (!enforceSticky(r, meta)) {
        return r.return(403);
    }

    var file = safeFileSeg(meta.file, pt.token + '.bin');
    var uri = '/f/' + pt.publication_id + '/' + pt.token + '/' + file;
    var exp = Math.floor(Date.now() / 1000) + downloadTtl(meta);
    var secret = cfg(r, 'uportal_dl_salt', 'CHANGE_ME_DOWNLOAD_SALT');
    var raw = '' + exp + uri + ' ' + secret;
    var st = b64url(crypto.createHash('md5').update(raw).digest());

    r.headersOut['Content-Type'] = 'application/json; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(200, JSON.stringify({ e: exp, st: st, file: file, filename: meta.filename || file }));
}

function sendFile(r) {
    var mf = r.uri.match(/^\/f\/([^/]+)\/([^/]+)\/([A-Za-z0-9._-]{1,200})$/);
    if (!mf) return r.return(404);

    var publicationId = mf[1];
    var token = mf[2];
    var file = mf[3];

    var meta = readMeta(r, publicationId, token);
    if (!meta || meta.type !== 'download' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }
    if (!isPasswordAuthorized(r, meta)) {
        return r.return(403);
    }
    meta.publication_id = meta.publication_id || publicationId;
    meta.token = meta.token || token;
    if (!enforceSticky(r, meta)) {
        return r.return(403);
    }

    var metaFile = safeFileSeg(meta.file, token + '.bin');
    if (metaFile !== file) return r.return(404);

    var originalName = safeDownloadName(meta.filename || meta.file || file, file);
    var reqName = r.args.fn ? safeDownloadName(r.args.fn, originalName) : originalName;

    return r.internalRedirect(
        '/_uportal_file/' +
        publicationId + '/' +
        token + '/' +
        file +
        '?fn=' + encodeURIComponent(reqName)
    );
}

function pageShell(r) {
    var pt = extractPubToken(r.uri, /^\/p\/([^/]+)\/([^/]+)\/$/);
    if (!pt) return r.return(404);

    var meta = readMeta(r, pt.publication_id, pt.token);
    if (!meta || meta.type !== 'page' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }
    if (!isPasswordAuthorized(r, meta)) {
        return requirePasswordPage(r, meta);
    }
    if (!checkPageCookie(r, pt.publication_id, pt.token)) {
        return safeRedirect(r, getFallback(r, meta));
    }
    meta.publication_id = meta.publication_id || pt.publication_id;
    meta.token = meta.token || pt.token;
    if (!enforceSticky(r, meta)) {
        return safeRedirect(r, getFallback(r, meta));
    }

    var shell = readText(pageDir(r, pt.publication_id, pt.token) + '/shell.html');
    if (shell === null) shell = readText(templatePath(r, 'page-shell.html'));
    if (shell === null) return r.return(404);

    var base = cfg(r, 'uportal_base_url', 'http://localhost:8080');

    ensureUidCookie(r);

    var pageViewUrl = signedPageViewUrl(r, meta);
    var contentUrl = signedContentUrl(r, meta);

    var lang = metaLang(meta);
    var vars = templateCaptionVars(lang);
    vars.TITLE = escHtml(meta.title || captions(lang).pageTitle);
    vars.DESCRIPTION = escHtml(meta.description || '');
    vars.PUBLICATION_ID = escAttr(pt.publication_id);
    vars.TOKEN = escAttr(pt.token);
    vars.PAGE_VIEW_URL_JS = jsStr(pageViewUrl);
    vars.CONTENT_URL_JS = jsStr(contentUrl);
    vars.BASE_URL_JS = jsStr(base);
    vars.STYLE_URL = escAttr('/assets/' + pt.publication_id + '/' + pt.token + '/style.css');

    var html = render(shell, vars);

    r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(200, html);
}

function pageContent(r) {
    var pt = extractPubToken(r.uri, /^\/api\/page-content\/([^/]+)\/([^/]+)$/);
    if (!pt) return r.return(404);

    var meta = readMeta(r, pt.publication_id, pt.token);
    if (!meta || meta.type !== 'page' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }
    if (!isPasswordAuthorized(r, meta)) return r.return(403);
    if (!checkPageCookie(r, pt.publication_id, pt.token)) return r.return(403);
    meta.publication_id = meta.publication_id || pt.publication_id;
    meta.token = meta.token || pt.token;
    if (!enforceSticky(r, meta)) return r.return(403);

    var html = readText(pageDir(r, pt.publication_id, pt.token) + '/content.html');
    if (html === null) return r.return(404);

    r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(200, html);
}

function pageAsset(r) {
    var m = r.uri.match(/^\/assets\/([^/]+)\/([^/]+)\/(.+)$/);
    if (!m) return r.return(404);

    var publicationId = m[1];
    var token = m[2];
    var rel = m[3];

    var meta = readMeta(r, publicationId, token);
    if (!meta || meta.type !== 'page' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }
    if (!isPasswordAuthorized(r, meta)) return r.return(403);
    if (!checkPageCookie(r, publicationId, token)) return r.return(403);
    if (rel.indexOf('..') >= 0) return r.return(403);
    meta.publication_id = meta.publication_id || publicationId;
    meta.token = meta.token || token;
    if (!enforceSticky(r, meta)) return r.return(403);

    return r.internalRedirect('/_uportal_page_asset/' + publicationId + '/' + token + '/' + rel);
}

function publicAsset(r) {
    var m = r.uri.match(/^\/assets-public\/([^/]+)\/([^/]+)\/([^/]+)$/);
    if (!m) return r.return(404);

    var publicationId = m[1];
    var token = m[2];
    var rel = safeSeg(m[3], 'x');

    var meta = readMeta(r, publicationId, token);
    if (!meta || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }

    var bin = readBin(payloadDir(r, publicationId, token) + '/' + rel);
    if (bin === null) {
        bin = readBin(inboxDir(r, publicationId, token) + '/' + rel);
    }
    if (bin === null) return r.return(404);

    r.headersOut['Content-Type'] = publicAssetContentType(rel, bin);
    r.headersOut['Cache-Control'] = 'public, max-age=3600';
    r.return(200, bin);
}

function pixel(r) {
    var pt = extractPubToken(r.uri, /^\/o\/([^/]+)\/([^/]+)\.(gif|png)$/);
    if (!pt) return r.return(404);

    var meta = readMeta(r, pt.publication_id, pt.token);
    if (!meta || meta.type !== 'pixel' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }

    meta.publication_id = meta.publication_id || pt.publication_id;
    meta.token = meta.token || pt.token;

    ensureUidCookie(r);
    if (!enforceSticky(r, meta)) return r.return(404);

    return servePixelImage(r);
}

function servePixelImage(r) {
    var bin = readBin(cfg(r, 'uportal_pixel_path', '/data/files/uportal/pixel/1x1.gif'));
    if (bin === null) return r.return(404);

    r.headersOut['Content-Type'] = 'image/gif';
    r.headersOut['Cache-Control'] = 'no-store';
    return r.return(200, bin);
}

function pixelAuth(r) {
    var publicationId = r.variables.track_pub || '';
    var token = r.variables.track_token || '';

    if (!publicationId || !token) {
        return r.return(404);
    }

    var meta = readMeta(r, publicationId, token);
    if (!meta || meta.type !== 'pixel' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }

    return r.return(204);
}

async function pixelGate(r) {
    var pt = extractPubToken(r.uri, /^\/o\/([^/]+)\/([^/]+)\.(gif|png)$/);
    if (!pt) return r.return(404);

    var meta = readMeta(r, pt.publication_id, pt.token);
    if (!meta || meta.type !== 'pixel' || !isActive(meta) || !isFresh(meta) || !hasClicks(meta)) {
        return r.return(404);
    }

    meta.publication_id = meta.publication_id || pt.publication_id;
    meta.token = meta.token || pt.token;

    ensureUidCookie(r);
    if (!enforceSticky(r, meta)) return r.return(404);

    await trackPixelEvent(r, pt.publication_id, pt.token);

    return servePixelImage(r);
}

function fallback(r) {
    var tpl = readText(templatePath(r, 'link-fallback.html'));
    var vars = templateCaptionVars(requestLang(r));
    addBrandVars(r, vars);
    var html = tpl === null ? null : render(tpl, vars);
    if (html === null) html = '<!doctype html><html><body><h1>Link unavailable</h1></body></html>';
    r.headersOut['Content-Type'] = 'text/html; charset=utf-8';
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(200, html);
}

export default {
    dispatchShort,
    authPassword,
    signDownload,
    sendFile,
    pageShell,
    pageContent,
    pageAsset,
    publicAsset,
    pixel,
    pixelAuth,
    pixelGate,
    fallback
};
