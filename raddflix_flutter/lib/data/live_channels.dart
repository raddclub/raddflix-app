// lib/data/live_channels.dart
//
// Hardcoded Live TV channel catalogue — 86 channels.
// All stream URLs are Jazz-CDN m3u8 HLS streams (tamashaweb CDN).
// Logo URLs: tamashaweb CDN primary, Wikipedia/upload fallback.

class LiveChannel {
  final String id;
  final String name;
  final String genre;
  final String cat; // 'sports' | 'religious' | 'news' | 'entertainment' | 'kids' | 'movies' | 'docs'
  final String logoUrl;
  final String streamUrl;

  const LiveChannel({
    required this.id,
    required this.name,
    required this.genre,
    required this.cat,
    required this.logoUrl,
    required this.streamUrl,
  });
}

class LiveCategory {
  final String id;
  final String label;
  const LiveCategory(this.id, this.label);
}

const kLiveCategories = <LiveCategory>[
  LiveCategory('all',           'All'),
  LiveCategory('sports',        '🏏 Sports'),
  LiveCategory('religious',     '🕌 Islamic'),
  LiveCategory('news',          '📰 News'),
  LiveCategory('entertainment', '🎭 Drama'),
  LiveCategory('kids',          '🧸 Kids'),
  LiveCategory('movies',        '🎬 Movies'),
  LiveCategory('docs',          '🌿 Lifestyle'),
];

