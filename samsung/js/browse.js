// Browse rules for long lists (the Mac design lock 2a + 3b, ported to the TV): clean labels, families,
// services, the hide rule. Input rows = library.json entries [id, raw name, count, lang, art].
var Browse = (function () {
    'use strict';
    var MIN_TITLES = 20;                       // a list under this many titles is a "small list"
    var JUNK = /CAM|PRE-RELEASE/;
    var ACR = {}; 'UHD 3D HD FHD HEVC UK US TV HBO BET NBC CBS ABC FX AMC MGM DC SF PPV UFC NBA NFL MLB NHL ESPN DAZN BBC ITV VIP RTL TNT MLS PBS F1 NCAA WNBA MXGP PDC GAA PSF NFHS B1G BTN MILB ITV WSL'.split(' ').forEach(function (a) { ACR[a] = 1; ACR['4K'] = 1; });
    var OVR = {
        'TOP IMDB/OSCAR MOVIES': 'IMDb top & Oscar winners', 'FRENCH MOVIES / ENG SUB': 'French, English subtitles',
        'ITALIAN MOVIES / ENG SUB': 'Italian, English subtitles', 'NEW RELEASED': 'New releases',
        '4K DOCUMENTARY/MUSIC/ STAND-UP': 'Documentary, music & stand-up', 'SCIENCE FICTION/FANTASTY': 'Sci-fi & fantasy',
        'MOVIES 2018-2021': '2018 to 2021', 'SCIENCE/FICTION/FANTASTIQUE': 'Science-fiction & fantastique',
        'DE NOËL': 'Films de Noël', 'FILM 1980-1999': '1980 à 1999', 'ART MARTIAUX': 'Arts martiaux',
        '4K MOVIES': 'All 4K films', 'UK MOVIES': 'British films', 'APPLE+ MOVIES': 'Apple TV+ films',
        'APPLE+ KIDS': 'Apple TV+ Kids', 'PRIME+': 'Prime Video', 'PRIME +': 'Prime Video', 'MyCANAL': 'myCanal',
        'NETFLIX': 'Netflix', 'DISNEY+': 'Disney+', 'CLASSIC MOVIES COLLECTION': 'Classic films',
        'ACTORS & DIRECTORS': 'Actors & directors', 'FILMOGRAPHIE LOUIS DE FUNES': 'Louis de Funès',
        'FILMS UHD': 'Films UHD', 'FILMS 4K/3D': 'Films 4K & 3D', 'JEUNESSE 4K/3D': 'Jeunesse 4K & 3D',
        'BET/ALLBLK MOVIES': 'BET & ALLBLK', 'HALLMARK MOVIES': 'Hallmark', 'WORLDCUP 2022': 'World Cup 2022',
        'RATED R': 'Rated R', 'HORREUR/EPOUVANTE': 'Horreur & épouvante', 'TV MOVIES': 'TV films',
        'ADVENTURE MOVIES': 'Adventure', 'CHRISTMAS MOVIES': 'Christmas', 'FOREIGN MOVIES': 'World cinema',
        'PIXAR MOVIES': 'Pixar', 'COMÉDIE/DRAME': 'Comédie & drame', 'HBO MAX': 'HBO Max', 'HBO FILMS': 'HBO films',
        'APPLE TV+': 'Apple TV+', 'PARAMOUNT+': 'Paramount+', 'ZIGGO GO': 'Ziggo GO', 'THEATRE ET SPECTACLE': 'Théâtre & spectacle',
        'BBCIPLAYER SERIES': 'BBC iPlayer series', 'ACTEURS FRANÇAIS': 'Acteurs français', 'MAFIA GANGSTER': 'Mafia & gangster',
        'NETFLIX JEUNESSE FAMILLE': 'Netflix jeunesse & famille', 'CHILDREN/FAMILY': 'Children & family',
        'STAND-UP COMEDY': 'Stand-up comedy', 'DRAMA/COMEDY': 'Drama & comedy', 'DRAMA/ROMANCE': 'Drama & romance', 'DRAMA/CRIME': 'Drama & crime',
        'ACTION/THRILLER': 'Action & thriller', 'HORROR/THRILLER': 'Horror & thriller', 'MUSIC/CONCERTS': 'Music & concerts',
        'BIBLICAL/RELIGIOUS': 'Biblical & religious', 'GANGSTER & MAFIA': 'Gangster & mafia', 'CLASSIC CARTOONS': 'Classic cartoons',
        '4K CHILDREN': '4K children', '4K CLASSIC MOVIES': '4K classics', '4K MAFIA & GANGSTER': '4K mafia & gangster', '4K NETFLIX MOVIES': '4K Netflix',
        'MyCANAL/TF1+': 'myCanal & TF1+', 'ANCIENNE': 'Séries anciennes', 'EMISSION | TÉLÉ-RÉALITÉ': 'Émissions & télé-réalité',
        'NETFLIX CRIME | MYSTERE': 'Netflix crime & mystère', 'BET/ALLBLK SERIES': 'BET & ALLBLK series', 'AMAZON PRIME': 'Prime Video',
        'TURKISH SERIES SUB': 'Turkish series, subtitled', 'PRE-RELEASES/SD CAM': 'Pre-releases (cam copies)'
    };
    var BRAND = {}; 'NETFLIX DISNEY DISNEY+ APPLE PRIME HULU FOX FOX+ MARVEL PIXAR HALLMARK PEACOCK STARZ SHOWTIME PARAMOUNT+ ASIA ENGLISH FRENCH TURKISH ASIAN ITALIAN SKY STORE DISCOVERY DISCOVERY+ NOW TUBI PLUTO CHRISTMAS NOËL AMAZON HOLLYWOOD ALLBLK SAGA PLAY GO VIDEO'.split(' ').forEach(function (b) { BRAND[b] = 1; });
    function word(w, i) { if (ACR[w.replace(/[+:]/g, '')]) return w; return (i === 0 || BRAND[w]) ? w.charAt(0) + w.slice(1).toLowerCase() : w.toLowerCase(); }
    function clean(raw) {
        if (OVR[raw]) return OVR[raw];
        var s = raw.replace(/\s*\/\s*/g, ' & ').replace(/\s*\|\s*/g, ' & ').replace(/APPLE\+/g, 'APPLE TV+').replace(/\s+(MOVIES|FILMS|SERIES)$/, '').replace(/\s+NETWORK$/, '');
        s = s.split(/\s+/).map(word).join(' ').replace(/\bAnd\b/g, '&').replace(/ \+$/, '+').replace(/\s*&\s*$/, '');
        return s ? s.charAt(0).toUpperCase() + s.slice(1) : raw;
    }
    // [name, test, public logo (github.com/tv-logo/tv-logos) or null, dark logo needs a light plate]
    var LOGO = 'https://raw.githubusercontent.com/tv-logo/tv-logos/main/';
    var SERVICES = [['Netflix', /NETFLIX/, 'misc/media/netflix.png'], ['Disney+', /DISNEY/, 'misc/media/disney-plus.png'],
        ['Apple TV+', /APPLE/, 'misc/media/apple-tv-plus.png'], ['Prime Video', /PRIME/, 'misc/media/prime-video.png'],
        ['HBO Max', /HBO/, 'misc/media/hbo-max.png'], ['Hulu', /HULU/, 'misc/media/hulu.png'], ['Paramount+', /PARAMOUNT|CBS/, 'misc/media/paramount-plus.png'],
        ['myCanal', /CANAL|TF1/i, 'countries/france/canal-plus-fr.png'], ['Peacock', /PEACOCK|NBC/, 'misc/media/peacock.png'],
        ['Showtime & Starz', /SHOWTIME|STARZ/, 'countries/united-states/showtime-us.png', 1], ['AMC+', /AMC/, 'misc/vod/amc-plus-vod-us.png'],
        ['Fox', /FOX\+/, null], ['Ziggo GO', /ZIGGO/, null], ['BET & ALLBLK', /BET\/ALLBLK/, 'countries/united-states/bet-us.png'],
        ['Hallmark', /HALLMARK/, 'countries/united-states/hallmark-channel-us.png']];
    var FAM = [
        ['svc', 'Streaming services', null],
        ['genre', 'Genres', null],
        ['4k', '4K & UHD', /4K|UHD|3D/],
        ['kids', 'Kids & family', /KIDS|CHILDREN|FAMILY|JEUNESSE|CARTOON|ANIMATION|PIXAR|ENFANT/],
        ['world', 'World & languages', /FRENCH|ITALIAN|UK MOVIES|FOREIGN|ASIATIQUE|TURKISH|ACTEURS FRAN|ENGLISH SERIES|UK SERIES|ASIAN SERIES/],
        ['coll', 'Collections & eras', /TOP|NEW|20\d\d|19\d\d|CLASSI|COLLECTION|ACTORS|SAGA|CHRISTMAS|NOËL|MARVEL|FUNES|WORLDCUP|RATED|TV MOVIES|LATEST|GOLDEN/]
    ];
    // card tint by family: the TV cannot read a picture's colour across origins, so the family sets it
    var TINT = { svc: [58, 61, 72], genre: [52, 44, 78], '4k': [20, 52, 84], kids: [94, 58, 20], world: [22, 72, 62], coll: [88, 30, 46], small: [40, 40, 46] };
    function service(raw) { for (var i = 0; i < SERVICES.length; i++) if (SERVICES[i][1].test(raw)) return SERVICES[i]; return null; }
    function family(raw) {
        if (service(raw)) return 'svc';
        for (var i = 2; i < FAM.length; i++) if (FAM[i][2].test(raw)) return FAM[i][0];
        return 'genre';
    }
    // rows = library.json entries; lang = 'EN' | 'FR' | '' (all). Returns shelves [{ key, title, cards: [...] }].
    function shelves(rows, lang) {
        var cats = rows.map(function (r) {
            return { id: r[0], raw: r[1], n: r[2], lang: r[3] || '', art: r[4] || [], label: clean(r[1]), fam: family(r[1]), svc: service(r[1]),
                small: r[2] < MIN_TITLES || JUNK.test(r[1]) };
        }).filter(function (c) { return !lang || !c.lang || c.lang === lang || c.lang === 'MULTI'; });
        var byFam = {}, out = [];
        cats.forEach(function (c) { var k = c.small ? 'small' : c.fam; (byFam[k] = byFam[k] || []).push(c); });
        // streaming services: one card per service holding its lists; a service with one list is that list
        if (byFam.svc) {
            var svcs = {};
            byFam.svc.forEach(function (c) { var s = c.svc[0]; (svcs[s] = svcs[s] || { name: s, logo: c.svc[2] ? LOGO + c.svc[2] : null, dark: !!c.svc[3], cats: [] }).cats.push(c); });
            var cards = [];
            for (var s in svcs) {
                var g = svcs[s]; g.cats.sort(function (a, b) { return b.n - a.n; });
                cards.push({ kind: 'service', name: g.name, logo: g.logo, dark: g.dark, n: g.cats.length, unit: 'list', cats: g.cats, art: g.cats[0].art, tint: TINT.svc });
            }
            cards.sort(function (a, b) { return b.n - a.n; });
            out.push({ key: 'svc', title: 'Streaming services', cards: cards });
        }
        for (var i = 1; i < FAM.length; i++) {
            var f = FAM[i], list = byFam[f[0]]; if (!list || !list.length) continue;
            list.sort(function (a, b) { return b.n - a.n; });
            out.push({ key: f[0], title: f[1], cards: list.map(function (c) { return { kind: 'list', name: c.label, n: c.n, cat: c, art: c.art, tint: TINT[f[0]] }; }) });
        }
        if (byFam.small) out.push({ key: 'small', title: 'Small lists', cards: byFam.small.map(function (c) { return { kind: 'list', name: c.label, n: c.n, cat: c, art: c.art, tint: TINT.small, muted: true }; }) });
        return out;
    }
    function fmt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }

    // Live categories, the same rules for the guide's category column. Input d = {g: [raw group names],
    // byGroup, lazy}. Returns sections [{ key, title, items: [{ label, gi: [group indexes], n }] }]: quality
    // variants of one group merged under one label (FRANCE 4K / FHD / HD / LQ = France), groups under
    // MIN_CHANNELS channels hidden once their counts are known, events and pay-per-view last.
    var MIN_CHANNELS = 8;
    var QUAL = /\s+(HEVC|FHD|UHD|HD|LQ|SD|4K)$/;
    var LIVE_OVR = {
        'TV': 'TV channels', 'BBCI': 'BBC iPlayer', 'MC VIDEO': 'Music videos', 'CW/MY NETWORK': 'CW & MyNetworkTV', 'FLO NETWORK': 'FloSports',
        'EPL PREMIER LEAGUE': 'Premier League', 'EPL PREMIER LEAGUE+ PPV': 'Premier League+ PPV', 'ESPN PLUS': 'ESPN+', 'ESPN PLAY': 'ESPN Play', 'ESPN+ PPV VIP': 'ESPN+ PPV',
        'DAZN PPV VIP': 'DAZN PPV', 'DAZN PPV VIP BK': 'DAZN PPV (backup)', '24/7 MOVIES & SERIES': '24/7 films & series', '24/7 BEIN CINEMA': '24/7 beIN Cinema',
        'MAX ESPN /': 'Max & ESPN', 'B/R MAX SPORTS PPV': 'B/R Sports on Max PPV', 'NOW TV': 'NOW', 'AMAZON PRIME +': 'Prime Video', 'PRIME': 'Prime Video', 'PRIME VIDEO SERIES': 'Prime Video series',
        'NETFLIX ON AIR': 'Netflix', 'NETFLIX ORIGINAL': 'Netflix originals', 'APPLE TV+ SERIES': 'Apple TV+ series', 'BBCIPLAYER SERIES': 'BBC iPlayer series', 'SKYMIX SERIES': 'Sky series', 'SKYMIX DOCS': 'Sky documentaries',
        'REALITY SHOW TV': 'Reality shows', 'CUP GAMES & INTERNATIONAL': 'Cups & internationals', 'FORMULA 1 + MOTOGP': 'Formula 1 & MotoGP', 'SKY SPORTS RED BUTTON': 'Sky Sports Red Button', 'SKY SPORT+ VIP': 'Sky Sports+',
        'ITV X VIP': 'ITVX', 'FA PLAYER': 'FA Player', 'DISCOVERY +': 'Discovery+', 'VIX+ DEPORTES': 'ViX+ Deportes', 'CINE+ PREMIUM': 'Ciné+', "L'EQUIPE LIVE": "L'Équipe live", 'LIGUE 1+': 'Ligue 1+', 'LIGUE 1+ VIP': 'Ligue 1+ VIP',
        'EUROSPORTS 360': 'Eurosport 360', 'EUROSPORT XTRA': 'Eurosport Xtra', 'CANAL+ LIVE': 'Canal+ live', 'CANAL PLAY': 'Canal Play', 'PREMIUM PLAY': 'Premium Play', 'LUXPLAY VIP': 'LuxPlay', 'PLAY TV': 'Play TV',
        'FRANCE': 'France', 'FRANCE VIP': 'France VIP', 'FRANCE SPORT VIP': 'France sport', 'BELGIUM VIP': 'Belgium VIP', 'WALLONIË': 'Wallonie', 'DOCUMENTAIRE': 'Documentaires', 'ENFANTS': 'Enfants', 'MOVIES': 'Films',
        'CINEMANIA HOLLYWOOD': 'Cinemania films', 'CINEMANIA TV SHOWS': 'Cinemania series', 'BIBLICAL/RELIGIOUS': 'Faith', 'SPECTRUM NETWORK': 'Spectrum', 'NEWS NETWORK': 'News', 'TENNIS CHANNEL PLUS': 'Tennis Channel+',
        'HBO MAX NETWORK': 'HBO Max', 'DISNEY+ NETWORK': 'Disney+', 'NFL NETWORK HULU': 'NFL Network', 'NBA NETWORK VIP': 'NBA TV', 'MLS NETWORK': 'MLS', 'TELEMUNDO NETWORK': 'Telemundo',
        'UFC/BOXING PPV': 'UFC & boxing PPV', 'PAY PER VIEW PPV': 'Pay-per-view', 'PPV EVENTS': 'PPV events', 'MLS PPV VIP': 'MLS PPV', 'PARAMOUNT+ PPV VIP': 'Paramount+ PPV', 'MAX PPV VIP': 'Max PPV',
        'DISNEY+ PPV VIP': 'Disney+ PPV', 'DISNEY+ PPV ⱽ': 'Disney+ PPV', 'TNT SPORTS EVENT': 'TNT Sports events', 'NFHS PPV': 'NFHS PPV', 'PSF PPV': 'PSF PPV', 'PDC BOARD PPV': 'PDC darts PPV', 'VIDIO EPL PPV': 'Vidio Premier League PPV',
        'MILB TV PPV': 'MiLB PPV', 'LEAGUE ONE': 'League One', 'LEAGUE TWO': 'League Two', 'NATIONAL LEAGUE': 'National League', 'LA LIGA TEAM PPV': 'La Liga team PPV', 'SERIE A TEAM PPV': 'Serie A team PPV',
        'VOLLEY BALL WORLD PPV': 'Volleyball World PPV', 'DIRTVISION PPV': 'DirtVision PPV', 'HUB PREMIER PPV': 'Hub Premier PPV', 'ULTIMATE POOL PPV': 'Ultimate Pool PPV', 'MONOMAX PPV': 'MonoMax PPV', 'BBC STREAM PPV': 'BBC Stream PPV',
        'CYMRU FOOTBALL PPV': 'Cymru Football PPV', 'FLO RACING PPV': 'FloRacing PPV', 'FLO COLLEGE PPV': 'FloCollege PPV', 'SCOTTISH FOOTBALL': 'Scottish Football', 'WORLD SPORTS': 'World Sports', 'NCAAF PACKAGE': 'NCAA Football package', 'NCAAB PACKAGE': 'NCAA Basketball package', 'B1G+ PPV': 'B1G+ PPV', 'BTN+ PPV': 'BTN+ PPV', 'GAA GO PPV': 'GAAGO PPV', 'ULSTER GAA PPV': 'Ulster GAA PPV', 'MXGP PPV': 'MXGP PPV', 'STAN PPV': 'Stan Sport PPV', 'FITE TV PPV': 'FITE PPV'
    };
    var LIVE_FAM = [
        ['ppv', 'Events & pay-per-view', /PPV|PAY PER VIEW|EVENT|PACKAGE/],
        ['sport', 'Sport', /SPORT|EPL|LEAGUE|FOOTBALL|FORMULA|MOTOGP|EUROSPORT|DAZN|LIGUE|NBA|NFL|NHL|MLB|MLS|WNBA|NCAA|TENNIS|FLO |GAA|RUGBY|CUP GAMES|EQUIPE|BEIN(?! CINEMA)|DEPORTES|ESPN|FA PLAYER|CHAMPIONSHIP|RED BUTTON|RACING|MILB/],
        ['kids', 'Kids', /KIDS|KINDEREN|ENFANTS|CARTOON/],
        ['docs', 'Documentary & music', /DOCUMENT|MUSIC|MC VIDEO|DOCS|DISCOVERY|BIBLICAL|RELIGIOUS/],
        ['film', 'Films & series', /MOVIES|CINE|24\/7|SKY STORE|SERIES|ORIGINAL|REALITY|CINEMANIA|HOLLYWOOD|TV SHOWS/],
        ['svc', 'Streaming services', /NOW TV|PRIME|TUBI|PLUTO|PARAMOUNT|PEACOCK|HULU|DISNEY|NETFLIX|HBO|ITV X|CANAL|PLAY|APPLE|VIX|TELENET|TELESAT/],
        ['tv', 'Channels', null]
    ];
    var LIVE_ORDER = ['tv', 'film', 'sport', 'kids', 'docs', 'svc', 'ppv'];
    function liveLabel(raw) { var s = raw.replace(QUAL, ''); return LIVE_OVR[s] || clean(s); }
    function liveFamily(raw) { for (var i = 0; i < LIVE_FAM.length - 1; i++) if (LIVE_FAM[i][2].test(raw)) return LIVE_FAM[i][0]; return 'tv'; }
    function live(d) {
        var byLabel = {}, items = [];
        for (var gi = 0; gi < d.g.length; gi++) {
            var raw = d.g[gi], label = liveLabel(raw), it = byLabel[label];
            if (!it) { it = byLabel[label] = { label: label, gi: [], n: 0, fam: liveFamily(raw) }; items.push(it); }
            it.gi.push(gi); it.n += d.byGroup && d.byGroup[gi] ? d.byGroup[gi].length : 0;
        }
        var out = [], byFam = {};
        items.forEach(function (it) { if (!d.lazy && it.n < MIN_CHANNELS) return; (byFam[it.fam] = byFam[it.fam] || []).push(it); });
        LIVE_ORDER.forEach(function (k) {
            if (!byFam[k]) return;
            for (var i = 0; i < LIVE_FAM.length; i++) if (LIVE_FAM[i][0] === k) out.push({ key: k, title: LIVE_FAM[i][1], items: byFam[k] });
        });
        return out;
    }
    return { shelves: shelves, live: live, clean: clean, fmt: fmt };
})();