const kAllLiveChannels = <LiveChannel>[
  // ── SPORTS ──────────────────────────────────────────────────────────────
  LiveChannel(
    id: 'pak-ban', name: 'PAK v BAN', genre: '🏏 Sports', cat: 'sports',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2024/01/ptv-sports.png',
    streamUrl: 'https://cdn02lhr-n.tamashaweb.com:8087/jazzauth/PAKvsBANTS-2026-ABR/playlist.m3u8',
  ),
  LiveChannel(
    id: 'ten-sports', name: 'Ten Sports', genre: '🏏 Sports', cat: 'sports',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ten-sports.png',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/YlUHeDQb7a/157-3H/playlist.m3u8',
  ),
  LiveChannel(
    id: 'ptv-sports', name: 'PTV Sports', genre: '🏏 Sports', cat: 'sports',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2024/01/ptv-sports.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/189H/chunks.m3u8',
  ),
  LiveChannel(
    id: 'eurosport', name: 'Eurosport', genre: '⚽ Sports', cat: 'sports',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/eurosport.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/Eurosport-abr/playlist.m3u8',
  ),

  // ── ISLAMIC ─────────────────────────────────────────────────────────────
  LiveChannel(
    id: 'saudi-makkah', name: 'Saudi Makkah', genre: '🕌 Islamic', cat: 'religious',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Saudi_Arabia_TV.svg/200px-Saudi_Arabia_TV.svg.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/Saudimakkah(nw)-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'saudi-madinah', name: 'Saudi Madinah', genre: '🕌 Islamic', cat: 'religious',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Saudi_Arabia_TV.svg/200px-Saudi_Arabia_TV.svg.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/SaudiSunnah(NW)-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'madani-ch', name: 'Madani Channel', genre: '🕌 Islamic', cat: 'religious',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/madani-channel.png',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/jazzauth/Madni-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'paigham-tv', name: 'Paigham TV', genre: '🕌 Islamic', cat: 'religious',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/paigham-tv.png',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/PaighamTV-abr/playlist.m3u8',
  ),

  // ── NEWS ────────────────────────────────────────────────────────────────
  LiveChannel(
    id: 'geo-news', name: 'Geo News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/geo-news.png',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/jazzauth/vsat-geonews-abr/playlist_dvr_timeshift-0-3600.m3u8',
  ),
  LiveChannel(
    id: 'ary-news', name: 'ARY News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ary-news.png',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/jazzauth/vsat-arynews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'hum-news', name: 'Hum News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/hum-news.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/humnews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'express-news', name: 'Express News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/express-news.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/expressnews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'samaa-tv', name: 'Samaa TV', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/samaa-tv.png',
    streamUrl: 'https://cdn05khi.tamashaweb.com:8087/jazzauth/samaaTV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bol-news', name: 'BOL News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/bol-news.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/BolNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'gnn', name: 'GNN', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/gnn.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/GNN-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'dawn-news', name: 'Dawn News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/dawn-news.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/DawnNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'suno-news', name: 'Suno News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/suno-news.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/Suno_News-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'neo-news', name: 'Neo News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/neo-news.png',
    streamUrl: 'https://cdn24lhr.tamashaweb.com:8087/jazzauth/NeoNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'sun-news', name: 'Sun News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/thumb/6/6d/Sun_News_Pakistan_Logo.png/200px-Sun_News_Pakistan_Logo.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/SUN-NEWS-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'ptv-news', name: 'PTV News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ptv-news.png',
    streamUrl: 'https://cdn05khi.tamashaweb.com:8087/jazzauth/PTVNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'abn-news', name: 'ABN News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/b/b8/Abn_news_logo.jpg',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/ABNnews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'gtv-news', name: 'GTV News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/a/ad/GTV_News.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/GTVNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'aaj-news', name: 'Aaj News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/aaj-news.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/AajNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: '365-news', name: '365 News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/8/87/365_News_Logo.jpg',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/365News-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'tamasha-news', name: 'Tamasha News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/tamasha.png',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/jazzauth/Tamasha-News-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'digital-pak', name: 'Digital Pak', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/f/f6/Digital_Pakistan_TV.jpg',
    streamUrl: 'https://cdn23lhr.tamashaweb.com:8087/jazzauth/Digital-pak-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'aljazeera', name: 'Al Jazeera', genre: '🌍 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/aljazeera.png',
    streamUrl: 'https://cdn05khi.tamashaweb.com:8087/jazzauth/AL-Jazeera-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'cnn', name: 'CNN', genre: '🌍 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/cnn.png',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/Livecnn-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'dw-news', name: 'DW News', genre: '🌍 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/dw-news.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/DWNews-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'cgtn-hd', name: 'CGTN HD', genre: '🌍 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/CGTN_logo.svg/200px-CGTN_logo.svg.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/CgtnHD-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: '24-news', name: '24 News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/24-news.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/24News-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'public-tv', name: 'Public TV', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/0/09/Public_News_Pakistan.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/PublicTV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'news-one', name: 'News One', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/2/24/Newsone_logo.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/NewsOne-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'abb-tak', name: 'Abb Tak', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/6/68/Abb_Tak_logo.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/abbtak-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'pnn', name: 'PNN (Aik News)', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/7/71/Aik_News_Logo.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/PNN-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bbc-news', name: 'BBC News', genre: '🌍 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/bbc-news.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/BBCNEWS-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'trt-world', name: 'TRT World', genre: '🌍 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/trt-world.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/153H/playlist.m3u8',
  ),
  LiveChannel(
    id: 'dunya-news', name: 'Dunya News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/dunya-news.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/113M/playlist.m3u8',
  ),
  LiveChannel(
    id: 'awaz-news', name: 'Awaz News', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/b/b2/Awaz_TV_logo.jpg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/120M/playlist.m3u8',
  ),
  LiveChannel(
    id: 'capital-tv', name: 'Capital TV', genre: '📰 News', cat: 'news',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/a/ae/Capital_TV_Pakistan.jpg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/111M/playlist.m3u8',
  ),

  // ── ENTERTAINMENT ────────────────────────────────────────────────────────
  LiveChannel(
    id: 'ary-digital', name: 'ARY Digital', genre: '🎭 Drama', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ary-digital.png',
    streamUrl: 'https://cdn07lhr.tamashaweb.com:8087/jazzauth/vsat-arydigital-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'hum-tv', name: 'Hum TV', genre: '🎭 Drama', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/hum-tv.png',
    streamUrl: 'https://cdn23lhr.tamashaweb.com:8087/jazzauth/humTV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'geo-ent', name: 'Geo Entertainment', genre: '🎭 Drama', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/geo-entertainment.png',
    streamUrl: 'https://cdn24lhr.tamashaweb.com:8087/jazzauth/GeoEntertainment-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'green-ent', name: 'Green Entertainment', genre: '🎭 Drama', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/green-entertainment.png',
    streamUrl: 'https://cdn23lhr.tamashaweb.com:8087/jazzauth/Green_Entertainment-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'ptv-home', name: 'PTV Home', genre: '🏠 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ptv-home.png',
    streamUrl: 'https://cdn23lhr.tamashaweb.com:8087/jazzauth/PTVHome-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'express-ent', name: 'Express Entertainment', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/express-entertainment.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/ExpressEntertainment-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'set-hd', name: 'SET HD', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/set-hd.png',
    streamUrl: 'https://cdn24lhr.tamashaweb.com:8087/jazzauth/SetEntertainment-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bol-ent', name: 'BOL Entertainment', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/bol-entertainment.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/jazzauth/BolEntertainment-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'ary-zindagi', name: 'ARY Zindagi', genre: '🎭 Drama', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ary-zindagi.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/ARYzindagi-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'hum-sitaray', name: 'Hum Sitaray', genre: '⭐ Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/hum-sitaray.png',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/HumSitaray-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'aan-tv', name: 'AAN TV', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/2/2b/Aan_TV_Logo.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/AAN-TV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'sab-tv', name: 'Sab TV', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/sab-tv.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/SabTV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'tv-one', name: 'TV One', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/tv-one.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/TVOne-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'tv-today', name: 'TV Today', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/7/77/TV_Today_Pakistan_logo.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/jazzauth/TvToday-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'aurlife', name: 'AurLife', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/e/ef/AurLife_TV_Logo.jpg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/AurLife-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'ltn-family', name: 'LTN Family', genre: '👨‍👩‍👧 Family', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/0/07/LTN_Family_logo.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/LTNFamily-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'aplus', name: 'A-Plus', genre: '🎭 Drama', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/aplus.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/Aplus-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'aaj-ent', name: 'Aaj Entertainment', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/aaj-entertainment.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/AajEntertainment-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'see-tv', name: 'See TV', genre: '👁️ Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/1/16/See_TV_logo.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/seeTV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'urooj-tv', name: 'Urooj TV', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/5/59/Urooj_TV_Logo.jpg',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/YlUHeDQb7a/117M/playlist.m3u8',
  ),
  LiveChannel(
    id: 'atv', name: 'ATV', genre: '📺 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/7/72/ATV_Pakistan.jpg',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/YlUHeDQb7a/123M/chunks.m3u8',
  ),
  LiveChannel(
    id: 'bbc-first', name: 'BBC First', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/6/66/BBC_First_logo.svg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/BBC-First-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bbc-brit', name: 'BBC Brit', genre: '🎭 Entertainment', cat: 'entertainment',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/b/b9/BBC_Brit_logo.svg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/BBC-Brit-abr/playlist.m3u8',
  ),

  // ── KIDS ────────────────────────────────────────────────────────────────
  LiveChannel(
    id: 'cartoon-network', name: 'Cartoon Network', genre: '🧸 Kids', cat: 'kids',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/cartoon-network.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/cartoonnetwork-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'minimax', name: 'Minimax', genre: '🚀 Kids', cat: 'kids',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/08/Minimax_logo.svg/200px-Minimax_logo.svg.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/Minimax-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'baby-tv', name: 'Baby TV', genre: '🍼 Kids', cat: 'kids',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b6/BabyTV_logo.svg/200px-BabyTV_logo.svg.png',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/BabyTV-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bbc-cbeebies', name: 'BBC CBeebies', genre: '🧸 Kids', cat: 'kids',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/7/74/CBeebies_2022.svg/200px-CBeebies_2022.svg.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/BBC-Cbeebies-abr/playlist.m3u8',
  ),

  // ── MOVIES & MUSIC ──────────────────────────────────────────────────────
  LiveChannel(
    id: 'filmax', name: 'Filmax', genre: '🎞️ Movies', cat: 'movies',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/4/4e/Filmax_logo.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/Filmax-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'movie-one', name: 'Movie One', genre: '🍿 Movies', cat: 'movies',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/2/22/Movie_One_Pakistan.jpg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/MovieOne-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: '8xm', name: '8xM Music', genre: '🎵 Music', cat: 'movies',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/ary-musik.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/8xm-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'jalwa-tv', name: 'Jalwa TV', genre: '💃 Music', cat: 'movies',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/d/d3/Jalwa_TV_logo.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/jalwa-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'play-tv', name: 'Play TV', genre: '🎶 Music', cat: 'movies',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/c/c3/Play_Entertainment_TV.jpg',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/play-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'srf-movies', name: 'SRF Movies', genre: '🎬 Movies', cat: 'movies',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d9/SRF_logo.svg/200px-SRF_logo.svg.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/177H/playlist.m3u8',
  ),
  LiveChannel(
    id: 'inplus', name: 'InPlus Pak', genre: '⭐ Movies', cat: 'movies',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/0/04/InPlus_Pak_logo.jpg',
    streamUrl: 'https://cdn23lhr.tamashaweb.com:8087/jazzauth/Inplus-abr/playlist.m3u8',
  ),

  // ── DOCS & LIFESTYLE ────────────────────────────────────────────────────
  LiveChannel(
    id: 'discovery-hd', name: 'Discovery HD', genre: '🦁 Discovery', cat: 'docs',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/discovery.png',
    streamUrl: 'https://cdn05khi.tamashaweb.com:8087/jazzauth/DiscoveryHD-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'cgtn-doc', name: 'CGTN Documentary', genre: '🎥 Docs', cat: 'docs',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/CGTN_logo.svg/200px-CGTN_logo.svg.png',
    streamUrl: 'https://cdn23lhr.tamashaweb.com:8087/jazzauth/CgtnDocumentary-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'animal-planet', name: 'Animal Planet', genre: '🐘 Nature', cat: 'docs',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/animal-planet.png',
    streamUrl: 'https://cdn07isb.tamashaweb.com:8087/YlUHeDQb7a/AnimalPlanet-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'disc-pak', name: 'Discover Pakistan', genre: '🇵🇰 Docs', cat: 'docs',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/e/e5/PTV_Sports_logo.png',
    streamUrl: 'https://cdn12isb.tamashaweb.com:8087/YlUHeDQb7a/DiscoveryPakistan-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'hum-masala', name: 'Hum Masala', genre: '🍳 Food', cat: 'docs',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/hum-masala.png',
    streamUrl: 'https://cdn05khi.tamashaweb.com:8087/jazzauth/hummasala-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'tamasha-women', name: 'Tamasha Woman', genre: '👩 Lifestyle', cat: 'docs',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/tamasha.png',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/Tamasha-Women-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'tamasha-life', name: 'Tamasha Life', genre: '🌿 Lifestyle', cat: 'docs',
    logoUrl: 'https://tamashaweb.com/wp-content/uploads/2023/07/tamasha.png',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/Tamasha-Life-HD-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bbc-earth', name: 'BBC Earth', genre: '🌍 Nature', cat: 'docs',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/en/4/4c/BBC_Earth_logo.svg',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/BBC-Earth-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'bbc-lifestyle', name: 'BBC Lifestyle', genre: '🌱 Lifestyle', cat: 'docs',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/4/41/BBC_Logo_2021.svg',
    streamUrl: 'https://cdn21lhr.tamashaweb.com:8087/jazzauth/BBC-Lifestyle-abr/playlist.m3u8',
  ),
  LiveChannel(
    id: 'disc-science', name: 'Discovery Science', genre: '🔬 Science', cat: 'docs',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7f/Discovery_Channel_logo_2019.svg/200px-Discovery_Channel_logo_2019.svg.png',
    streamUrl: 'https://cdn22lhr.tamashaweb.com:8087/jazzauth/Discovery-Science-abr/playlist.m3u8',
  ),
];
