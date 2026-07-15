import 'dart:math';
import 'audit.dart';
import 'auth.dart';

// Konfigurierbare Werte — werden einmalig beim Start gesetzt
String _appDomain = '';
String _appLagerOu = '';
List<String> _appComputerPrefixes = [];

void configureTemplates({
  required String domain,
  required String lagerOu,
  required List<String> computerPrefixes,
}) {
  _appDomain = domain;
  _appLagerOu = lagerOu;
  _appComputerPrefixes = computerPrefixes;
}

String _searchHistoryPills(List<String> history, {bool prominent = false}) {
  if (history.isEmpty) return '';
  if (prominent) {
    final pills = history.take(8).map((q) =>
      '<a href="/search?q=${Uri.encodeComponent(q)}" style="display:inline-flex;align-items:center;gap:.4rem;padding:.45rem .9rem;background:rgba(255,255,255,.10);border:1px solid rgba(255,255,255,.18);border-radius:8px;text-decoration:none;font:500 .85rem var(--mono);color:rgba(255,255,255,.85);transition:all .15s;white-space:nowrap;" onmouseover="this.style.background=\'rgba(255,255,255,.2)\';this.style.borderColor=\'rgba(255,255,255,.35)\'" onmouseout="this.style.background=\'rgba(255,255,255,.10)\';this.style.borderColor=\'rgba(255,255,255,.18)\'">'
      '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" style="opacity:.5"><circle cx="8" cy="8" r="6"/><path d="M8 5v3l2 1.5"/></svg>'
      '${_esc(q)}</a>'
    ).join('\n');
    return '''
  <div style="margin-top:1.1rem;border-top:1px solid rgba(255,255,255,.08);padding-top:.9rem;">
    <span style="font:600 10px var(--mono);letter-spacing:.1em;text-transform:uppercase;color:rgba(255,255,255,.28);display:block;margin-bottom:.55rem;">Zuletzt gesucht</span>
    <div style="display:flex;flex-wrap:wrap;gap:.4rem;">$pills</div>
  </div>''';
  }
  final pills = history.take(5).map((q) =>
    '<a href="/search?q=${Uri.encodeComponent(q)}" style="display:inline-flex;align-items:center;padding:.25rem .65rem;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);border-radius:20px;text-decoration:none;font:500 .78rem var(--mono);color:rgba(255,255,255,.55);transition:all .12s;white-space:nowrap;" onmouseover="this.style.background=\'rgba(255,255,255,.15)\';this.style.color=\'rgba(255,255,255,.9)\'" onmouseout="this.style.background=\'rgba(255,255,255,.08)\';this.style.color=\'rgba(255,255,255,.55)\'">${_esc(q)}</a>'
  ).join('\n');
  return '''
  <div style="display:flex;align-items:center;gap:.5rem;margin-top:.75rem;flex-wrap:wrap;">
    <span style="font:400 .72rem var(--mono);color:rgba(255,255,255,.28);white-space:nowrap;">Zuletzt:</span>
    $pills
  </div>''';
}

// ── Dark Mode CSS variables ───────────────────────────────────────────────────
const _darkCss = '''
[data-theme="dark"] {
  --navy:    #0a0f1e;
  --navy-2:  #0f172a;
  --navy-3:  #1e293b;
  --gray-50:  #1e2130;
  --gray-100: #252a3d;
  --gray-200: #2e3450;
  --gray-300: #3d4560;
  --gray-400: #6b7694;
  --gray-500: #8891a8;
  --gray-600: #94a3b8;
  --gray-700: #cbd5e1;
  --gray-800: #e2e8f0;
  --text: #e2e8f0;
  --surface: #1a1d27;
  --blue-lt: rgba(37,99,235,.18);
  --green-lt: rgba(26,122,77,.18);
  --red-lt:   rgba(192,40,42,.18);
  --amber-lt: rgba(146,64,14,.18);
}
[data-theme="dark"] body { background: #0d0f14; color: #e2e8f0; }
[data-theme="dark"] .content { background: #0d0f14; }
[data-theme="dark"] .card { background: #1a1d27; border-color: #2e3450; }
[data-theme="dark"] .card-pad { background: transparent; }
[data-theme="dark"] .result-table thead th { background: #1e2130; color: #6b7694; }
[data-theme="dark"] .result-table tbody tr:hover td { background: #252a3d !important; }
[data-theme="dark"] tbody tr:hover td { background: #252a3d !important; }
[data-theme="dark"] thead th { background: #1e2130; color: #6b7694; }
[data-theme="dark"] tbody td { border-color: #252a3d; color: #e2e8f0; }
[data-theme="dark"] .search-box input,
[data-theme="dark"] input[type=text],
[data-theme="dark"] input[type=password],
[data-theme="dark"] input[type=email],
[data-theme="dark"] input[type=date],
[data-theme="dark"] textarea,
[data-theme="dark"] select {
  background: #1e2130 !important; border-color: #2e3450 !important; color: #e2e8f0 !important;
}
[data-theme="dark"] .btn-ghost { background: #1e2130; border-color: #2e3450; color: #94a3b8; }
[data-theme="dark"] .btn-ghost:hover { background: #252a3d; border-color: #3d4560; color: #e2e8f0; }
[data-theme="dark"] .btn-danger { background: rgba(192,40,42,.15); color: #f87171; border-color: rgba(192,40,42,.3); }
[data-theme="dark"] .btn-danger:hover { background: rgba(192,40,42,.25); }
[data-theme="dark"] .btn-success { background: rgba(26,122,77,.15); color: #4ade80; border-color: rgba(26,122,77,.3); }
[data-theme="dark"] .btn-success:hover { background: rgba(26,122,77,.25); }
[data-theme="dark"] .group-item { background: #1e2130; border-color: #2e3450; }
[data-theme="dark"] .picker-item { background: #1e2130; border-color: #2e3450; }
[data-theme="dark"] .picker-item:hover { background: #252a3d !important; border-color: #3d4560; }
[data-theme="dark"] .field-item { border-color: #2e3450; }
[data-theme="dark"] .field-col:first-child { border-color: #2e3450; }
[data-theme="dark"] .section { border-color: #2e3450; }
[data-theme="dark"] .detail-header { background: linear-gradient(180deg,#161920 0%,#1a1d27 80%) !important; border-color: #2e3450; }
[data-theme="dark"] .ou-node:hover { background: #252a3d; }
[data-theme="dark"] code { background: #252a3d; color: #94a3b8; }
[data-theme="dark"] .badge-active   { background: rgba(34,197,94,.15);  color: #4ade80; }
[data-theme="dark"] .badge-disabled { background: rgba(239,68,68,.15);  color: #f87171; }
[data-theme="dark"] .badge-locked   { background: rgba(245,158,11,.15); color: #fbbf24; }
[data-theme="dark"] .alert-success  { background: rgba(34,197,94,.12); color: #4ade80; border-color: rgba(34,197,94,.25); }
[data-theme="dark"] .alert-error    { background: rgba(239,68,68,.12); color: #f87171; border-color: rgba(239,68,68,.25); }
[data-theme="dark"] .avatar-placeholder { background: linear-gradient(135deg,#252a3d,#1e2537); }
[data-theme="dark"] .detail-avatar-ph  { background: linear-gradient(135deg,#252a3d,#1e2537); }
[data-theme="dark"] .photo-ph { background: #1e2130; border-color: #2e3450; color: #6b7694; }
[data-theme="dark"] .inline-edit input { background: #1e2130 !important; border-color: #2e3450 !important; color: #e2e8f0 !important; }
[data-theme="dark"] .add-group-form input { background: #1e2130 !important; border-color: #2e3450 !important; color: #e2e8f0 !important; }
[data-theme="dark"] .surf { background: #1a1d27 !important; border-color: #2e3450 !important; color: #e2e8f0 !important; }
[data-theme="dark"] .surf .surf-title { color: #e2e8f0 !important; }
[data-theme="dark"] .surf .surf-sub   { color: #6b7694 !important; }
''';

String _layout(String username, String title, String body, {String active = '', String csrfToken = ''}) => '''
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="csrf-token" content="$csrfToken">
  <meta name="generator" content="UserDesk · Built by Somedia IT">
  <!-- UserDesk · Powered by Somedia IT · somedia.ch -->
  <title>$title – LDAP Tool</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <script>
    (function() {
      try {
        var t = localStorage.getItem('theme');
        if (t === 'dark') document.documentElement.setAttribute('data-theme','dark');
      } catch(e){}
    })();
  </script>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --navy:    #0f172a;
      --navy-2:  #1e293b;
      --navy-3:  #334155;
      --blue:    #2563eb;
      --blue-lt: #eff6ff;
      --blue-dk: #1d4ed8;
      --green:   #1a7a4d; --green-lt: #eaf5ee;
      --red:     #c0282a; --red-lt:   #fae9e9;
      --amber:   #92400e; --amber-lt: #fef3c7;
      --gray-50:  #f8f9fb;
      --gray-100: #f1f2f6;
      --gray-200: #e3e5ec;
      --gray-300: #c8ccd7;
      --gray-400: #9199aa;
      --gray-500: #6b7280;
      --gray-600: #4b5263;
      --gray-800: #1a1d27;
      --surface:  #ffffff;
      --radius: 12px;
      --shadow-xs: 0 1px 2px rgba(0,0,0,.04);
      --shadow-sm: 0 1px 3px rgba(0,0,0,.08), 0 1px 2px rgba(0,0,0,.05);
      --shadow-md: 0 4px 16px rgba(0,0,0,.10), 0 1px 4px rgba(0,0,0,.06);
      --sans: 'Inter', system-ui, -apple-system, sans-serif;
      --mono: 'IBM Plex Mono', ui-monospace, monospace;
    }

    body { font-family: var(--sans); font-size: 15px; background: #f1f4f9; color: var(--gray-800); -webkit-font-smoothing: antialiased; }
    .app { display: flex; min-height: 100vh; }

    /* ── Sidebar ── */
    .sidebar {
      width: 252px; flex-shrink: 0;
      position: sticky; top: 0; height: 100vh;
      display: flex; flex-direction: column;
      background: var(--navy);
      border-right: 1px solid rgba(255,255,255,.06);
      overflow: hidden;
    }
    .sidebar::before {
      content: '';
      position: absolute; inset: 0;
      background:
        radial-gradient(ellipse 140% 60% at 50% -10%, rgba(37,99,235,.22) 0%, transparent 65%);
      pointer-events: none;
    }

    .brand {
      display: flex; align-items: center; gap: .7rem;
      padding: 1.1rem 1.1rem .95rem;
      border-bottom: 1px solid rgba(255,255,255,.05);
      position: relative;
    }
    .brand-mark {
      width: 34px; height: 34px; border-radius: 9px;
      background: linear-gradient(135deg, #2563eb 0%, #3b82f6 100%);
      display: flex; align-items: center; justify-content: center;
      font: 700 12px var(--sans); color: #fff; flex-shrink: 0;
      box-shadow: 0 2px 10px rgba(37,99,235,.55);
      letter-spacing: .03em;
    }
    .brand-name { font: 700 14px var(--sans); color: #fff; line-height: 1.2; letter-spacing: .01em; }
    .brand-sub  { font: 500 10px var(--sans); letter-spacing: .04em; color: rgba(255,255,255,.4); margin-top: 2px; }

    .nav-group {
      padding: .85rem 1.1rem .3rem;
      font: 600 10px var(--sans); letter-spacing: .1em; text-transform: uppercase;
      color: rgba(255,255,255,.3);
    }
    nav { display: flex; flex-direction: column; gap: 2px; padding: 0 .7rem; position: relative; }

    .nav-link {
      display: flex; align-items: center; gap: .65rem;
      color: rgba(255,255,255,.55); text-decoration: none;
      font: 500 13.5px var(--sans);
      padding: .55rem .8rem; border-radius: 8px;
      transition: color .12s, background .12s;
      position: relative; z-index: 1;
    }
    .nav-link svg { flex-shrink: 0; transition: opacity .12s; opacity: .7; }
    .nav-link:hover { color: rgba(255,255,255,.95); background: rgba(255,255,255,.07); }
    .nav-link:hover svg { opacity: 1; }
    .nav-link.active {
      color: #fff; background: rgba(37,99,235,.25);
      box-shadow: inset 3px 0 0 #60a5fa;
    }
    .nav-link.active svg { opacity: 1; }

    .sidebar-foot {
      margin-top: auto; padding: .85rem 1.1rem;
      border-top: 1px solid rgba(255,255,255,.05);
      position: relative;
    }
    .conn {
      display: flex; align-items: center; gap: .45rem; margin-bottom: .7rem;
      font: 500 10px var(--mono); color: rgba(255,255,255,.3);
    }
    .conn-dot {
      width: 6px; height: 6px; border-radius: 50%;
      background: #22c55e; flex-shrink: 0;
      box-shadow: 0 0 0 2px rgba(34,197,94,.22);
      animation: pulse 2.8s ease-in-out infinite;
    }
    @keyframes pulse {
      0%,100% { box-shadow: 0 0 0 2px rgba(34,197,94,.2); }
      50%      { box-shadow: 0 0 0 4px rgba(34,197,94,.08); }
    }
    .conn-tls { margin-left: auto; color: #22c55e; font-size: 9px; letter-spacing: .06em; }

    .nav-user { display: flex; align-items: center; gap: .55rem; }
    .nav-user-av {
      width: 30px; height: 30px; border-radius: 8px;
      background: linear-gradient(135deg, #2563eb, #3b82f6);
      color: #fff; display: flex; align-items: center; justify-content: center;
      font: 700 11px var(--sans); flex-shrink: 0;
    }
    .nav-user-name { font: 600 12.5px var(--sans); color: rgba(255,255,255,.9); line-height: 1.2; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .nav-user-role { font: 400 10px var(--sans); color: rgba(255,255,255,.35); margin-top: 1px; }
    .nav-user a {
      margin-left: auto; color: rgba(255,255,255,.38); text-decoration: none;
      font: 500 11px var(--mono); padding: .28rem .5rem;
      border: 1px solid rgba(255,255,255,.1); border-radius: 6px;
      transition: all .12s; flex-shrink: 0;
    }
    .nav-user a:hover { border-color: var(--blue); color: #fff; background: rgba(37,99,235,.2); }

    /* ── Content ── */
    .content { flex: 1; min-width: 0; display: flex; flex-direction: column; }
    main { max-width: 1600px; margin: 1.5rem auto; padding: 0 1.5rem; width: 100%; box-sizing: border-box; }

    /* ── Cards ── */
    .card {
      background: #fff; border-radius: var(--radius);
      border: 1px solid var(--gray-200);
      box-shadow: var(--shadow-sm);
      margin-bottom: 1.25rem;
      overflow: hidden;
    }
    .card-pad { padding: 1.4rem 1.6rem; }
    .card-section-title {
      font: 600 11px var(--sans); letter-spacing: .08em; text-transform: uppercase;
      color: var(--gray-400); margin-bottom: .9rem;
    }

    /* ── Search box ── */
    .search-box { display: flex; gap: .5rem; }
    .search-box input {
      flex: 1; padding: .65rem 1rem;
      border: 1.5px solid var(--gray-200); border-radius: 8px;
      font: 400 14px var(--sans); color: var(--gray-800);
      background: white; transition: border-color .15s, box-shadow .15s;
    }
    .search-box input:focus { outline: none; border-color: var(--blue); box-shadow: 0 0 0 3px rgba(37,99,235,.12); }
    .search-box input::placeholder { color: var(--gray-400); }

    /* ── Buttons ── */
    .btn {
      display: inline-flex; align-items: center; gap: .4rem;
      padding: .55rem 1.1rem; border: none; border-radius: 8px;
      font: 500 14px var(--sans); cursor: pointer; text-decoration: none;
      transition: all .13s; white-space: nowrap; letter-spacing: .01em;
    }
    .btn-primary { background: var(--blue); color: #fff; box-shadow: 0 1px 4px rgba(37,99,235,.4); }
    .btn-primary:hover { background: var(--blue-dk); box-shadow: 0 3px 10px rgba(37,99,235,.5); transform: translateY(-1px); }
    .btn-primary:active { transform: none; box-shadow: 0 1px 3px rgba(37,99,235,.3); }
    .btn-ghost { background: white; color: var(--gray-600); border: 1px solid var(--gray-200); }
    .btn-ghost:hover { background: var(--gray-50); border-color: var(--gray-300); color: var(--gray-800); }
    .btn-danger { background: var(--red-lt); color: var(--red); border: 1px solid #f5c0c0; }
    .btn-danger:hover { background: #f7d0d0; border-color: #e8a0a0; }
    .btn-success { background: var(--green-lt); color: var(--green); border: 1px solid #a8d8bc; }
    .btn-success:hover { background: #d6eddf; }
    .btn-sm { padding: .32rem .7rem; font-size: .85rem; border-radius: 7px; }
    .btn-xs { padding: .2rem .5rem; font-size: .78rem; border-radius: 6px; }

    /* ── Result table ── */
    .table-wrap { overflow-x: auto; width: 100%; }
    .result-table { width: max-content; min-width: 100%; border-collapse: collapse; font-size: .78rem; }
    .result-table thead th {
      text-align: left; padding: .3rem .2rem;
      background: var(--gray-50);
      border-bottom: 1px solid var(--gray-200);
      font: 600 .67rem var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--gray-400);
      white-space: nowrap;
    }
    .result-table tbody td { padding: .35rem .2rem; border-bottom: 1px solid var(--gray-100); vertical-align: middle; }
    .result-table tbody tr:last-child td { border-bottom: none; }
    .result-table tbody tr { transition: background .1s; }
    .result-table tbody tr:hover td { background: #f4f5fb; }
    .result-table td:nth-child(1), .result-table th:nth-child(1) { max-width: 140px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .result-table td:nth-child(3), .result-table th:nth-child(3) { max-width: 220px; }
    .result-table td:nth-child(3) strong { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .result-table td:nth-child(4), .result-table th:nth-child(4) { max-width: 120px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .result-table td:nth-child(5), .result-table th:nth-child(5) { width: 1%; white-space: nowrap; }

    .avatar-sm { width: 34px; height: 34px; border-radius: 8px; object-fit: cover; }
    .avatar-placeholder {
      width: 34px; height: 34px; border-radius: 8px;
      background: linear-gradient(135deg, #e8ebfa 0%, #d4d9f5 100%);
      color: var(--blue);
      display: flex; align-items: center; justify-content: center;
      font: 700 12px var(--mono);
    }

    /* ── Badges ── */
    .badge {
      display: inline-flex; align-items: center; gap: .3rem;
      padding: .25rem .65rem; border-radius: 6px;
      font: 600 .72rem var(--sans); letter-spacing: .03em; text-transform: uppercase;
    }
    .badge::before { content: ''; width: 6px; height: 6px; border-radius: 50%; background: currentColor; opacity: .8; flex-shrink: 0; }
    .badge-active   { background: var(--green-lt); color: #166539; }
    .badge-disabled { background: var(--red-lt);   color: #9b2020; }
    .badge-locked   { background: var(--amber-lt); color: var(--amber); }

    /* ── Detail page ── */
    .detail-header {
      display: flex; align-items: flex-start; gap: 1.5rem;
      padding: 1.75rem 1.5rem 1.5rem;
      border-bottom: 1px solid var(--gray-100);
      background: linear-gradient(180deg, #f6f7fb 0%, #fff 80%);
      position: relative;
    }
    .detail-header::before {
      content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
      background: linear-gradient(90deg, var(--blue) 0%, #60a5fa 100%);
    }
    .detail-avatar { width: 80px; height: 80px; border-radius: 14px; object-fit: cover; border: 2px solid var(--gray-200); flex-shrink: 0; box-shadow: var(--shadow-sm); }
    .detail-avatar-ph {
      width: 80px; height: 80px; border-radius: 14px;
      background: linear-gradient(135deg, #e8ebfa 0%, #d0d6f4 100%);
      color: var(--blue); display: flex; align-items: center; justify-content: center;
      font: 700 2rem var(--mono); flex-shrink: 0;
    }
    .detail-name { font: 700 19px var(--sans); color: var(--gray-800); line-height: 1.3; }
    .detail-sub  { font-size: .88rem; color: var(--gray-400); margin-top: .3rem; }
    .dn-text { font: 400 .68rem var(--mono); color: var(--gray-300); word-break: break-all; margin-top: .4rem; line-height: 1.5; }

    /* ── Field grid ── */
    .field-grid { display: grid; grid-template-columns: 1fr 1fr; }
    @media(max-width:640px) { .field-grid { grid-template-columns: 1fr; } }
    .field-col { padding: 1rem 1.5rem; }
    .field-col:first-child { border-right: 1px solid var(--gray-100); }
    .field-item { padding: .65rem 0; border-bottom: 1px solid var(--gray-100); }
    .field-item:last-child { border-bottom: none; }
    .field-label { font: 600 .72rem var(--sans); letter-spacing: .05em; text-transform: uppercase; color: var(--gray-400); margin-bottom: .3rem; }
    .field-val { font-size: .95rem; display: flex; align-items: center; gap: .5rem; flex-wrap: wrap; color: var(--gray-800); }
    .field-val em { color: var(--gray-300); font-style: normal; }

    .inline-edit { display: none; margin-top: .5rem; }
    .inline-edit form { display: flex; gap: .4rem; }
    .inline-edit input {
      flex: 1; padding: .38rem .65rem;
      border: 1.5px solid var(--gray-200); border-radius: 7px;
      font: 400 .875rem var(--sans); transition: border-color .15s, box-shadow .15s;
    }
    .inline-edit input:focus { outline: none; border-color: var(--blue); box-shadow: 0 0 0 3px rgba(37,99,235,.1); }

    .edit-link {
      font: 500 .72rem var(--sans); color: var(--blue); cursor: pointer;
      background: none; border: none; padding: 0; opacity: .6; transition: opacity .12s;
    }
    .edit-link:hover { opacity: 1; text-decoration: underline; }

    /* ── Section ── */
    .section { padding: 1.25rem 1.5rem; border-top: 1px solid var(--gray-100); }
    .section-title {
      font: 700 .69rem var(--mono); letter-spacing: .1em; text-transform: uppercase;
      color: var(--gray-400); margin-bottom: 1rem;
      display: flex; align-items: center; justify-content: space-between;
    }

    /* ── Group items ── */
    .group-item {
      display: flex; align-items: center; justify-content: space-between;
      padding: .5rem .8rem; border-radius: 7px;
      background: var(--gray-50); border: 1px solid var(--gray-100);
      font-size: .875rem; transition: border-color .1s;
    }
    .group-item:hover { border-color: var(--gray-200); }
    .group-name { font-weight: 600; font-size: .88rem; }
    .group-dn   { font: 400 .7rem var(--mono); color: var(--gray-400); }

    .add-group-form { display: flex; gap: .4rem; margin-top: .9rem; }
    .add-group-form input {
      flex: 1; padding: .45rem .75rem;
      border: 1.5px solid var(--gray-200); border-radius: 7px; font-size: .875rem;
      transition: border-color .15s, box-shadow .15s;
    }
    .add-group-form input:focus { outline: none; border-color: var(--blue); box-shadow: 0 0 0 3px rgba(37,99,235,.1); }

    /* ── Alerts ── */
    .alert {
      display: flex; align-items: center; gap: .65rem;
      padding: .85rem 1.1rem; border-radius: 8px; margin-bottom: 1rem; font-size: .875rem;
      font-weight: 500;
    }
    .alert-success { background: var(--green-lt); color: #166539; border: 1px solid #a8d8bc; }
    .alert-error   { background: var(--red-lt);   color: #9b2020; border: 1px solid #f5c0c0; }

    /* ── Generic table ── */
    table { width: max-content; min-width: 100%; border-collapse: collapse; font-size: .78rem; }
    thead th {
      text-align: left; padding: .3rem .2rem;
      background: var(--gray-50); border-bottom: 1px solid var(--gray-200);
      font: 600 .67rem var(--mono); letter-spacing: .1em; text-transform: uppercase; color: var(--gray-400);
      white-space: nowrap;
    }
    tbody td { padding: .35rem .2rem; border-bottom: 1px solid var(--gray-100); }
    tbody tr:last-child td { border-bottom: none; }
    tbody tr { transition: background .08s; }
    tbody tr:hover td { background: #f4f5fb; }
    /* Wrapper für horizontales Scrollen bei Tabellen */
    .card > .table-wrap { overflow-x: auto; width: 100%; }
    .card > table { display: table; }

    /* ── Group picker ── */
    .picker-list { display: flex; flex-direction: column; gap: .5rem; margin-top: 1rem; }
    .picker-item {
      display: flex; justify-content: space-between; align-items: center;
      padding: .7rem 1rem; background: var(--gray-50);
      border-radius: 8px; border: 1px solid var(--gray-100);
      transition: border-color .12s, background .12s;
    }
    .picker-item:hover { background: white; border-color: var(--gray-200); }

    /* ── Photo ── */
    .photo-row { display: flex; align-items: center; gap: 1rem; flex-wrap: wrap; }
    .photo-preview { width: 100px; height: 100px; border-radius: 10px; object-fit: cover; border: 1px solid var(--gray-200); box-shadow: var(--shadow-xs); }
    .photo-ph { width: 100px; height: 100px; border-radius: 10px; background: var(--gray-100); border: 1.5px dashed var(--gray-300); display: flex; align-items: center; justify-content: center; color: var(--gray-400); font-size: .8rem; }

    /* ── Misc ── */
    code { font-family: var(--mono); font-size: .9em; background: var(--gray-100); padding: .1em .3em; border-radius: 4px; }
    input[type=date] { font-family: var(--sans); color: var(--gray-800); }

    /* ── Dark Mode Toggle Button ── */
    .dark-toggle {
      display: flex; align-items: center; justify-content: center;
      width: 30px; height: 30px; border-radius: 7px; border: none;
      background: rgba(255,255,255,.08); color: rgba(255,255,255,.6);
      cursor: pointer; transition: background .15s, color .15s; flex-shrink: 0;
      font-size: 14px;
    }
    .dark-toggle:hover { background: rgba(255,255,255,.15); color: #fff; }

    /* ── Favorite Star ── */
    .fav-btn { background: none; border: none; cursor: pointer; font-size: 1.1rem; line-height: 1; padding: .2rem; opacity: .5; transition: opacity .12s, transform .12s; }
    .fav-btn:hover { opacity: 1; transform: scale(1.15); }
    .fav-btn.active { opacity: 1; }

    ${'$_darkCss'}

    /* ── Responsive (Tablet/Mobile) ── */
    .mobile-header {
      display: none; align-items: center; gap: .75rem;
      padding: .75rem 1rem; background: var(--navy);
      position: sticky; top: 0; z-index: 99;
    }
    .hamburger {
      background: rgba(255,255,255,.08); border: none; color: rgba(255,255,255,.8);
      border-radius: 7px; width: 34px; height: 34px; font-size: 16px; cursor: pointer;
      display: flex; align-items: center; justify-content: center; flex-shrink: 0;
    }
    .sidebar-backdrop {
      display: none; position: fixed; inset: 0; background: rgba(0,0,0,.5); z-index: 99;
    }
    .overflow-x { overflow-x: auto; }

    @media (max-width: 900px) {
      .sidebar {
        position: fixed; left: -260px; z-index: 100; height: 100vh;
        transition: left .25s ease; top: 0; overflow-y: auto;
      }
      .sidebar.open { left: 0; }
      .sidebar-backdrop.open { display: block; }
      .content { margin-left: 0; }
      .mobile-header { display: flex; }
      main { padding: 0 .75rem; margin: .75rem auto; }
      .field-grid { grid-template-columns: 1fr !important; }
      .stat-grid { grid-template-columns: 1fr 1fr !important; }
      .dir-filter-wrap { flex-direction: column; }
    }
    @media (min-width: 901px) {
      .mobile-header { display: none !important; }
    }
    /* Tabellen immer mit Scroll-Wrapper, nie abschneiden */
    .table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; }
  </style>
<script>
function toggleEdit(btn, id) {
  const el = document.getElementById(id);
  const show = el.style.display !== 'block';
  el.style.display = show ? 'block' : 'none';
  btn.textContent = show ? 'Abbrechen' : 'Bearbeiten';
}
function toggleDark() {
  var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  var newTheme = isDark ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', newTheme);
  try { localStorage.setItem('theme', newTheme); } catch(e){}
  var btn = document.getElementById('dark-toggle');
  if (btn) btn.textContent = newTheme === 'dark' ? '☀' : '🌙';
}
(function() {
  try {
    var t = localStorage.getItem('theme');
    var btn = document.getElementById('dark-toggle');
    if (btn) btn.textContent = t === 'dark' ? '☀' : '🌙';
  } catch(e){}
})();
function generatePassword() {
  var chars = 'abcdefghijkmnpqrstuvwxyz';
  var upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  var nums  = '23456789';
  var syms  = '!@#%^&*';
  var all   = chars + upper + nums + syms;
  var pwd = '';
  pwd += upper[Math.floor(Math.random()*upper.length)];
  pwd += nums[Math.floor(Math.random()*nums.length)];
  pwd += syms[Math.floor(Math.random()*syms.length)];
  for (var i = 0; i < 9; i++) pwd += all[Math.floor(Math.random()*all.length)];
  pwd = pwd.split('').sort(function(){return Math.random()-.5}).join('');
  return pwd;
}
function applyGeneratedPassword(inputId, displayId) {
  var pwd = generatePassword();
  var inp = document.getElementById(inputId);
  if (inp) { inp.value = pwd; inp.type = 'text'; }
  var disp = document.getElementById(displayId);
  if (disp) { disp.textContent = pwd; disp.parentElement.style.display = 'flex'; }
}
function copyToClipboard(text) {
  navigator.clipboard.writeText(text).then(function() {
    var btn = event.target;
    var orig = btn.textContent;
    btn.textContent = '✓';
    setTimeout(function(){ btn.textContent = orig; }, 1500);
  }).catch(function() {
    var ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  });
}
function initPhotoUpload(fileId, previewId, b64Id, formId) {
  document.getElementById(fileId).addEventListener('change', function() {
    const file = this.files[0];
    if (!file) return;
    const canvas = document.createElement('canvas');
    canvas.width = 200; canvas.height = 200;
    const ctx = canvas.getContext('2d');
    const img = new Image();
    img.onload = () => {
      const s = Math.min(img.width, img.height);
      ctx.drawImage(img, (img.width-s)/2, (img.height-s)/2, s, s, 0, 0, 200, 200);
      const b64 = canvas.toDataURL('image/jpeg', 0.85).split(',')[1];
      document.getElementById(b64Id).value = b64;
      const prev = document.getElementById(previewId);
      if (prev && prev.tagName === 'IMG') {
        prev.src = 'data:image/jpeg;base64,' + b64;
      }
      if (formId) document.getElementById(formId).submit();
    };
    img.src = URL.createObjectURL(file);
  });
}
// ── CSRF: Automatisch in alle POST-Forms einfügen ─────────────────────────────
document.addEventListener('DOMContentLoaded', function() {
  document.addEventListener('submit', function(e) {
    var form = e.target;
    if (form.method && form.method.toLowerCase() === 'post') {
      var meta = document.querySelector('meta[name="csrf-token"]');
      if (meta && meta.content && !form.querySelector('[name="_csrf"]')) {
        var inp = document.createElement('input');
        inp.type = 'hidden'; inp.name = '_csrf'; inp.value = meta.content;
        form.appendChild(inp);
      }
    }
  }, true);
});
// ── Session-Inaktivitäts-Timeout ─────────────────────────────────────────────
(function() {
  var idle = 0;
  var warn = 55 * 60, limit = 60 * 60;
  var banner = document.getElementById('session-warn');
  setInterval(function() {
    idle++;
    if (idle >= limit) { location.href = '/logout'; return; }
    if (banner) banner.style.display = idle >= warn ? 'flex' : 'none';
    if (banner && idle >= warn) {
      var left = limit - idle;
      var el = document.getElementById('session-warn-timer');
      if (el) el.textContent = Math.floor(left/60) + ':' + ('0'+(left%60)).slice(-2);
    }
  }, 1000);
  ['click','keydown','mousemove','scroll'].forEach(function(ev) {
    document.addEventListener(ev, function() { idle = 0; }, {passive:true});
  });
})();
// ── Passwort-Stärke ───────────────────────────────────────────────────────────
function checkPasswordStrength(pwd) {
  var score = 0;
  var tips = [];
  if (pwd.length >= 8) score++; else tips.push('mind. 8 Zeichen');
  if (/[A-Z]/.test(pwd)) score++; else tips.push('Grossbuchstabe');
  if (/[a-z]/.test(pwd)) score++; else tips.push('Kleinbuchstabe');
  if (/[0-9]/.test(pwd)) score++; else tips.push('Zahl');
  if (/[^A-Za-z0-9]/.test(pwd)) score++; else tips.push('Sonderzeichen');
  return {score: score, tips: tips};
}
function updatePwStrength(val) {
  var res = checkPasswordStrength(val);
  var bar = document.getElementById('pw-strength-bar');
  var tips = document.getElementById('pw-strength-tips');
  var btn = document.getElementById('pw-submit-btn');
  if (!bar) return;
  var colors = ['#e5e7eb','#ef4444','#f59e0b','#22c55e','#16a34a','#15803d'];
  var labels = ['','Sehr schwach','Schwach','Mittel','Stark','Sehr stark'];
  bar.style.width = (res.score * 20) + '%';
  bar.style.background = colors[res.score] || colors[0];
  bar.title = labels[res.score] || '';
  if (tips) tips.textContent = res.tips.length > 0 ? 'Fehlt: ' + res.tips.join(', ') : '';
  if (btn) btn.disabled = res.score < 3;
}
// ── Hamburger-Menü ────────────────────────────────────────────────────────────
function toggleSidebar() {
  var sb = document.querySelector('.sidebar');
  var bd = document.querySelector('.sidebar-backdrop');
  if (sb) sb.classList.toggle('open');
  if (bd) bd.classList.toggle('open');
}
</script>
</head>
<body>
<div class="sidebar-backdrop" onclick="toggleSidebar()"></div>
<div class="mobile-header">
  <button class="hamburger" onclick="toggleSidebar()">&#9776;</button>
  <div style="font:700 13.5px var(--sans);color:#fff;">UserDesk</div>
</div>
<div class="app">
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-mark">UD</div>
      <div>
        <div class="brand-name">UserDesk</div>
        <div class="brand-sub">Benutzerverwaltung</div>
      </div>
    </div>
    <div class="nav-group">Benutzer &amp; Gruppen</div>
    <nav>
      <a href="/" class="nav-link ${active == 'dashboard' ? 'active' : active == 'search' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="7" cy="7" r="4.2"/><line x1="10.2" y1="10.2" x2="13.5" y2="13.5" stroke-linecap="round"/></svg>
        Benutzer suchen
      </a>
      <a href="/search/advanced" class="nav-link ${active == 'advsearch' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="7" cy="7" r="4.2"/><line x1="10.2" y1="10.2" x2="13.5" y2="13.5" stroke-linecap="round"/><line x1="5" y1="5" x2="9" y2="9" stroke-linecap="round"/></svg>
        Erweiterte Suche
      </a>
      <a href="/groups" class="nav-link ${active == 'groups' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="5.5" cy="6" r="2.6"/><circle cx="11" cy="6.6" r="2.1"/><path d="M1.7 13c0-2.2 1.7-3.6 3.8-3.6s3.8 1.4 3.8 3.6"/></svg>
        Gruppen
      </a>
      <a href="/ou" class="nav-link ${active == 'ou' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2" y="2.5" width="5" height="4" rx="1"/><rect x="8.5" y="9.5" width="5.5" height="4" rx="1"/><path d="M4.5 6.5v3.5h6"/></svg>
        Ordner-Struktur
      </a>
      <a href="/computers" class="nav-link ${active == 'computers' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2" y="2" width="12" height="9" rx="1.5"/><path d="M5 13.5h6M8 11v2.5" stroke-linecap="round"/></svg>
        Computer
      </a>
      <a href="/audit" class="nav-link ${active == 'log' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><line x1="3" y1="4.5" x2="13" y2="4.5"/><line x1="3" y1="8" x2="13" y2="8"/><line x1="3" y1="11.5" x2="9.5" y2="11.5"/></svg>
        Protokoll
      </a>
      <a href="/orgchart" class="nav-link ${active == 'orgchart' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="5.5" y="1.5" width="5" height="3.5" rx="1"/><rect x="1" y="11" width="4.5" height="3.5" rx="1"/><rect x="5.5" y="11" width="4.5" height="3.5" rx="1"/><rect x="10.5" y="11" width="4.5" height="3.5" rx="1"/><path d="M8 5v2.5M3.25 11V8.5h9.5V11M8 8.5V7" stroke-linecap="round"/></svg>
        Org-Diagramm
      </a>
      <a href="/directory" class="nav-link ${active == 'directory' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2" y="3" width="12" height="10" rx="1.5"/><path d="M5 7.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM3 11c0-1.1.9-2 2-2s2 .9 2 2" stroke-linecap="round"/><line x1="9" y1="6" x2="13" y2="6" stroke-linecap="round"/><line x1="9" y1="9" x2="13" y2="9" stroke-linecap="round"/></svg>
        Telefonliste
      </a>
      <a href="/stats/departments" class="nav-link ${active == 'depts' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><line x1="2" y1="4" x2="10" y2="4"/><line x1="2" y1="7.5" x2="13" y2="7.5"/><line x1="2" y1="11" x2="8" y2="11"/></svg>
        Abteilungen
      </a>
    </nav>
    <div class="nav-group">Schnellansichten</div>
    <nav>
      <a href="/users/locked" class="nav-link ${active == 'locked' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="4" y="7.5" width="8" height="6.5" rx="1.5"/><path d="M5.5 7.5V5.5a2.5 2.5 0 0 1 5 0v2" stroke-linecap="round"/></svg>
        Gesperrte User
      </a>
      <a href="/users/disabled" class="nav-link ${active == 'disabled' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="8" r="5.5"/><line x1="4.5" y1="11.5" x2="11.5" y2="4.5" stroke-linecap="round"/></svg>
        Deaktivierte User
      </a>
      <a href="/users/pw-expiring" class="nav-link ${active == 'pw-expiring' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="8" r="5.5"/><path d="M8 5v3.5l2 1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
        Passwort läuft ab
      </a>
      <a href="/users/inactive" class="nav-link ${active == 'inactive' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="6" r="3"/><path d="M2 14c0-3 2.5-5 6-5s6 2 6 5"/><line x1="11" y1="3" x2="14" y2="6" stroke-linecap="round"/></svg>
        Lange inaktiv
      </a>
      <a href="/users/service" class="nav-link ${active == 'service' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="6" r="3"/><path d="M2 14c0-3 2.5-5 6-5s6 2 6 5"/><circle cx="13" cy="3" r="1.5" fill="currentColor" stroke="none"/></svg>
        Service-Konten
      </a>
      <a href="/users/no-email" class="nav-link ${active == 'noemail' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2" y="4" width="12" height="9" rx="1.5"/><path d="M2 6l6 4 6-4"/><line x1="1" y1="15" x2="15" y2="1" stroke-linecap="round"/></svg>
        Ohne E-Mail
      </a>
      <a href="/users/expiring-accounts" class="nav-link ${active == 'expiring' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2" y="2.5" width="12" height="12" rx="1.5"/><path d="M5 1v3M11 1v3M2 7h12" stroke-linecap="round"/><path d="M8 10v2.5l1.5 1" stroke-linecap="round" stroke-linejoin="round"/></svg>
        Konten laufen ab
      </a>
    </nav>
    <div class="nav-group">System</div>
    <nav>
      <a href="/admin/roles" class="nav-link ${active == 'roles' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="6" r="3"/><path d="M2 14c0-3 2.5-5 6-5s6 2 6 5"/><polyline points="11,4 13,6 15,4" stroke-linecap="round" stroke-linejoin="round"/></svg>
        Zugriffsrechte
      </a>
      <a href="/config" class="nav-link ${active == 'config' ? 'active' : ''}">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="8" r="2.5"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.2 3.2l1.4 1.4M11.4 11.4l1.4 1.4M3.2 12.8l1.4-1.4M11.4 4.6l1.4-1.4" stroke-linecap="round"/></svg>
        Einstellungen
      </a>
    </nav>
    <div class="sidebar-foot">
      <div class="conn"><span class="conn-dot"></span>$_appDomain<span class="conn-tls">636·TLS</span></div>
      <div style="display:flex;align-items:center;gap:.55rem;">
        <a href="/settings" style="display:flex;align-items:center;gap:.55rem;text-decoration:none;flex:1;min-width:0;padding:.3rem .4rem;border-radius:7px;transition:background .12s;" onmouseover="this.style.background='rgba(255,255,255,.06)'" onmouseout="this.style.background=''">
          <div class="nav-user-av">${username.isNotEmpty ? username[0].toUpperCase() : 'A'}</div>
          <div style="flex:1;min-width:0;">
            <div class="nav-user-name" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">$username</div>
            <div class="nav-user-role" style="color:${active == 'settings' ? 'rgba(255,255,255,.65)' : 'rgba(255,255,255,.3)'};">Einstellungen ${active == 'settings' ? '·' : '→'}</div>
          </div>
        </a>
        <button class="dark-toggle" id="dark-toggle" onclick="toggleDark()" title="Dark/Light Mode">🌙</button>
        <a href="/logout" title="Abmelden" style="color:rgba(255,255,255,.35);text-decoration:none;font:500 11px var(--mono);padding:.3rem .5rem;border:1px solid rgba(255,255,255,.1);border-radius:6px;transition:all .12s;flex-shrink:0;" onmouseover="this.style.borderColor='var(--blue)';this.style.color='#fff'" onmouseout="this.style.borderColor='rgba(255,255,255,.1)';this.style.color='rgba(255,255,255,.35)'">↩</a>
      </div>
    </div>
  </aside>
  <div class="content">
    <main>$body</main>
  </div>
</div>
<div id="session-warn" style="display:none;position:fixed;bottom:1rem;right:1rem;background:#fef3c7;border:1px solid #fcd34d;border-radius:10px;padding:.75rem 1.25rem;box-shadow:var(--shadow-md);z-index:9999;align-items:center;gap:.75rem;font:500 13px var(--sans);color:#92400e;">
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="8" r="6.5"/><path d="M8 5v3.5l2 1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
  Sitzung läuft ab in <strong id="session-warn-timer">5:00</strong>
  &nbsp;<a href="/" style="color:#92400e;font-weight:700;text-decoration:underline;">Aktiv bleiben</a>
</div>
</body>
</html>
''';

// ── Login ─────────────────────────────────────────────────────────────────────

String renderLogin(String? error) => '''
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Anmelden – UserDesk</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{
      font-family:'Inter',system-ui,sans-serif;
      -webkit-font-smoothing:antialiased;
      min-height:100vh;display:flex;align-items:center;justify-content:center;
      background:#0f172a;
      background-image:
        radial-gradient(ellipse 80% 60% at 50% -5%, rgba(37,99,235,.4) 0%, transparent 60%),
        radial-gradient(ellipse 40% 40% at 80% 80%, rgba(59,130,246,.15) 0%, transparent 50%);
    }
    .wrap{width:380px;padding:1rem}
    .top{display:flex;align-items:center;gap:.8rem;justify-content:center;margin-bottom:2rem}
    .mark{
      width:40px;height:40px;border-radius:10px;
      background:linear-gradient(135deg,#2563eb,#3b82f6);
      display:flex;align-items:center;justify-content:center;
      font:700 13px 'Inter',sans-serif;color:#fff;letter-spacing:.04em;
      box-shadow:0 4px 16px rgba(37,99,235,.6);
    }
    .brandtitle{font:700 20px 'Inter';color:#fff;letter-spacing:.01em}
    .card{
      background:rgba(15,23,42,.92);
      border:1px solid rgba(255,255,255,.1);
      border-radius:18px;padding:2.25rem 2rem;
      box-shadow:0 32px 80px rgba(0,0,0,.6), 0 0 0 1px rgba(255,255,255,.05) inset;
      backdrop-filter:blur(12px);
    }
    .card-top{border-bottom:1px solid rgba(255,255,255,.07);margin-bottom:1.6rem;padding-bottom:1.35rem}
    h2{font:600 17px 'Inter';color:#fff;margin-bottom:.35rem}
    .sub{font:400 12px 'Inter';color:rgba(255,255,255,.38);letter-spacing:.01em}
    label{display:block;font:600 11px 'Inter';letter-spacing:.06em;text-transform:uppercase;color:rgba(255,255,255,.4);margin-bottom:.45rem}
    .field{margin-bottom:1rem}
    input{
      width:100%;padding:.7rem 1rem;
      border:1px solid rgba(255,255,255,.12);background:rgba(8,10,16,.6);
      border-radius:9px;font:400 14px 'Inter';color:#fff;outline:none;
      transition:border-color .15s,box-shadow .15s;
    }
    input:focus{border-color:#3b82f6;box-shadow:0 0 0 3px rgba(37,99,235,.28)}
    input::placeholder{color:rgba(255,255,255,.22)}
    button{
      width:100%;padding:.8rem;margin-top:.25rem;
      background:linear-gradient(135deg,#2563eb,#3b82f6);color:#fff;
      border:none;border-radius:9px;font:600 14px 'Inter';cursor:pointer;
      box-shadow:0 2px 10px rgba(37,99,235,.5);
      transition:opacity .13s,box-shadow .13s,transform .13s;
    }
    button:hover{opacity:.92;box-shadow:0 4px 18px rgba(37,99,235,.65);transform:translateY(-1px)}
    button:active{transform:none}
    .error{
      display:flex;align-items:center;gap:.55rem;
      background:rgba(192,40,42,.15);color:#f3a3a4;
      border:1px solid rgba(192,40,42,.35);border-radius:9px;
      padding:.7rem 1rem;font:400 13px 'Inter';margin-bottom:1.1rem;
    }
    .foot{text-align:center;font:400 11px 'Inter';color:rgba(255,255,255,.2);margin-top:1.35rem;letter-spacing:.03em}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <div class="mark">AD</div>
      <div class="brandtitle">UserDesk</div>
    </div>
    <div class="card">
      <div class="card-top">
        <h2>Anmelden</h2>
        <p class="sub">Nur für autorisierte Administratoren</p>
      </div>
      ${error != null ? '<div class="error"><svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="8" cy="8" r="6.5"/><line x1="8" y1="5" x2="8" y2="8.5" stroke-linecap="round"/><circle cx="8" cy="11" r=".5" fill="currentColor" stroke="none"/></svg>$error</div>' : ''}
      <form method="post" action="/login">
        <div class="field">
          <label>Benutzername</label>
          <input type="text" name="username" autofocus autocomplete="username" placeholder="domain\\username">
        </div>
        <div class="field">
          <label>Passwort</label>
          <input type="password" name="password" autocomplete="current-password" placeholder="••••••••">
        </div>
        <button type="submit">Anmelden →</button>
      </form>
    </div>
    <div class="foot">$_appDomain · Active Directory · TLS 636</div>
  </div>
</body></html>
''';

// ── Index ─────────────────────────────────────────────────────────────────────

String renderIndex(String username, {List<String> searchHistory = const []}) => _layout(username, 'Suche', '''
  <div style="background:linear-gradient(135deg,#1a1d27 0%,#252a3d 100%);border-radius:14px;padding:2rem 2rem 1.75rem;margin-bottom:1.5rem;position:relative;overflow:hidden;">
    <div style="position:absolute;top:-30px;right:-30px;width:180px;height:180px;border-radius:50%;background:radial-gradient(circle,rgba(37,99,235,.25) 0%,transparent 70%);pointer-events:none;"></div>
    <div style="position:absolute;bottom:-40px;left:30%;width:220px;height:220px;border-radius:50%;background:radial-gradient(circle,rgba(124,92,219,.15) 0%,transparent 70%);pointer-events:none;"></div>
    <p style="font:600 10px var(--mono);letter-spacing:.12em;text-transform:uppercase;color:rgba(255,255,255,.35);margin-bottom:.6rem;">Active Directory</p>
    <h1 style="font:700 22px var(--sans);color:#fff;margin-bottom:.4rem;line-height:1.2;">Benutzersuche</h1>
    <p style="font-size:.875rem;color:rgba(255,255,255,.45);margin-bottom:1.5rem;">Name, Benutzername oder E-Mail-Adresse eingeben</p>
    <form class="search-box" action="/search" method="get" style="position:relative;z-index:1;">
      <input type="text" name="q" placeholder="z.B. max.muster oder muster@$_appDomain" autofocus
             style="background:rgba(255,255,255,.07);border-color:rgba(255,255,255,.12);color:#fff;font-size:.95rem;padding:.75rem 1.1rem;">
      <button type="submit" class="btn btn-primary" style="padding:.75rem 1.25rem;font-size:.9rem;">Suchen</button>
    </form>
    ${_searchHistoryPills(searchHistory, prominent: true)}
  </div>
  <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:1rem;">
    <a href="/groups" class="surf" style="text-decoration:none;display:flex;align-items:center;gap:.85rem;background:var(--surface);border:1px solid var(--gray-200);border-radius:10px;padding:1rem 1.1rem;transition:box-shadow .15s,transform .15s;" onmouseover="this.style.boxShadow='var(--shadow-md)';this.style.transform='translateY(-2px)'" onmouseout="this.style.boxShadow='';this.style.transform=''">
      <div style="width:38px;height:38px;border-radius:9px;background:var(--blue-lt);color:var(--blue);display:flex;align-items:center;justify-content:center;flex-shrink:0;">
        <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="5.5" cy="6" r="2.6"/><circle cx="11" cy="6.6" r="2.1"/><path d="M1.7 13c0-2.2 1.7-3.6 3.8-3.6s3.8 1.4 3.8 3.6"/></svg>
      </div>
      <div><div style="font:600 13px var(--sans);color:var(--gray-800);">Gruppen</div><div style="font-size:.78rem;color:var(--gray-400);margin-top:1px;">Gruppen durchsuchen</div></div>
    </a>
    <a href="/ou" class="surf" style="text-decoration:none;display:flex;align-items:center;gap:.85rem;background:var(--surface);border:1px solid var(--gray-200);border-radius:10px;padding:1rem 1.1rem;transition:box-shadow .15s,transform .15s;" onmouseover="this.style.boxShadow='var(--shadow-md)';this.style.transform='translateY(-2px)'" onmouseout="this.style.boxShadow='';this.style.transform=''">
      <div style="width:38px;height:38px;border-radius:9px;background:#eff6ff;color:#2563eb;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
        <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2" y="2.5" width="5" height="4" rx="1"/><rect x="8.5" y="9.5" width="5.5" height="4" rx="1"/><path d="M4.5 6.5v3.5h6"/></svg>
      </div>
      <div><div style="font:600 13px var(--sans);color:var(--gray-800);">OU-Browser</div><div style="font-size:.78rem;color:var(--gray-400);margin-top:1px;">Verzeichnisstruktur</div></div>
    </a>
    <a href="/audit" class="surf" style="text-decoration:none;display:flex;align-items:center;gap:.85rem;background:var(--surface);border:1px solid var(--gray-200);border-radius:10px;padding:1rem 1.1rem;transition:box-shadow .15s,transform .15s;" onmouseover="this.style.boxShadow='var(--shadow-md)';this.style.transform='translateY(-2px)'" onmouseout="this.style.boxShadow='';this.style.transform=''">
      <div style="width:38px;height:38px;border-radius:9px;background:#f0f5f2;color:#1a7a4d;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
        <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><line x1="3" y1="4.5" x2="13" y2="4.5"/><line x1="3" y1="8" x2="13" y2="8"/><line x1="3" y1="11.5" x2="9.5" y2="11.5"/></svg>
      </div>
      <div><div style="font:600 13px var(--sans);color:var(--gray-800);">Änderungs-Log</div><div style="font-size:.78rem;color:var(--gray-400);margin-top:1px;">Aktivitätsprotokoll</div></div>
    </a>
  </div>
''', active: 'search');

// ── Donut Chart (pure SVG, server-rendered) ───────────────────────────────────

String _donutChart(int total, int active, int disabled, int locked) {
  const cx = 80.0, cy = 80.0, outerR = 65.0, innerR = 40.0;

  if (total == 0) {
    return '<svg viewBox="0 0 160 160" width="160" height="160">'
        '<circle cx="$cx" cy="$cy" r="$outerR" fill="var(--gray-100)"/>'
        '<circle cx="$cx" cy="$cy" r="$innerR" fill="white"/>'
        '<text x="$cx" y="${cy + 5}" text-anchor="middle" fill="var(--gray-300)" font-size="12">Keine Daten</text>'
        '</svg>';
  }

  String f(double v) => v.toStringAsFixed(2);

  String makeArc(double startDeg, double endDeg, String color) {
    final s = (startDeg - 90) * pi / 180;
    final e = (endDeg - 90) * pi / 180;
    final large = (endDeg - startDeg) > 180 ? 1 : 0;
    final x1 = cx + outerR * cos(s);
    final y1 = cy + outerR * sin(s);
    final x2 = cx + outerR * cos(e);
    final y2 = cy + outerR * sin(e);
    final x3 = cx + innerR * cos(e);
    final y3 = cy + innerR * sin(e);
    final x4 = cx + innerR * cos(s);
    final y4 = cy + innerR * sin(s);
    return '<path d="M ${f(x1)} ${f(y1)} A $outerR $outerR 0 $large 1 ${f(x2)} ${f(y2)} '
        'L ${f(x3)} ${f(y3)} A $innerR $innerR 0 $large 0 ${f(x4)} ${f(y4)} Z" '
        'fill="$color" stroke="white" stroke-width="2.5"/>';
  }

  final slices = [(active, '#22c55e'), (disabled, '#ef4444'), (locked, '#f59e0b')];
  final paths = <String>[];
  var angle = 0.0;
  for (final (count, color) in slices) {
    if (count <= 0) continue;
    final sweep = (count / total) * 360;
    // Avoid a full 360° arc (SVG can't draw that) — cap at 359.99
    final end = sweep >= 360 ? angle + 359.99 : angle + sweep;
    paths.add(makeArc(angle, end, color));
    angle += sweep;
  }

  return '<svg viewBox="0 0 160 160" width="160" height="160">'
      '${paths.join()}'
      '<circle cx="$cx" cy="$cy" r="$innerR" fill="white"/>'
      '<text x="$cx" y="${cy - 7}" text-anchor="middle" fill="var(--gray-700)" '
      'font-size="18" font-weight="700" font-family="var(--sans)">$total</text>'
      '<text x="$cx" y="${cy + 10}" text-anchor="middle" fill="var(--gray-400)" '
      'font-size="10" font-family="var(--sans)">User</text>'
      '</svg>';
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

String renderDashboard(String username, Map<String, int> stats, List<AuditEntry> recent,
    {List<Favorite> favorites = const [], String csrfToken = ''}) {
  final total = stats['total'] ?? 0;
  final disabled = stats['disabled'] ?? 0;
  final locked = stats['locked'] ?? 0;
  final active = total - disabled;

  String statCard(String label, int value, String color, String bgColor, String link, String svgPath) => '''
    <a href="$link" class="surf" style="text-decoration:none;background:var(--surface);border:1px solid var(--gray-200);border-radius:var(--radius);padding:1.1rem 1.25rem;display:flex;align-items:center;gap:1rem;box-shadow:var(--shadow-sm);transition:box-shadow .15s,transform .15s;" onmouseover="this.style.boxShadow='var(--shadow-md)';this.style.transform='translateY(-2px)'" onmouseout="this.style.boxShadow='var(--shadow-sm)';this.style.transform=''">
      <div style="width:44px;height:44px;border-radius:10px;background:$bgColor;color:$color;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
        $svgPath
      </div>
      <div>
        <div class="surf-title" style="font:700 22px var(--sans);color:var(--gray-800);">$value</div>
        <div class="surf-sub" style="font:500 12px var(--sans);color:var(--gray-400);margin-top:1px;">$label</div>
      </div>
    </a>''';

  final recentRows = recent.map((e) {
    final ts = e.timestamp;
    final time = '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')} · '
        '${ts.day.toString().padLeft(2,'0')}.${ts.month.toString().padLeft(2,'0')}.${ts.year}';
    final cnPart = e.targetDn.isNotEmpty ? _extractCn(e.targetDn) : '–';
    return '<tr>'
        '<td style="white-space:nowrap;font-size:.75rem;color:var(--gray-400);">$time</td>'
        '<td style="font-size:.85rem;"><strong>${_esc(e.actor)}</strong></td>'
        '<td style="font-size:.85rem;">${_esc(e.action)}</td>'
        '<td style="font-size:.82rem;color:var(--gray-500);">$cnPart</td>'
        '</tr>';
  }).join('\n');

  final chart = _donutChart(total, active, disabled, locked);
  final disabledPercent = total > 0 ? (disabled / total * 100).round() : 0;
  final lockedPercent = total > 0 ? (locked / total * 100).round() : 0;
  final activePercent = total > 0 ? (100 - disabledPercent - lockedPercent).clamp(0, 100) : 0;

  String legendRow(String color, String label, int count, int pct) =>
      '<div style="display:flex;align-items:center;gap:.6rem;padding:.45rem 0;border-bottom:1px solid var(--gray-100);">'
      '<span style="width:10px;height:10px;border-radius:3px;background:$color;flex-shrink:0;display:inline-block;"></span>'
      '<span style="font:500 13px var(--sans);color:var(--gray-600);flex:1;">$label</span>'
      '<span style="font:600 13px var(--mono);color:var(--gray-800);">$count</span>'
      '<span style="font:400 11px var(--mono);color:var(--gray-400);width:34px;text-align:right;">$pct%</span>'
      '</div>';

  return _layout(username, 'Dashboard', '''
    <div style="background:linear-gradient(135deg,#1a1d27 0%,#252a3d 100%);border-radius:14px;padding:2rem 2rem 1.75rem;margin-bottom:1.5rem;position:relative;overflow:hidden;">
      <div style="position:absolute;top:-30px;right:-30px;width:180px;height:180px;border-radius:50%;background:radial-gradient(circle,rgba(37,99,235,.25) 0%,transparent 70%);pointer-events:none;"></div>
      <div style="position:absolute;bottom:-40px;left:30%;width:220px;height:220px;border-radius:50%;background:radial-gradient(circle,rgba(124,92,219,.15) 0%,transparent 70%);pointer-events:none;"></div>
      <div style="position:absolute;top:1.1rem;right:1.25rem;display:flex;flex-direction:column;align-items:flex-end;gap:.3rem;">
        <div style="display:flex;align-items:center;gap:.4rem;font:500 10px var(--mono);color:rgba(255,255,255,.28);">
          <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="8" cy="8" r="5.5"/><path d="M8 5v3.5l2 1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <span id="refresh-timer">2:00</span>
          <a id="refresh-now" href="#" style="color:rgba(255,255,255,.35);text-decoration:none;border:1px solid rgba(255,255,255,.12);border-radius:4px;padding:.1rem .35rem;font:500 9px var(--mono);transition:all .12s;" onmouseover="this.style.color='#fff';this.style.borderColor='rgba(255,255,255,.4)'" onmouseout="this.style.color='rgba(255,255,255,.35)';this.style.borderColor='rgba(255,255,255,.12)'">↺</a>
        </div>
        <div style="width:90px;height:2px;background:rgba(255,255,255,.1);border-radius:1px;overflow:hidden;">
          <div id="refresh-bar" style="height:100%;width:100%;background:rgba(37,99,235,.6);border-radius:1px;transition:width 1s linear;"></div>
        </div>
      </div>
      <p style="font:600 10px var(--mono);letter-spacing:.12em;text-transform:uppercase;color:rgba(255,255,255,.35);margin-bottom:.6rem;">Active Directory</p>
      <h1 style="font:700 22px var(--sans);color:#fff;margin-bottom:.4rem;line-height:1.2;">Benutzersuche</h1>
      <p style="font-size:.875rem;color:rgba(255,255,255,.45);margin-bottom:1.5rem;">Name, Benutzername oder E-Mail-Adresse eingeben</p>
      <form class="search-box" action="/search" method="get" style="position:relative;z-index:1;">
        <input type="text" name="q" placeholder="z.B. max.muster oder muster@$_appDomain" autofocus
               style="background:rgba(255,255,255,.07);border-color:rgba(255,255,255,.12);color:#fff;font-size:.95rem;padding:.75rem 1.1rem;">
        <button type="submit" class="btn btn-primary" style="padding:.75rem 1.25rem;font-size:.9rem;">Suchen</button>
      </form>
    </div>

    <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:1rem;margin-bottom:1.5rem;">
      ${statCard('Total User', total, 'var(--blue)', 'var(--blue-lt)', '/search', '<svg width="20" height="20" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="5.5" r="2.8"/><path d="M2.5 14c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/></svg>')}
      ${statCard('Aktiv', active, '#166539', 'var(--green-lt)', '/search', '<svg width="20" height="20" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M3 8.5l3.5 3.5 6.5-7" stroke-linecap="round" stroke-linejoin="round"/></svg>')}
      ${statCard('Deaktiviert', disabled, 'var(--red)', 'var(--red-lt)', '/users/disabled', '<svg width="20" height="20" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="8" cy="8" r="5.5"/><line x1="4.5" y1="11.5" x2="11.5" y2="4.5" stroke-linecap="round"/></svg>')}
      ${statCard('Gesperrt', locked, 'var(--amber)', 'var(--amber-lt)', '/users/locked', '<svg width="20" height="20" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="4" y="7.5" width="8" height="6.5" rx="1.5"/><path d="M5.5 7.5V5.5a2.5 2.5 0 0 1 5 0v2" stroke-linecap="round"/></svg>')}
    </div>

    <div style="display:grid;grid-template-columns:240px 1fr 1fr;gap:1rem;margin-bottom:1.5rem;align-items:start;">

      <!-- Donut Chart -->
      <div class="card card-pad" style="display:flex;flex-direction:column;align-items:center;gap:1rem;">
        <div class="card-section-title" style="align-self:flex-start;">Verteilung</div>
        <div style="position:relative;display:flex;align-items:center;justify-content:center;">
          $chart
        </div>
        <div style="width:100%;display:flex;flex-direction:column;gap:0;">
          ${legendRow('#22c55e', 'Aktiv', active, activePercent)}
          ${legendRow('#ef4444', 'Deaktiviert', disabled, disabledPercent)}
          ${legendRow('#f59e0b', 'Gesperrt', locked, lockedPercent)}
        </div>
      </div>

      <!-- Schnellansichten -->
      <div class="card card-pad">
        <div class="card-section-title">Schnellansichten</div>
        <div style="display:flex;flex-direction:column;gap:.5rem;">
          <a href="/users/locked" style="display:flex;align-items:center;gap:.85rem;padding:.7rem .9rem;background:var(--amber-lt);border:1px solid #fcd34d;border-radius:8px;text-decoration:none;transition:opacity .12s;" onmouseover="this.style.opacity='.8'" onmouseout="this.style.opacity='1'">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#92400e" stroke-width="1.6"><rect x="4" y="7.5" width="8" height="6.5" rx="1.5"/><path d="M5.5 7.5V5.5a2.5 2.5 0 0 1 5 0v2" stroke-linecap="round"/></svg>
            <span style="font:500 13px var(--sans);color:var(--amber);">Gesperrte User</span>
            <span style="margin-left:auto;font:700 13px var(--mono);color:var(--amber);">$locked</span>
          </a>
          <a href="/users/disabled" style="display:flex;align-items:center;gap:.85rem;padding:.7rem .9rem;background:var(--red-lt);border:1px solid #f5c0c0;border-radius:8px;text-decoration:none;transition:opacity .12s;" onmouseover="this.style.opacity='.8'" onmouseout="this.style.opacity='1'">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="var(--red)" stroke-width="1.6"><circle cx="8" cy="8" r="5.5"/><line x1="4.5" y1="11.5" x2="11.5" y2="4.5" stroke-linecap="round"/></svg>
            <span style="font:500 13px var(--sans);color:var(--red);">Deaktivierte User</span>
            <span style="margin-left:auto;font:700 13px var(--mono);color:var(--red);">$disabled</span>
          </a>
          <a href="/users/pw-expiring" style="display:flex;align-items:center;gap:.85rem;padding:.7rem .9rem;background:var(--blue-lt);border:1px solid #93c5fd;border-radius:8px;text-decoration:none;transition:opacity .12s;" onmouseover="this.style.opacity='.8'" onmouseout="this.style.opacity='1'">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="var(--blue)" stroke-width="1.6"><circle cx="8" cy="8" r="5.5"/><path d="M8 5v3.5l2 1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span style="font:500 13px var(--sans);color:var(--blue);">PW läuft bald ab</span>
          </a>
          <a href="/groups" style="display:flex;align-items:center;gap:.85rem;padding:.7rem .9rem;background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;text-decoration:none;transition:opacity .12s;" onmouseover="this.style.opacity='.8'" onmouseout="this.style.opacity='1'">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#166534" stroke-width="1.6"><circle cx="5.5" cy="5.5" r="2"/><circle cx="10.5" cy="5.5" r="2"/><path d="M1.5 13c0-2 1.8-3.5 4-3.5M14.5 13c0-2-1.8-3.5-4-3.5M8 13c0-2-1.2-3-3-3" stroke-linecap="round"/></svg>
            <span style="font:500 13px var(--sans);color:#166534;">Gruppen verwalten</span>
          </a>
          <a href="/ou" style="display:flex;align-items:center;gap:.85rem;padding:.7rem .9rem;background:#f5f3ff;border:1px solid #ddd6fe;border-radius:8px;text-decoration:none;transition:opacity .12s;" onmouseover="this.style.opacity='.8'" onmouseout="this.style.opacity='1'">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#6d28d9" stroke-width="1.6"><rect x="2" y="2" width="5" height="4" rx="1"/><rect x="9" y="2" width="5" height="4" rx="1"/><rect x="5.5" y="10" width="5" height="4" rx="1"/><path d="M4.5 6v1.5h7V6M8 7.5V10" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span style="font:500 13px var(--sans);color:#6d28d9;">OU-Browser</span>
          </a>
        </div>
      </div>

      <!-- Letzte Aktionen -->
      <div class="card">
        <div class="card-pad" style="padding-bottom:.5rem;">
          <div class="card-section-title">Letzte Aktionen</div>
        </div>
        ${recent.isEmpty
          ? '<div style="padding:1rem 1.5rem;font-size:.85rem;color:var(--gray-400);">Noch keine Einträge.</div>'
          : '<table style="font-size:.82rem;"><thead><tr><th>Zeit</th><th>Benutzer</th><th>Aktion</th><th>Ziel</th></tr></thead><tbody>$recentRows</tbody></table>'}
        <div style="padding:.65rem 1.5rem;border-top:1px solid var(--gray-100);display:flex;align-items:center;gap:1rem;flex-wrap:wrap;">
          <a href="/audit" style="font-size:.82rem;color:var(--blue);text-decoration:none;">Alle Einträge →</a>
          <a href="/export/users" style="font-size:.82rem;color:var(--green);text-decoration:none;margin-left:auto;">User exportieren ↓</a>
        </div>
      </div>
    </div>
    ${favorites.isNotEmpty ? '''
    <div class="card card-pad" style="margin-bottom:1.5rem;">
      <div class="card-section-title" style="margin-bottom:.75rem;">Favoriten</div>
      <div style="display:flex;flex-wrap:wrap;gap:.5rem;">
        ${favorites.map((f) => '<a href="/user?dn=${Uri.encodeComponent(f.dn)}" style="display:inline-flex;align-items:center;gap:.4rem;padding:.35rem .75rem;background:var(--blue-lt);border:1px solid rgba(37,99,235,.25);border-radius:20px;text-decoration:none;font:500 .82rem var(--sans);color:var(--blue);transition:all .12s;" onmouseover="this.style.background=\'rgba(37,99,235,.2)\'" onmouseout="this.style.background=\'var(--blue-lt)\'">⭐ ${_esc(f.name)}</a>').join('\n')}
      </div>
    </div>''' : ''}

    <script>
    (function() {
      var total = 120, remaining = total;
      var timerEl = document.getElementById('refresh-timer');
      var barEl   = document.getElementById('refresh-bar');
      function fmt(s) {
        var m = Math.floor(s / 60), sec = s % 60;
        return m + ':' + (sec < 10 ? '0' : '') + sec;
      }
      function tick() {
        remaining--;
        if (remaining <= 0) { location.reload(); return; }
        if (timerEl) timerEl.textContent = fmt(remaining);
        if (barEl)   barEl.style.width = (remaining / total * 100) + '%';
        setTimeout(tick, 1000);
      }
      setTimeout(tick, 1000);
      var manualBtn = document.getElementById('refresh-now');
      if (manualBtn) manualBtn.addEventListener('click', function(e) {
        e.preventDefault(); location.reload();
      });
    })();
    </script>
  ''', active: 'dashboard', csrfToken: csrfToken);
}

// ── Schnellansichten ──────────────────────────────────────────────────────────

String renderQuickUsers(String username, String title, String subtitle,
    List<Map<String, dynamic>> users, {String? extraCol, String backHref = '/'}) {
  final isLocked = extraCol == 'Entsperren';
  final isDisabled = extraCol == 'Aktivieren';
  final isPwExpiring = extraCol == 'Tage';

  final rows = users.map((u) {
    final dn = u['dn'] ?? '';
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final mail = _esc(u['mail'] ?? '–');
    final dept = _esc(u['department'] ?? '–');
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';

    String actionCell = '';
    if (isLocked) {
      actionCell = '''
        <form method="post" action="/account/unlock" style="margin:0;display:inline;">
          <input type="hidden" name="dn" value="${_esc(dn)}">
          <input type="hidden" name="back" value="">
          <button type="submit" class="btn btn-sm" style="background:#fef3c7;color:#92400e;border:1px solid #fcd34d;">🔓 Entsperren</button>
        </form>''';
    } else if (isDisabled) {
      final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
      actionCell = '''
        <form method="post" action="/account/toggle" style="margin:0;display:inline;">
          <input type="hidden" name="dn" value="${_esc(dn)}">
          <input type="hidden" name="uac" value="$uac">
          <input type="hidden" name="action" value="enable">
          <input type="hidden" name="back" value="">
          <button type="submit" class="btn btn-success btn-xs">✓ Aktivieren</button>
        </form>''';
    } else if (isPwExpiring) {
      final daysLeft = u['_daysLeft'] ?? 0;
      actionCell = '<span class="badge ${daysLeft <= 3 ? 'badge-disabled' : 'badge-locked'}">$daysLeft Tage</span>';
    }

    return '<tr>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;"><strong>$cn</strong></td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">$sam</td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">$mail</td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">$dept</td>'
        '${extraCol != null ? '<td onclick="event.stopPropagation()">$actionCell</td>' : ''}'
        '</tr>';
  }).join('\n');

  final activeNav = isLocked ? 'locked' : (isDisabled ? 'disabled' : 'pw-expiring');

  return _layout(username, title, '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="$backHref" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">$title</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">$subtitle</p>
      </div>
    </div>
    <div class="card">
      ${users.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine Benutzer gefunden.</em></div>'
        : '''
        <div class="card-pad" style="padding-bottom:.5rem;">
          <span style="font:500 .82rem var(--sans);color:var(--gray-500);">${users.length} Benutzer</span>
        </div>
        <div class="table-wrap">
        <table class="result-table">
          <thead><tr>
            <th>Name</th><th>Benutzername</th><th>E-Mail</th><th>Abteilung</th>
            ${extraCol != null ? '<th>$extraCol</th>' : ''}
          </tr></thead>
          <tbody>$rows</tbody>
        </table>
        </div>'''}
    </div>
  ''', active: activeNav);
}

// ── Suchergebnisse (kompakte Liste) ──────────────────────────────────────────

String renderResults(String username, String query, List<Map<String, dynamic>> results, {List<String> searchHistory = const []}) {
  final rows = results.map((u) {
    final dn = u['dn'] ?? '';
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final mail = _esc(u['mail'] ?? '–');
    final dept = _esc(u['department'] ?? '–');
    final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
    final lockoutTime = int.tryParse(u['lockoutTime']?.toString() ?? '0') ?? 0;
    final disabled = (uac & 2) != 0;
    final locked = lockoutTime > 0;
    final statusAttr = locked ? 'locked' : (disabled ? 'disabled' : 'active');
    final badge = locked
        ? '<span class="badge badge-locked">Gesperrt</span>'
        : disabled
            ? '<span class="badge badge-disabled">Inaktiv</span>'
            : '<span class="badge badge-active">Aktiv</span>';
    final desc = _esc(u['description'] ?? '');
    final photo = u['jpegPhoto'] as String?;
    final initial = cn.isNotEmpty ? cn[0].toUpperCase() : '?';
    final avatar = photo != null && photo.isNotEmpty
        ? '<img class="avatar-sm" src="$photo">'
        : '<div class="avatar-placeholder">$initial</div>';
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(query)}';

    // Feature 3: Inline action buttons
    final unlockBtn = locked ? '''
      <form method="post" action="/account/unlock" style="margin:0;display:inline;" onclick="event.stopPropagation()">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="back" value="${_esc(query)}">
        <button type="submit" class="btn btn-xs" style="background:#fef3c7;color:#92400e;border:1px solid #fcd34d;" title="Entsperren">🔓</button>
      </form>''' : '';
    final toggleBtn = '''
      <form method="post" action="/account/toggle" style="margin:0;display:inline;" onclick="event.stopPropagation()">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="uac" value="$uac">
        <input type="hidden" name="action" value="${disabled ? 'enable' : 'disable'}">
        <input type="hidden" name="back" value="${_esc(query)}">
        <button type="submit" class="btn btn-xs ${disabled ? 'btn-success' : 'btn-danger'}" title="${disabled ? 'Aktivieren' : 'Deaktivieren'}">${disabled ? '✓' : '⊘'}</button>
      </form>''';

    return '''
    <tr data-status="$statusAttr">
      <td onclick="event.stopPropagation()" style="width:36px;">
        <input type="checkbox" class="user-check" value="${_esc(dn)}" onchange="updateBulk()">
      </td>
      <td onclick="location.href='$detailUrl'" style="cursor:pointer;">$avatar</td>
      <td onclick="location.href='$detailUrl'" style="cursor:pointer;"><strong>$cn</strong>${desc.isNotEmpty ? '<br><span style="font-size:.75rem;color:var(--gray-400);font-weight:400;">$desc</span>' : ''}</td>
      <td onclick="location.href='$detailUrl'" style="cursor:pointer;">$sam</td>
      <td onclick="location.href='$detailUrl'" style="cursor:pointer;">$mail</td>
      <td onclick="location.href='$detailUrl'" style="cursor:pointer;">$dept</td>
      <td onclick="location.href='$detailUrl'" style="cursor:pointer;">$badge</td>
      <td onclick="event.stopPropagation()">$unlockBtn$toggleBtn</td>
    </tr>''';
  }).join('\n');

  return _layout(username, 'Suchergebnisse', '''
    <style>
      .filter-pill { display:inline-flex; padding:.28rem .7rem; border-radius:20px; font-size:.78rem; font-weight:500; cursor:pointer; border:1px solid var(--gray-200); background:white; transition:all .12s; }
      .filter-pill.active { background:var(--blue); color:white; border-color:var(--blue); }
    </style>
    <div class="card card-pad" style="margin-bottom:1rem;background:linear-gradient(135deg,#1a1d27 0%,#252a3d 100%);">
      <form class="search-box" action="/search" method="get">
        <input type="text" name="q" value="${_esc(query)}" autofocus
               style="background:rgba(255,255,255,.07);border-color:rgba(255,255,255,.12);color:#fff;">
        <button type="submit" class="btn btn-primary">Suchen</button>
        ${results.isNotEmpty ? '<a href="/export/search?q=${Uri.encodeComponent(query)}" class="btn btn-ghost" style="color:rgba(255,255,255,.6);border-color:rgba(255,255,255,.15);background:rgba(255,255,255,.06);">⬇ CSV</a>' : ''}
      </form>
      ${_searchHistoryPills(searchHistory)}
    </div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:.75rem;flex-wrap:wrap;gap:.5rem;">
      <p style="font-size:.82rem;color:var(--gray-400);">${results.length} Benutzer${query.isNotEmpty ? ' für „${_esc(query)}"' : ' · alphabetisch'}</p>
      <div style="display:flex;gap:.35rem;">
        <span class="filter-pill active" data-filter="all" onclick="filterStatus('all')">Alle</span>
        <span class="filter-pill" data-filter="active" onclick="filterStatus('active')">Aktiv</span>
        <span class="filter-pill" data-filter="disabled" onclick="filterStatus('disabled')">Deaktiviert</span>
        <span class="filter-pill" data-filter="locked" onclick="filterStatus('locked')">Gesperrt</span>
      </div>
    </div>
    <div class="card">
      <div class="table-wrap">
      <table class="result-table">
        <thead><tr>
          <th><input type="checkbox" id="check-all" onchange="toggleAll(this)" title="Alle auswählen"></th>
          <th></th>
          <th onclick="sortTable(this,2)" style="cursor:pointer;user-select:none;">Name ▲▼</th>
          <th onclick="sortTable(this,3)" style="cursor:pointer;user-select:none;">Benutzername ▲▼</th>
          <th onclick="sortTable(this,4)" style="cursor:pointer;user-select:none;">E-Mail ▲▼</th>
          <th onclick="sortTable(this,5)" style="cursor:pointer;user-select:none;">Abteilung ▲▼</th>
          <th onclick="sortTable(this,6)" style="cursor:pointer;user-select:none;">Status ▲▼</th>
          <th>Aktionen</th>
        </tr></thead>
        <tbody>$rows</tbody>
      </table>
      </div>
    </div>
    <!-- Bulk-Action-Bar -->
    <div id="bulk-bar" style="display:none;position:fixed;bottom:1.5rem;left:50%;transform:translateX(-50%);background:var(--navy);color:white;padding:.75rem 1.25rem;border-radius:10px;box-shadow:0 4px 20px rgba(0,0,0,.3);align-items:center;gap:.75rem;z-index:200;flex-wrap:wrap;">
      <span id="bulk-count" style="font-size:.85rem;white-space:nowrap;"></span>
      <form method="post" action="/bulk/group/add" style="display:flex;gap:.5rem;align-items:center;margin:0;">
        <input type="hidden" name="back" value="${_esc(query)}">
        <input type="hidden" name="user_dns" id="bulk-dns">
        <input type="text" name="group_name" placeholder="Gruppenname..." required
               style="padding:.35rem .7rem;border:none;border-radius:6px;font-size:.85rem;width:180px;">
        <button type="submit" class="btn btn-primary btn-sm">+ Gruppe</button>
      </form>
      <form method="post" action="/bulk/unlock" style="display:flex;gap:.5rem;align-items:center;margin:0;">
        <input type="hidden" name="back" value="${_esc(query)}">
        <input type="hidden" name="user_dns" id="bulk-dns-unlock">
        <button type="submit" class="btn btn-sm" style="background:#fef3c7;color:#92400e;border:1px solid #fcd34d;">🔓 Entsperren</button>
      </form>
      <form method="post" action="/bulk/disable" style="display:flex;gap:.5rem;align-items:center;margin:0;">
        <input type="hidden" name="back" value="${_esc(query)}">
        <input type="hidden" name="user_dns" id="bulk-dns-disable">
        <input type="hidden" name="action" value="disable">
        <button type="submit" class="btn btn-danger btn-sm">⊘ Deaktivieren</button>
      </form>
      <form method="post" action="/bulk/disable" style="display:flex;gap:.5rem;align-items:center;margin:0;">
        <input type="hidden" name="back" value="${_esc(query)}">
        <input type="hidden" name="user_dns" id="bulk-dns-enable">
        <input type="hidden" name="action" value="enable">
        <button type="submit" class="btn btn-success btn-sm">✓ Aktivieren</button>
      </form>
    </div>
    <script>
    function updateBulk() {
      const checked = Array.from(document.querySelectorAll('.user-check:checked'));
      const bar = document.getElementById('bulk-bar');
      if (checked.length > 0) {
        bar.style.display = 'flex';
        document.getElementById('bulk-count').textContent = checked.length + ' ausgewählt';
        const dns = checked.map(c => c.value).join('\\n');
        document.getElementById('bulk-dns').value = dns;
        document.getElementById('bulk-dns-unlock').value = dns;
        document.getElementById('bulk-dns-disable').value = dns;
        document.getElementById('bulk-dns-enable').value = dns;
      } else {
        bar.style.display = 'none';
      }
    }
    function toggleAll(cb) {
      document.querySelectorAll('.user-check').forEach(c => { c.checked = cb.checked; });
      updateBulk();
    }
    function sortTable(th, col) {
      const tbody = th.closest('table').querySelector('tbody');
      const rows = Array.from(tbody.querySelectorAll('tr'));
      const asc = th.dataset.sort !== 'asc';
      th.closest('thead').querySelectorAll('th').forEach(h => delete h.dataset.sort);
      th.dataset.sort = asc ? 'asc' : 'desc';
      rows.sort((a, b) => {
        const av = a.cells[col]?.textContent.trim() ?? '';
        const bv = b.cells[col]?.textContent.trim() ?? '';
        return asc ? av.localeCompare(bv, 'de') : bv.localeCompare(av, 'de');
      });
      rows.forEach(r => tbody.appendChild(r));
    }
    function filterStatus(status) {
      document.querySelectorAll('.filter-pill').forEach(p => p.classList.toggle('active', p.dataset.filter === status));
      document.querySelectorAll('tbody tr[data-status]').forEach(r => {
        r.style.display = (!status || status === 'all' || r.dataset.status === status) ? '' : 'none';
      });
    }
    </script>
  ''', active: 'search');
}

// ── User Detail ───────────────────────────────────────────────────────────────

String renderUserDetail(String username, Map<String, dynamic> u, String back,
    {GroupClipboard? clipboard, int maxPwdAgeDays = 90,
     bool isOwnUser = false, bool readOnlySelf = false, bool isFavorite = false,
     Map<String, dynamic>? note}) {
  final dn = u['dn'] ?? '';
  final cn = _esc(u['cn'] ?? '–');
  final sam = _esc(u['sAMAccountName'] ?? '–');
  final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
  final disabled = (uac & 2) != 0;
  final lockoutTime = int.tryParse(u['lockoutTime']?.toString() ?? '0') ?? 0;
  final locked = lockoutTime > 0;
  final badge = disabled
      ? '<span class="badge badge-disabled">Deaktiviert</span>'
      : locked
          ? '<span class="badge" style="background:#fef3c7;color:#92400e;">Gesperrt</span>'
          : '<span class="badge badge-active">Aktiv</span>';
  final photo = u['jpegPhoto'] as String?;
  final initial = cn.isNotEmpty ? cn[0].toUpperCase() : '?';
  final avatarHtml = photo != null && photo.isNotEmpty
      ? '<img class="detail-avatar" id="photo-prev" src="$photo">'
      : '<div class="detail-avatar-ph" id="photo-prev">$initial</div>';
  final backUrl = back.isNotEmpty ? '/search?q=${Uri.encodeComponent(back)}' : '/';

  String field(String label, String attr, String val, String id) {
    final safeVal = _esc(val);
    return '''
    <div class="field-item">
      <div class="field-label">$label</div>
      <div class="field-val">
        ${val.isEmpty ? '<em>–</em>' : safeVal}
        <button class="edit-link" onclick="toggleEdit(this,'e-$id')">Bearbeiten</button>
      </div>
      <div class="inline-edit" id="e-$id">
        <form method="post" action="/modify">
          <input type="hidden" name="dn" value="${_esc(dn)}">
          <input type="hidden" name="attribute" value="$attr">
          <input type="hidden" name="back" value="${_esc(back)}">
          <input type="text" name="value" value="$safeVal" placeholder="Neuer Wert...">
          <button type="submit" class="btn btn-primary btn-sm">Speichern</button>
        </form>
      </div>
    </div>''';
  }

  final g = (String s) => u[s]?.toString() ?? '';
  final memberOf = (u['memberOf'] as List?)?.cast<String>() ?? [];
  final sortedGroups = [...memberOf]..sort((a, b) => _extractCn(a).compareTo(_extractCn(b)));

  // Gruppen-Tabelle
  final groupRows = sortedGroups.map((gdn) {
    final gName = _extractCn(gdn);
    final ou = _extractOu(gdn);
    return '''
    <tr>
      <td><strong>$gName</strong></td>
      <td style="color:var(--gray-400);font-size:.78rem;">$ou</td>
      <td>
        <form method="post" action="/group/remove" style="margin:0;display:inline">
          <input type="hidden" name="user_dn" value="${_esc(dn)}">
          <input type="hidden" name="group_dn" value="${_esc(gdn)}">
          <input type="hidden" name="back" value="${_esc(back)}">
          <button type="submit" class="btn btn-danger btn-sm">Entfernen</button>
        </form>
      </td>
    </tr>''';
  }).join('\n');

  // Clipboard-Banner
  final clipboardBanner = clipboard != null && clipboard.groupDns.isNotEmpty
      ? '''
      <div style="background:var(--blue-lt);border:1px solid #93c5fd;border-radius:8px;padding:.75rem 1rem;margin-bottom:.75rem;display:flex;align-items:center;justify-content:space-between;gap:1rem;flex-wrap:wrap;">
        <div>
          <strong style="font-size:.85rem;">📋 Clipboard:</strong>
          <span style="font-size:.82rem;color:var(--gray-600);"> ${clipboard.groupDns.length} Gruppen von <strong>${_esc(clipboard.sourceUsername)}</strong></span>
        </div>
        <form method="post" action="/groups/paste" style="margin:0">
          <input type="hidden" name="user_dn" value="${_esc(dn)}">
          <input type="hidden" name="back" value="${_esc(back)}">
          <button type="submit" class="btn btn-primary btn-sm">📋 Gruppen einfügen</button>
        </form>
      </div>'''
      : '';


  final pwdNeverExpires = (uac & 65536) != 0;
  final accountExpires = int.tryParse(u['accountExpires']?.toString() ?? '0') ?? 0;
  final accountExpiresStr = _formatAccountExpiry(accountExpires);

  final String successMsg;
  if (u['_msg'] == 'pw_ok') {
    successMsg = '<div class="alert alert-success" style="margin-bottom:.75rem;">✓ Passwort wurde erfolgreich zurückgesetzt.</div>';
  } else if (u['_msg'] == 'clone_ok') {
    successMsg = '<div class="alert alert-success" style="margin-bottom:.75rem;">✓ Benutzer wurde erfolgreich erstellt.</div>';
  } else if (u['_msg'] == 'note_ok') {
    successMsg = '<div class="alert alert-success" style="margin-bottom:.75rem;">✓ Notiz gespeichert.</div>';
  } else {
    successMsg = '';
  }

  final photoUpload = '''
    <form method="post" action="/photo" style="margin:0" id="photo-form">
      <input type="hidden" name="dn" value="${_esc(dn)}">
      <input type="hidden" name="back" value="${_esc(back)}">
      <input type="hidden" name="photo_b64" id="photo-b64">
      <label class="btn btn-ghost btn-sm" style="cursor:pointer;" title="Foto auswählen – wird automatisch hochgeladen">
        📷 Foto ändern
        <input type="file" accept="image/*" style="display:none" id="photo-file">
      </label>
    </form>
    ${photo != null && photo.isNotEmpty ? '''
    <form method="post" action="/photo/delete" style="margin:0">
      <input type="hidden" name="dn" value="${_esc(dn)}">
      <input type="hidden" name="back" value="${_esc(back)}">
      <button type="submit" class="btn btn-danger btn-sm" title="Foto löschen">🗑</button>
    </form>''' : ''}
  ''';

  final readOnlyActive = isOwnUser && readOnlySelf;

  final accountActions = readOnlyActive ? '' : '''
    <div style="display:flex;gap:.4rem;flex-wrap:wrap;align-items:center;margin-top:.6rem;">
      ${locked ? '''
      <form method="post" action="/account/unlock" style="margin:0">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <button type="submit" class="btn btn-sm" style="background:#fef3c7;color:#92400e;border:1px solid #fcd34d;">🔓 Entsperren</button>
      </form>''' : ''}
      <form method="post" action="/account/toggle" style="margin:0">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="uac" value="$uac">
        <input type="hidden" name="action" value="${disabled ? 'enable' : 'disable'}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <button type="submit" class="btn btn-sm ${disabled ? 'btn-success' : 'btn-danger'}">
          ${disabled ? '✓ Aktivieren' : '⊘ Deaktivieren'}
        </button>
      </form>
      <button class="btn btn-ghost btn-sm" onclick="toggleEdit(this,'pw-reset')">🔑 Passwort</button>
      <button class="btn btn-ghost btn-sm" onclick="toggleEdit(this,'acc-opts')">⚙ Optionen</button>
      <a href="/user/clone?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}" class="btn btn-ghost btn-sm">👤 Kopieren</a>
      <a href="/user/move?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}" class="btn btn-ghost btn-sm">📦 Verschieben</a>
      <a href="/user/compare?a=${Uri.encodeComponent(dn)}" class="btn btn-ghost btn-sm">⚖ Vergleichen</a>
      <a href="/user/groups-effective?dn=${Uri.encodeComponent(dn)}" class="btn btn-ghost btn-sm">🌐 Eff. Gruppen</a>
      <a href="/orgchart?dn=${Uri.encodeComponent(dn)}" class="btn btn-ghost btn-sm">🏢 Org-Chart</a>
      <form method="post" action="/favorite/toggle" style="margin:0;display:inline;">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="name" value="${_esc(u['cn'] ?? u['sAMAccountName'] ?? dn)}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <button type="submit" class="fav-btn ${isFavorite ? 'active' : ''}" title="${isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten hinzufügen'}">${isFavorite ? '⭐' : '☆'}</button>
      </form>
    </div>
    <div class="inline-edit" id="pw-reset" style="margin-top:.5rem;">
      ${_pwdStatusBox(g('pwdLastSet'), uac, maxPwdAgeDays)}
      <form method="post" action="/password/reset" style="display:flex;gap:.4rem;flex-wrap:wrap;align-items:center;">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <input type="text" name="password" id="pw-input-${_esc(dn).hashCode.abs()}" placeholder="Neues Passwort..." oninput="updatePwStrength(this.value)" style="flex:1;min-width:160px;padding:.3rem .6rem;border:1.5px solid var(--gray-200);border-radius:5px;font-size:.85rem;">
        <button type="button" class="btn btn-ghost btn-sm" onclick="applyGeneratedPassword('pw-input-${_esc(dn).hashCode.abs()}','pw-display-${_esc(dn).hashCode.abs()}')">Generieren</button>
        <button type="submit" id="pw-submit-btn" class="btn btn-primary btn-sm">Zurücksetzen</button>
      </form>
      <div style="margin-top:.4rem;">
        <div style="height:4px;background:var(--gray-200);border-radius:2px;overflow:hidden;width:180px;">
          <div id="pw-strength-bar" style="height:100%;width:0;border-radius:2px;transition:width .2s,background .2s;"></div>
        </div>
        <div id="pw-strength-tips" style="font:400 .72rem var(--sans);color:var(--gray-400);margin-top:.25rem;"></div>
      </div>
      <div id="pw-display-${_esc(dn).hashCode.abs()}-wrap" style="display:none;align-items:center;gap:.5rem;margin-top:.4rem;padding:.35rem .6rem;background:var(--gray-50);border:1px solid var(--gray-200);border-radius:6px;">
        <span style="font:600 .82rem var(--mono);color:var(--gray-800);" id="pw-display-${_esc(dn).hashCode.abs()}"></span>
        <button type="button" class="btn btn-ghost btn-xs" onclick="copyToClipboard(document.getElementById('pw-display-${_esc(dn).hashCode.abs()}').textContent)">📋 Kopieren</button>
      </div>
      <script>
      (function(){
        var dispWrap = document.getElementById('pw-display-${_esc(dn).hashCode.abs()}-wrap');
        var dispEl = document.getElementById('pw-display-${_esc(dn).hashCode.abs()}');
        if(dispEl) { dispEl.parentElement.style.display = dispEl.textContent ? 'flex' : 'none'; }
        // Override applyGeneratedPassword to also show wrap
        var origFn = window.applyGeneratedPassword;
        window.applyGeneratedPassword = function(inputId, displayId) {
          origFn(inputId, displayId);
          var wrap = document.getElementById(displayId + '-wrap');
          if(wrap) wrap.style.display = 'flex';
        };
      })();
      </script>
    </div>
    <div class="inline-edit" id="acc-opts" style="margin-top:.5rem;padding:.75rem;background:var(--gray-50);border-radius:8px;border:1px solid var(--gray-200);">
      <div style="display:flex;flex-direction:column;gap:.6rem;">
        <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:.4rem;">
          <span style="font-size:.82rem;">Passwort bei nächster Anmeldung ändern erzwingen</span>
          <form method="post" action="/account/pwmustchange" style="margin:0">
            <input type="hidden" name="dn" value="${_esc(dn)}">
            <input type="hidden" name="back" value="${_esc(back)}">
            <button type="submit" class="btn btn-ghost btn-sm">Jetzt setzen</button>
          </form>
        </div>
        <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:.4rem;">
          <span style="font-size:.82rem;">Passwort läuft nie ab: <strong>${pwdNeverExpires ? 'Ein' : 'Aus'}</strong></span>
          <form method="post" action="/account/pwexpiry" style="margin:0">
            <input type="hidden" name="dn" value="${_esc(dn)}">
            <input type="hidden" name="uac" value="$uac">
            <input type="hidden" name="enable" value="${pwdNeverExpires ? '0' : '1'}">
            <input type="hidden" name="back" value="${_esc(back)}">
            <button type="submit" class="btn btn-ghost btn-sm">${pwdNeverExpires ? 'Deaktivieren' : 'Aktivieren'}</button>
          </form>
        </div>
        <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:.4rem;">
          <span style="font-size:.82rem;">Ablaufdatum: <strong>$accountExpiresStr</strong></span>
          <form method="post" action="/account/expiry" style="display:flex;gap:.3rem;align-items:center;margin:0">
            <input type="hidden" name="dn" value="${_esc(dn)}">
            <input type="hidden" name="back" value="${_esc(back)}">
            <input type="date" name="expiry" style="padding:.25rem .5rem;border:1.5px solid var(--gray-200);border-radius:5px;font-size:.82rem;" title="Leer lassen = kein Ablauf">
            <button type="submit" class="btn btn-ghost btn-sm">Setzen</button>
            ${accountExpires > 0 && accountExpires != 9223372036854775807 ? '''
            <button type="submit" class="btn btn-ghost btn-sm" onclick="this.previousElementSibling.previousElementSibling.value=''">Aufheben</button>''' : ''}
          </form>
        </div>
      </div>
    </div>
  ''';

  final readOnlyBanner = readOnlyActive
      ? '''<div style="display:flex;align-items:center;gap:.65rem;background:var(--amber-lt);border:1px solid #fcd34d;border-radius:8px;padding:.75rem 1rem;margin-bottom:.75rem;font-size:.875rem;color:var(--amber);">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="4" y="7" width="8" height="7" rx="1.5"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2" stroke-linecap="round"/></svg>
          <span><strong>Nur-Lesen aktiv:</strong> Dein eigener Account ist gegen Änderungen geschützt. <a href="/settings" style="color:var(--amber);font-weight:600;">Einstellungen</a></span>
        </div>'''
      : '';

  return _layout(username, cn, '''
    <div style="display:flex;align-items:center;gap:.6rem;margin-bottom:1rem;">
      <a href="$backUrl" class="btn btn-ghost btn-sm">← Zurück</a>
      <span style="font-size:.82rem;color:var(--gray-400);">$sam</span>
    </div>
    $successMsg
    $readOnlyBanner
    <div class="card">
      <div class="detail-header">
        <div style="display:flex;flex-direction:column;align-items:center;gap:.4rem;flex-shrink:0;">
          $avatarHtml
          <div style="display:flex;gap:.3rem;flex-wrap:wrap;justify-content:center;">
            $photoUpload
          </div>
        </div>
        <div style="flex:1;">
          <div class="detail-name">$cn $badge</div>
          <div class="detail-sub">${g('title')}${g('department').isNotEmpty ? ' · ${g('department')}' : ''}</div>
          <div class="dn-text">${_esc(dn)}</div>
          $accountActions
        </div>
      </div>

      <div class="field-grid">
        <div class="field-col">
          ${field('Vorname', 'givenName', g('givenName'), 'givenName')}
          ${field('Nachname', 'sn', g('sn'), 'sn')}
          ${field('Anzeigename', 'displayName', g('displayName'), 'displayName')}
          ${field('E-Mail', 'mail', g('mail'), 'mail')}
          ${field('Telefon', 'telephoneNumber', g('telephoneNumber'), 'phone')}
          ${field('Mobil', 'mobile', g('mobile'), 'mobile')}
        </div>
        <div class="field-col">
          ${field('Abteilung', 'department', g('department'), 'dept')}
          ${field('Titel / Position', 'title', g('title'), 'title')}
          ${field('Firma', 'company', g('company'), 'company')}
          ${field('Büro', 'physicalDeliveryOfficeName', g('physicalDeliveryOfficeName'), 'office')}
          ${field('Strasse', 'streetAddress', g('streetAddress'), 'street')}
          ${field('Ort', 'l', g('l'), 'city')}
          ${field('PLZ', 'postalCode', g('postalCode'), 'plz')}
          ${_floorplanBlock(g('physicalDeliveryOfficeName'), g('department'))}
        </div>
      </div>

      <div class="section">
        ${field('Beschreibung', 'description', g('description'), 'desc')}
      </div>

      <div class="section">
        <div class="section-title"><span>Account-Info</span></div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:.5rem 1.5rem;font-size:.85rem;">
          <div>
            <div class="field-label">Zuletzt angemeldet</div>
            <div>${_formatFileTime(g('lastLogonTimestamp'))}</div>
          </div>
          <div>
            <div class="field-label">Passwort gesetzt am</div>
            <div>${_formatFileTime(g('pwdLastSet'))}</div>
          </div>
          <div>
            <div class="field-label">Passwort läuft ab</div>
            <div>${_pwdExpiryInfo(g('pwdLastSet'), uac, maxPwdAgeDays)}</div>
          </div>
          <div>
            <div class="field-label">Account läuft ab</div>
            <div>$accountExpiresStr</div>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-title">
          <span>Gruppen (${memberOf.length})</span>
          <div style="display:flex;gap:.4rem;">
            ${memberOf.isNotEmpty ? '''
            <form method="post" action="/groups/copy" style="margin:0">
              <input type="hidden" name="user_dn" value="${_esc(dn)}">
              <input type="hidden" name="user_name" value="$sam">
              <input type="hidden" name="back" value="${_esc(back)}">
              <button type="submit" class="btn btn-ghost btn-sm" title="Gruppen in Zwischenablage kopieren">📋 Kopieren</button>
            </form>''' : ''}
          </div>
        </div>
        $clipboardBanner
        ${memberOf.isEmpty
          ? '<em style="color:var(--gray-400);font-size:.85rem;">Keine Gruppen</em>'
          : '''<table style="font-size:.85rem;">
              <thead><tr><th>Gruppe</th><th>Bereich / OU</th><th></th></tr></thead>
              <tbody>$groupRows</tbody>
            </table>'''}
        <form class="add-group-form" method="post" action="/group/add" style="margin-top:.9rem;">
          <input type="hidden" name="user_dn" value="${_esc(dn)}">
          <input type="hidden" name="back" value="${_esc(back)}">
          <input type="text" name="group_name" placeholder="Gruppenname suchen...">
          <button type="submit" class="btn btn-success btn-sm">+ Gruppe hinzufügen</button>
        </form>
      </div>

      <!-- Notizen -->
      <div class="section">
        <div class="section-title"><span>Notizen</span></div>
        <form method="post" action="/user/notes" style="display:flex;flex-direction:column;gap:.6rem;">
          <input type="hidden" name="dn" value="${_esc(dn)}">
          <input type="hidden" name="back" value="${_esc(back)}">
          <textarea name="text" rows="4" placeholder="Interne Notizen zu diesem Benutzer (nur für Admins sichtbar)..."
                    style="width:100%;padding:.55rem .85rem;border:1.5px solid var(--gray-200);border-radius:7px;font:400 .875rem var(--sans);resize:vertical;">${_esc(note?['text']?.toString() ?? '')}</textarea>
          ${note != null && (note['updatedAt'] as String? ?? '').isNotEmpty
            ? '<div style="font:400 .72rem var(--mono);color:var(--gray-400);">Zuletzt bearbeitet: ${_esc(note['updatedAt'] as String? ?? '')} von ${_esc(note['updatedBy'] as String? ?? '')}</div>'
            : ''}
          <div>
            <button type="submit" class="btn btn-ghost btn-sm">💾 Notiz speichern</button>
          </div>
        </form>
      </div>

    </div>
    <script>initPhotoUpload('photo-file','photo-prev','photo-b64','photo-form');</script>
  ''', active: 'search');
}

// ── Group Picker ──────────────────────────────────────────────────────────────

String renderGroupPicker(String username, String userDn, String back,
    List<Map<String, dynamic>> groups, String action) {
  final items = groups.map((g) {
    final cn = _esc(g['cn'] ?? '–');
    final gdn = _esc(g['dn'] ?? '');
    return '''
    <div class="picker-item">
      <div>
        <strong>$cn</strong>
        <div style="font-size:.72rem;color:var(--gray-400);">$gdn</div>
      </div>
      <form method="post" action="/group/add/confirm">
        <input type="hidden" name="user_dn" value="${_esc(userDn)}">
        <input type="hidden" name="group_dn" value="${_esc(g['dn'] ?? '')}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <button type="submit" class="btn btn-primary btn-sm">$action</button>
      </form>
    </div>''';
  }).join('\n');

  return _layout(username, 'Gruppe wählen', '''
    <div class="card card-pad">
      <p style="margin-bottom:1rem;font-weight:600;">Welche Gruppe?</p>
      <div class="picker-list">$items</div>
      <a href="javascript:history.back()" class="btn btn-ghost" style="margin-top:1rem;">← Zurück</a>
    </div>
  ''', active: 'search');
}

// ── Gruppen ───────────────────────────────────────────────────────────────────

String renderGroups(String username, String query, List<Map<String, dynamic>> groups,
    List<Map<String, dynamic>> ous) {
  final rows = groups.map((g) {
    final cn = _esc(g['cn'] ?? '–');
    final desc = _esc(g['description'] ?? '');
    final count = g['memberCount'] ?? 0;
    final gdn = g['dn'] ?? '';
    return '''
    <tr>
      <td><strong>$cn</strong>${desc.isNotEmpty ? '<br><span style="color:var(--gray-400);font-size:.78rem;">$desc</span>' : ''}</td>
      <td>$count</td>
      <td style="white-space:nowrap;">
        <a href="/groups/members?dn=${Uri.encodeComponent(gdn)}&name=${Uri.encodeComponent(g['cn'] ?? '')}" class="btn btn-ghost btn-sm">Mitglieder</a>
        <a href="/export/group?dn=${Uri.encodeComponent(gdn)}&name=${Uri.encodeComponent(g['cn'] ?? '')}" class="btn btn-ghost btn-sm">⬇ CSV</a>
        <form method="post" action="/group/delete" style="display:inline;margin:0">
          <input type="hidden" name="group_dn" value="${_esc(gdn)}">
          <button type="submit" class="btn btn-danger btn-sm" onclick="return confirm('Gruppe wirklich löschen?')">🗑 Löschen</button>
        </form>
      </td>
    </tr>''';
  }).join('\n');

  final ouOptions = ous
      .toList()
      ..sort((a, b) => (a['ou'] ?? a['dn'] ?? '').compareTo(b['ou'] ?? b['dn'] ?? ''));
  final ouOptHtml = ouOptions.map((o) {
    final label = _esc(o['ou'] as String? ?? o['dn'] as String? ?? '');
    final val = _esc(o['dn'] as String? ?? '');
    return '<option value="$val">$label</option>';
  }).join('\n');

  return _layout(username, 'Gruppen', '''
    <div class="card card-pad" style="margin-bottom:1rem;">
      <p style="font:600 13px var(--sans);color:var(--gray-700);margin-bottom:.85rem;">Neue Gruppe erstellen</p>
      <form method="post" action="/group/create" style="display:grid;grid-template-columns:1fr 1fr 1fr auto;gap:.65rem;align-items:end;">
        <div>
          <label style="display:block;font:600 .75rem var(--mono);color:var(--gray-500);margin-bottom:.3rem;text-transform:uppercase;letter-spacing:.06em;">Name *</label>
          <input type="text" name="name" required placeholder="z.B. IT-Admins" style="width:100%;padding:.5rem .75rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
        </div>
        <div>
          <label style="display:block;font:600 .75rem var(--mono);color:var(--gray-500);margin-bottom:.3rem;text-transform:uppercase;letter-spacing:.06em;">OU *</label>
          <select name="ou_dn" required style="width:100%;padding:.5rem .75rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;background:white;">
            <option value="">OU wählen...</option>
            $ouOptHtml
          </select>
        </div>
        <div>
          <label style="display:block;font:600 .75rem var(--mono);color:var(--gray-500);margin-bottom:.3rem;text-transform:uppercase;letter-spacing:.06em;">Beschreibung</label>
          <input type="text" name="description" placeholder="Optional..." style="width:100%;padding:.5rem .75rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
        </div>
        <button type="submit" class="btn btn-primary">+ Erstellen</button>
      </form>
    </div>
    <div class="card card-pad" style="margin-bottom:1rem;">
      <p style="font-weight:600;margin-bottom:.75rem;color:var(--gray-600);">Gruppen suchen</p>
      <form class="search-box" action="/groups" method="get">
        <input type="text" name="q" value="${_esc(query)}" placeholder="Gruppenname..." autofocus>
        <button type="submit" class="btn btn-primary">Suchen</button>
      </form>
    </div>
    ${groups.isEmpty && query.isNotEmpty ? '<div class="alert alert-error">Keine Gruppen gefunden.</div>' : ''}
    ${groups.isNotEmpty ? '''
    <div class="card">
      <table>
        <thead><tr><th>Gruppe</th><th>Mitglieder</th><th>Aktionen</th></tr></thead>
        <tbody>$rows</tbody>
      </table>
    </div>''' : ''}
  ''', active: 'groups');
}

String renderGroupMembers(String username, String groupName, String groupDn,
    List<Map<String, dynamic>> members) {
  final rows = members.map((u) {
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final mail = _esc(u['mail'] ?? '–');
    final dept = _esc(u['department'] ?? '–');
    final title = _esc(u['title'] ?? '–');
    return '<tr><td>$cn</td><td>$sam</td><td>$mail</td><td>$dept</td><td>$title</td></tr>';
  }).join('\n');

  return _layout(username, groupName, '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/groups" class="btn btn-ghost btn-sm">← Gruppen</a>
      <h2 style="font-size:1rem;font-weight:600;">${_esc(groupName)}</h2>
      <a href="/export/group?dn=${Uri.encodeComponent(groupDn)}&name=${Uri.encodeComponent(groupName)}"
         class="btn btn-ghost btn-sm" style="margin-left:auto;">⬇ CSV Export</a>
    </div>
    ${members.isEmpty ? '<div class="alert alert-error">Keine Mitglieder gefunden.</div>' : '''
    <div class="card">
      <table>
        <thead><tr><th>Name</th><th>Benutzername</th><th>E-Mail</th><th>Abteilung</th><th>Titel</th></tr></thead>
        <tbody>$rows</tbody>
      </table>
    </div>'''}
  ''', active: 'groups');
}

// ── OU Browser ───────────────────────────────────────────────────────────────

String renderOuBrowser(String username, List<Map<String, dynamic>> ous) {
  final tree = <String, List<Map<String, dynamic>>>{};
  final allDns = <String>{};
  for (final ou in ous) {
    allDns.add((ou['dn'] as String).toLowerCase());
  }
  for (final ou in ous) {
    final parent = _getParentDn(ou['dn'] as String).toLowerCase();
    tree.putIfAbsent(parent, () => []).add(ou);
  }

  String renderNode(Map<String, dynamic> ou) {
    final dn = ou['dn'] as String;
    final name = _esc(ou['ou'] as String? ?? _extractCn(dn));
    final desc = _esc(ou['description'] as String? ?? '');
    final children = (tree[dn.toLowerCase()] ?? [])
      ..sort((a, b) => (a['ou'] ?? '').compareTo(b['ou'] ?? ''));
    final childHtml = children.map((c) => renderNode(c)).join('\n');
    final hasChildren = children.isNotEmpty;
    final ouUrl = '/ou/users?dn=${Uri.encodeComponent(dn)}';
    if (hasChildren) {
      return '<li data-ou-name="${name.toLowerCase()}">'
          '<details>'
          '<summary class="ou-node">'
          '<svg class="ou-chevron" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3 4.5l3 3 3-3"/></svg>'
          '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".6"><path d="M2 4.5h5l1.5 2H14v7H2z"/></svg>'
          '<a href="$ouUrl" class="ou-name" onclick="event.stopPropagation()">$name</a>'
          '${desc.isNotEmpty ? '<span class="ou-desc">$desc</span>' : ''}'
          '</summary>'
          '<ul class="ou-children">$childHtml</ul>'
          '</details>'
          '</li>';
    } else {
      return '<li data-ou-name="${name.toLowerCase()}">'
          '<div class="ou-node ou-leaf">'
          '<span style="display:inline-block;width:12px;"></span>'
          '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".45"><path d="M2 4.5h5l1.5 2H14v7H2z"/></svg>'
          '<a href="$ouUrl" class="ou-name">$name</a>'
          '${desc.isNotEmpty ? '<span class="ou-desc">$desc</span>' : ''}'
          '</div>'
          '</li>';
    }
  }

  final roots = ous.where((ou) {
    final parent = _getParentDn(ou['dn'] as String).toLowerCase();
    return !allDns.contains(parent);
  }).toList()..sort((a, b) => (a['ou'] ?? '').compareTo(b['ou'] ?? ''));

  final treeHtml = roots.isEmpty
      ? '<p style="color:var(--gray-400);padding:.5rem">Keine OUs gefunden.</p>'
      : '<ul class="ou-tree" id="ou-tree">${roots.map(renderNode).join('\n')}</ul>';

  return _layout(username, 'OU-Browser', '''
    <style>
      .ou-tree, .ou-children { list-style:none; padding-left:0; margin:0; }
      .ou-children { padding-left:1.25rem; border-left:1px solid var(--gray-200); margin-left:.85rem; }
      .ou-node {
        display:flex; align-items:center; gap:.45rem;
        padding:.38rem .6rem; border-radius:7px;
        transition:background .1s;
      }
      .ou-node:not(.ou-leaf) { cursor:pointer; }
      .ou-node:hover { background:var(--gray-100); }
      summary.ou-node { list-style:none; }
      summary.ou-node::-webkit-details-marker { display:none; }
      .ou-chevron { transition:transform .18s; flex-shrink:0; color:var(--gray-400); }
      details[open] > summary .ou-chevron { transform:rotate(0deg); }
      summary .ou-chevron { transform:rotate(-90deg); }
      details[open] > summary .ou-chevron { transform:rotate(0deg); }
      .ou-name { color:var(--blue); text-decoration:none; font:500 .9rem var(--sans); }
      .ou-name:hover { text-decoration:underline; }
      .ou-desc { font:400 .72rem var(--mono); color:var(--gray-400); margin-left:.15rem; }
      .ou-search { width:100%; padding:.65rem 1rem .65rem 2.6rem; border:1.5px solid var(--gray-200); border-radius:8px; font:400 14px var(--sans); outline:none; transition:border-color .15s,box-shadow .15s; }
      .ou-search:focus { border-color:var(--blue); box-shadow:0 0 0 3px rgba(37,99,235,.12); }
      .ou-search-wrap { position:relative; margin-bottom:1.25rem; }
      .ou-search-ico { position:absolute; left:.8rem; top:50%; transform:translateY(-50%); color:var(--gray-400); pointer-events:none; }
      li[data-ou-name].hidden { display:none; }
    </style>
    <div class="card card-pad">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:1rem;">
        <div>
          <p style="font:600 14px var(--sans);color:var(--gray-800);">Active Directory Struktur</p>
          <p style="font:400 .78rem var(--mono);color:var(--gray-400);margin-top:2px;">${ous.length} OUs geladen</p>
        </div>
        <div style="display:flex;gap:.5rem;">
          <button onclick="expandAll()" class="btn btn-ghost btn-sm">Alle aufklappen</button>
          <button onclick="collapseAll()" class="btn btn-ghost btn-sm">Alle einklappen</button>
        </div>
      </div>
      <div class="ou-search-wrap">
        <svg class="ou-search-ico" width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="7" cy="7" r="4.2"/><line x1="10.2" y1="10.2" x2="13.5" y2="13.5" stroke-linecap="round"/></svg>
        <input class="ou-search" type="text" id="ou-search" placeholder="OU suchen..." oninput="filterOus(this.value)" autocomplete="off">
      </div>
      <div id="ou-empty" style="display:none;color:var(--gray-400);font-size:.875rem;padding:.5rem 0;">Keine OUs gefunden.</div>
      $treeHtml
    </div>
    <script>
    function filterOus(q) {
      q = q.toLowerCase().trim();
      const tree = document.getElementById('ou-tree');
      const empty = document.getElementById('ou-empty');
      if (!q) {
        tree.querySelectorAll('li[data-ou-name]').forEach(li => li.classList.remove('hidden'));
        tree.querySelectorAll('details').forEach(d => d.open = false);
        empty.style.display = 'none';
        tree.style.display = '';
        return;
      }
      // First hide all
      tree.querySelectorAll('li[data-ou-name]').forEach(li => li.classList.add('hidden'));
      // Show matches and their ancestors
      let found = 0;
      tree.querySelectorAll('li[data-ou-name]').forEach(li => {
        if (li.dataset.ouName.includes(q)) {
          found++;
          li.classList.remove('hidden');
          let parent = li.parentElement;
          while (parent && parent !== tree) {
            if (parent.tagName === 'UL') {
              const parentLi = parent.closest('li[data-ou-name]');
              if (parentLi) parentLi.classList.remove('hidden');
              const parentDetails = parent.previousElementSibling?.tagName === 'DETAILS'
                ? parent.previousElementSibling : parent.closest('details');
              if (parentDetails) parentDetails.open = true;
            }
            if (parent.tagName === 'DETAILS') parent.open = true;
            parent = parent.parentElement;
          }
        }
      });
      empty.style.display = found === 0 ? '' : 'none';
      tree.style.display = found === 0 ? 'none' : '';
    }
    function expandAll() {
      document.getElementById('ou-tree').querySelectorAll('details').forEach(d => d.open = true);
    }
    function collapseAll() {
      document.getElementById('ou-tree').querySelectorAll('details').forEach(d => d.open = false);
    }
    </script>
  ''', active: 'ou');
}

String renderOuUsers(String username, String ouDn, List<Map<String, dynamic>> users,
    {bool subtree = false}) {
  final ouName = _extractCn(ouDn);
  final toggleUrl = subtree
      ? '/ou/users?dn=${Uri.encodeComponent(ouDn)}'
      : '/ou/users?dn=${Uri.encodeComponent(ouDn)}&subtree=1';
  final rows = users.map((u) {
    final dn = u['dn'] ?? '';
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final mail = _esc(u['mail'] ?? '–');
    final dept = _esc(u['department'] ?? '–');
    final uac2 = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
    final badge = (uac2 & 2) != 0
        ? '<span class="badge badge-disabled">Inaktiv</span>'
        : '<span class="badge badge-active">Aktiv</span>';
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
    return '<tr onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">'
        '<td><strong>$cn</strong></td>'
        '<td>$sam</td><td>$mail</td><td>$dept</td><td>$badge</td></tr>';
  }).join('\n');

  return _layout(username, ouName, '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;flex-wrap:wrap;">
      <a href="/ou" class="btn btn-ghost btn-sm">← OU-Browser</a>
      <h2 style="font-size:1rem;font-weight:600;">$ouName</h2>
      <span style="font-size:.78rem;color:var(--gray-400);word-break:break-all;">${_esc(ouDn)}</span>
      <a href="$toggleUrl" class="btn btn-ghost btn-sm" style="margin-left:auto;">
        ${subtree ? '📂 Nur direkte User' : '📁 Alle Sub-OUs einschliessen'}
      </a>
    </div>
    ${users.isEmpty
      ? '<div class="alert alert-error" style="background:var(--gray-100);color:var(--gray-600);border-color:var(--gray-200);">Keine User in dieser OU${subtree ? '' : ' (direkt)'}.</div>'
      : '''<div class="card">
          <table class="result-table">
            <thead><tr><th>Name</th><th>Benutzername</th><th>E-Mail</th><th>Abteilung</th><th>Status</th></tr></thead>
            <tbody>$rows</tbody>
          </table>
        </div>'''}
  ''', active: 'ou');
}

// ── Audit Log ─────────────────────────────────────────────────────────────────

String renderAuditLog(String username, List<AuditEntry> entries) {
  final rows = entries.map((e) {
    final ts = e.timestamp;
    final time = '${ts.day.toString().padLeft(2,'0')}.${ts.month.toString().padLeft(2,'0')}.${ts.year} '
        '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}';
    final cnPart = _extractCn(e.targetDn);
    final target = e.targetDn.isNotEmpty
        ? '<span title="${_esc(e.targetDn)}" style="cursor:help;">$cnPart</span>'
        : '–';
    return '<tr>'
        '<td style="white-space:nowrap;font-size:.78rem;color:var(--gray-400);">$time</td>'
        '<td><strong>${_esc(e.actor)}</strong></td>'
        '<td>${_esc(e.action)}</td>'
        '<td>$target</td>'
        '<td style="color:var(--gray-400);font-size:.82rem;">${_esc(e.details)}</td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Änderungs-Log', '''
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:1rem;flex-wrap:wrap;gap:.5rem;">
      <h2 style="font-size:1rem;font-weight:600;">Änderungs-Log</h2>
      <div style="display:flex;align-items:center;gap:.75rem;">
        <span style="font-size:.82rem;color:var(--gray-400);">${entries.length} Einträge (persistiert in audit.jsonl)</span>
        <a href="/export/audit" class="btn btn-ghost btn-sm">
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M8 2v8M5 7l3 3 3-3" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 12h10" stroke-linecap="round"/></svg>
          CSV exportieren
        </a>
      </div>
    </div>
    ${entries.isEmpty
      ? '<div class="card card-pad"><em style="color:var(--gray-400)">Noch keine Einträge.</em></div>'
      : '''<div class="card overflow-x">
          <table>
            <thead><tr><th>Zeit</th><th>Benutzer</th><th>Aktion</th><th>Ziel</th><th>Details</th></tr></thead>
            <tbody>$rows</tbody>
          </table>
        </div>'''}
  ''', active: 'log');
}

// ── Einstellungen ────────────────────────────────────────────────────────────

String renderSettings(String username, Map<String, bool> settings, {String? msg}) {
  final readOnlySelf = settings['readonly_self'] ?? false;

  String toggle(String key, bool value, String label, String desc, String icon) {
    final id = 'toggle-$key';
    return '''
    <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:1.5rem;padding:1rem 0;border-bottom:1px solid var(--gray-100);">
      <div style="display:flex;align-items:flex-start;gap:.85rem;">
        <div style="width:36px;height:36px;border-radius:8px;background:var(--gray-100);display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:1.1rem;">$icon</div>
        <div>
          <div style="font:600 14px var(--sans);color:var(--gray-800);">$label</div>
          <div style="font:400 .82rem var(--sans);color:var(--gray-500);margin-top:.25rem;max-width:360px;">$desc</div>
        </div>
      </div>
      <form method="post" action="/settings" style="margin:0;flex-shrink:0;">
        <input type="hidden" name="key" value="$key">
        <button type="submit" id="$id" style="
          width:44px;height:24px;border-radius:12px;border:none;cursor:pointer;
          background:${value ? 'var(--blue)' : 'var(--gray-300)'};
          position:relative;transition:background .2s;padding:0;
        " title="${value ? 'Deaktivieren' : 'Aktivieren'}">
          <span style="
            position:absolute;top:3px;left:${value ? '22' : '3'}px;
            width:18px;height:18px;border-radius:50%;background:white;
            transition:left .2s;box-shadow:0 1px 4px rgba(0,0,0,.2);
          "></span>
        </button>
      </form>
    </div>''';
  }

  return _layout(username, 'Einstellungen', '''
    <div style="display:flex;align-items:center;gap:.6rem;margin-bottom:1.25rem;">
      <a href="javascript:history.back()" class="btn btn-ghost btn-sm">← Zurück</a>
      <h1 style="font:700 16px var(--sans);color:var(--gray-800);">Einstellungen</h1>
    </div>

    ${msg == 'testmail' ? '<div class="alert alert-success" style="margin-bottom:1.25rem;">✓ Testmail wurde gesendet an support.it@somedia.ch.</div>' : ''}

    <div class="card" style="margin-bottom:1.25rem;">
      <div style="padding:1rem 1.5rem;border-bottom:1px solid var(--gray-100);">
        <p style="font:700 11px var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);">Wochen-Report</p>
      </div>
      <div style="padding:1rem 1.5rem;display:flex;align-items:center;justify-content:space-between;gap:1rem;flex-wrap:wrap;">
        <div>
          <div style="font:600 14px var(--sans);color:var(--gray-800);">Testmail senden</div>
          <div style="font:400 .82rem var(--sans);color:var(--gray-500);margin-top:.25rem;">Sendet sofort einen Bericht mit gesperrten Usern &amp; ablaufenden Passwörtern.</div>
        </div>
        <a href="/admin/test-mail" class="btn btn-ghost btn-sm" style="white-space:nowrap;">
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" style="margin-right:.35rem;vertical-align:middle;"><rect x="2" y="3.5" width="12" height="9" rx="1.5"/><path d="M2 3.5l6 5.5 6-5.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
          Testmail senden
        </a>
      </div>
    </div>

    <div class="card" style="margin-bottom:1.25rem;">
      <div style="padding:1rem 1.5rem;border-bottom:1px solid var(--gray-100);">
        <p style="font:700 11px var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);">Account-Schutz</p>
      </div>
      <div style="padding:0 1.5rem;">
        ${toggle('readonly_self', readOnlySelf,
            'Nur-Lesen für eigenen Account',
            'Verhindert versehentliche Änderungen an deinem eigenen AD-Account. Bearbeiten, Passwort-Reset und Account-Aktionen sind dann gesperrt, wenn du deinen eigenen User öffnest.',
            '🔒')}
      </div>
    </div>

    <div class="card">
      <div style="padding:1rem 1.5rem;border-bottom:1px solid var(--gray-100);">
        <p style="font:700 11px var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);">Session-Info</p>
      </div>
      <div style="padding:1rem 1.5rem;">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:.75rem 2rem;font-size:.875rem;">
          <div>
            <div style="font:600 .68rem var(--mono);text-transform:uppercase;letter-spacing:.08em;color:var(--gray-400);margin-bottom:.25rem;">Angemeldet als</div>
            <div style="font-weight:600;">$username</div>
          </div>
          <div>
            <div style="font:600 .68rem var(--mono);text-transform:uppercase;letter-spacing:.08em;color:var(--gray-400);margin-bottom:.25rem;">Status</div>
            <span class="badge badge-active">Aktive Session</span>
          </div>
        </div>
        <div style="margin-top:1rem;padding-top:1rem;border-top:1px solid var(--gray-100);">
          <a href="/logout" class="btn btn-danger btn-sm">Abmelden</a>
        </div>
      </div>
    </div>

    <p style="font:400 .78rem var(--mono);color:var(--gray-400);text-align:center;margin-top:.75rem;">
      Einstellungen werden bei Session-Ende zurückgesetzt.
    </p>
  ''', active: 'settings');
}

// ── User kopieren ─────────────────────────────────────────────────────────────

String renderCloneForm(String username, Map<String, dynamic> u, String back) {
  final dn = u['dn'] as String? ?? '';
  final cn = _esc(u['cn'] as String? ?? '');
  final sam = _esc(u['sAMAccountName'] as String? ?? '');
  final dept = _esc(u['department'] as String? ?? '');
  final title2 = _esc(u['title'] as String? ?? '');
  final parentOu = dn.contains(',') ? dn.substring(dn.indexOf(',') + 1) : dn;

  return _layout(username, 'User kopieren', '''
    <div style="display:flex;align-items:center;gap:.6rem;margin-bottom:1rem;">
      <a href="/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}" class="btn btn-ghost btn-sm">← Zurück</a>
      <h2 style="font-size:1rem;font-weight:600;">Neuen User basierend auf Vorlage erstellen</h2>
    </div>
    <div class="card card-pad" style="margin-bottom:1rem;background:var(--blue-lt);border:1px solid #93c5fd;">
      <p style="font-size:.85rem;"><strong>Vorlage:</strong> $cn (<code>$sam</code>)</p>
      <p style="font-size:.78rem;color:var(--gray-600);margin-top:.3rem;">OU: ${_esc(parentOu)}</p>
      <p style="font-size:.78rem;color:var(--gray-600);">Alle Gruppen werden auf den neuen User übertragen.</p>
    </div>
    <div class="card card-pad">
      <form method="post" action="/user/clone">
        <input type="hidden" name="template_dn" value="${_esc(dn)}">
        <input type="hidden" name="parent_ou" value="${_esc(parentOu)}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;">
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">Vorname *</label>
            <input type="text" name="givenName" required style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;" autofocus>
          </div>
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">Nachname *</label>
            <input type="text" name="sn" required style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;">
          </div>
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">Benutzername (sAMAccountName) *</label>
            <input type="text" name="sAMAccountName" required style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;">
          </div>
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">Initiales Passwort *</label>
            <input type="password" name="password" required style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;">
          </div>
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">E-Mail</label>
            <input type="email" name="mail" style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;">
          </div>
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">Abteilung</label>
            <input type="text" name="department" value="$dept" style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;">
          </div>
          <div>
            <label style="display:block;font-size:.8rem;font-weight:600;color:var(--gray-600);margin-bottom:.3rem;">Titel / Position</label>
            <input type="text" name="title" value="$title2" style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;">
          </div>
        </div>
        <div style="margin-top:1rem;display:flex;align-items:center;gap:.5rem;">
          <input type="checkbox" name="must_change" value="1" id="must-change" checked>
          <label for="must-change" style="font-size:.88rem;">Passwort bei erster Anmeldung ändern erzwingen</label>
        </div>
        <div style="margin-top:1.25rem;display:flex;gap:.75rem;">
          <button type="submit" class="btn btn-primary">👤 User erstellen</button>
          <a href="/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}" class="btn btn-ghost">Abbrechen</a>
        </div>
      </form>
    </div>
  ''', active: 'search');
}

// ── User verschieben ─────────────────────────────────────────────────────────

String renderMoveForm(String username, Map<String, dynamic> u, List<Map<String, dynamic>> ous, String back) {
  final dn = u['dn'] as String? ?? '';
  final cn = _esc(u['cn'] as String? ?? '');
  final sam = _esc(u['sAMAccountName'] as String? ?? '');
  final currentOu = dn.contains(',') ? dn.substring(dn.indexOf(',') + 1) : dn;

  final lagerOu = _appLagerOu;
  final rawCn = (u['cn'] as String? ?? '').toLowerCase();
  final isComputer = _appComputerPrefixes.isNotEmpty
      ? _appComputerPrefixes.any((p) => rawCn.startsWith(p))
      : false;
  final alreadyInLager = dn.toLowerCase().contains('lager_deaktivierte');

  final lagerSection = isComputer ? '''
    <div style="margin-bottom:1rem;border-radius:10px;border:2px solid #f97316;background:#fff7ed;padding:1rem 1.2rem;display:flex;align-items:center;gap:1.2rem;">
      <div style="flex:1;">
        <p style="font:700 .9rem var(--sans);color:#c2410c;margin:0 0 .2rem;">Schnell-Aktion</p>
        <p style="font-size:.8rem;color:#9a3412;margin:0;">Gerät direkt in den Lager-OU verschieben und deaktivieren.</p>
      </div>
      ${alreadyInLager
        ? '<span style="font:.6rem var(--sans);color:#9a3412;background:#fed7aa;border-radius:6px;padding:.4rem .9rem;">Bereits im Lager</span>'
        : '''<form method="post" action="/computer/move-lager" style="margin:0;"
               onsubmit="return confirm('Gerät $cn wirklich ins Lager verschieben?')">
             <input type="hidden" name="dn" value="${_esc(dn)}">
             <input type="hidden" name="target_ou" value="${_esc(lagerOu)}">
             <button type="submit"
               style="background:#f97316;color:#fff;border:none;border-radius:8px;padding:.55rem 1.2rem;font:700 .9rem var(--sans);cursor:pointer;white-space:nowrap;box-shadow:0 2px 8px rgba(249,115,22,.4);letter-spacing:.01em;">
               &#128230; Ins Lager verschieben
             </button>
           </form>'''}
    </div>
  ''' : '';

  final ouOptions = ous
      .toList()
      ..sort((a, b) => (a['ou'] ?? a['dn'] ?? '').compareTo(b['ou'] ?? b['dn'] ?? ''));
  final ouOptHtml = ouOptions.map((o) {
    final label = _esc(o['ou'] as String? ?? o['dn'] as String? ?? '');
    final val = _esc(o['dn'] as String? ?? '');
    final selected = val == _esc(currentOu) ? ' selected' : '';
    return '<option value="$val"$selected>$label</option>';
  }).join('\n');

  final pageTitle = isComputer ? 'Computer verschieben' : 'Benutzer in andere OU verschieben';
  final objectLabel = isComputer ? 'Computer' : 'Benutzer';

  return _layout(username, isComputer ? 'Computer verschieben' : 'User verschieben', '''
    <div style="display:flex;align-items:center;gap:.6rem;margin-bottom:1rem;">
      <a href="/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}" class="btn btn-ghost btn-sm">← Zurück</a>
      <h2 style="font-size:1rem;font-weight:600;">$pageTitle</h2>
    </div>
    <div class="card card-pad" style="margin-bottom:1rem;background:var(--blue-lt);border:1px solid #93c5fd;">
      <p style="font-size:.85rem;"><strong>$objectLabel:</strong> $cn (<code>$sam</code>)</p>
      <p style="font-size:.78rem;color:var(--gray-600);margin-top:.3rem;">Aktuelle OU: ${_esc(currentOu)}</p>
    </div>
    $lagerSection
    <div class="card card-pad">
      <form method="post" action="/user/move">
        <input type="hidden" name="dn" value="${_esc(dn)}">
        <input type="hidden" name="back" value="${_esc(back)}">
        <div style="margin-bottom:1rem;">
          <label style="display:block;font:600 .8rem var(--sans);color:var(--gray-600);margin-bottom:.4rem;">Ziel-OU auswählen *</label>
          <select name="target_ou" required style="width:100%;padding:.55rem .85rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.95rem;background:white;">
            <option value="">OU wählen...</option>
            $ouOptHtml
          </select>
        </div>
        <div style="display:flex;gap:.75rem;">
          <button type="submit" class="btn btn-primary">📦 Verschieben</button>
          <a href="/user?dn=${Uri.encodeComponent(dn)}&q=${Uri.encodeComponent(back)}" class="btn btn-ghost">Abbrechen</a>
        </div>
      </form>
    </div>
  ''', active: 'search');
}

// ── Hilfsfunktionen ──────────────────────────────────────────────────────────

String _formatFileTime(String? value) {
  final ft = int.tryParse(value ?? '0') ?? 0;
  if (ft <= 0) return '–';
  if (ft == 9223372036854775807) return 'Nie';
  final unixMs = (ft ~/ 10000) - 11644473600000;
  if (unixMs <= 0) return '–';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}

String _pwdExpiryInfo(String? pwdLastSetStr, int uac, int maxPwdAgeDays) {
  if ((uac & 65536) != 0) return 'Läuft nie ab';
  final ft = int.tryParse(pwdLastSetStr ?? '0') ?? 0;
  if (ft <= 0) return 'Muss bei nächster Anmeldung geändert werden';
  final unixMs = (ft ~/ 10000) - 11644473600000;
  final set = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
  final expiry = set.add(Duration(days: maxPwdAgeDays));
  final daysLeft = expiry.difference(DateTime.now()).inDays;
  final dateStr = '${expiry.day.toString().padLeft(2, '0')}.${expiry.month.toString().padLeft(2, '0')}.${expiry.year}';
  if (daysLeft < 0) return '<span style="color:var(--red);">Abgelaufen seit ${-daysLeft} Tagen ($dateStr)</span>';
  if (daysLeft <= 14) return '<span style="color:#92400e;">In $daysLeft Tagen ($dateStr)</span>';
  return 'In $daysLeft Tagen ($dateStr)';
}

String _pwdStatusBox(String? pwdLastSetStr, int uac, int maxPwdAgeDays) {
  final neverExpires = (uac & 65536) != 0;
  final ft = int.tryParse(pwdLastSetStr ?? '0') ?? 0;
  final mustChange = ft <= 0 && !neverExpires;

  String badgeColor, badgeText, detail, icon;

  if (mustChange) {
    badgeColor = '#dc2626'; badgeText = 'Muss geändert werden'; icon = '⚠';
    detail = 'Das Passwort muss bei der nächsten Anmeldung geändert werden.';
  } else if (neverExpires) {
    badgeColor = '#2563eb'; badgeText = 'Läuft nie ab'; icon = '🔵';
    final setStr = ft > 0 ? _formatFileTime(pwdLastSetStr) : '–';
    detail = 'Gesetzt am: <strong>$setStr</strong>';
  } else {
    final unixMs = (ft ~/ 10000) - 11644473600000;
    final set = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
    final expiry = set.add(Duration(days: maxPwdAgeDays));
    final daysLeft = expiry.difference(DateTime.now()).inDays;
    final expiryStr = '${expiry.day.toString().padLeft(2,'0')}.${expiry.month.toString().padLeft(2,'0')}.${expiry.year}';
    final setStr = _formatFileTime(pwdLastSetStr);
    if (daysLeft < 0) {
      badgeColor = '#dc2626'; badgeText = 'Abgelaufen'; icon = '⚠';
      detail = 'Gesetzt am: <strong>$setStr</strong> · Abgelaufen seit <strong>${-daysLeft} Tagen</strong> ($expiryStr)';
    } else if (daysLeft <= 14) {
      badgeColor = '#d97706'; badgeText = 'Läuft bald ab'; icon = '⏰';
      detail = 'Gesetzt am: <strong>$setStr</strong> · Läuft ab in <strong>$daysLeft Tagen</strong> ($expiryStr)';
    } else {
      badgeColor = '#16a34a'; badgeText = 'Gültig'; icon = '✓';
      detail = 'Gesetzt am: <strong>$setStr</strong> · Läuft ab: <strong>$expiryStr</strong> (in $daysLeft Tagen)';
    }
  }

  return '''
  <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:.65rem;padding:.6rem .85rem;background:var(--gray-50);border:1px solid var(--gray-200);border-radius:8px;flex-wrap:wrap;">
    <span style="display:inline-flex;align-items:center;gap:.3rem;background:$badgeColor;color:#fff;border-radius:5px;padding:.2rem .55rem;font:700 .72rem var(--sans);white-space:nowrap;">$icon $badgeText</span>
    <span style="font-size:.8rem;color:var(--gray-600);">$detail</span>
  </div>''';
}

// ── Feedback ──────────────────────────────────────────────────────────────────

String renderSuccess(String username, String msg) => _layout(username, 'Erfolg', '''
  <div class="alert alert-success">✓ $msg</div>
  <a href="javascript:history.back()" class="btn btn-ghost">← Zurück</a>
''');

String renderError(String username, String msg) => _layout(username, 'Fehler', '''
  <div class="alert alert-error">✗ $msg</div>
  <a href="/" class="btn btn-ghost">← Zur Suche</a>
''');

// ── Helpers ───────────────────────────────────────────────────────────────────

String _getParentDn(String dn) {
  final idx = dn.indexOf(',');
  return idx >= 0 ? dn.substring(idx + 1) : '';
}

String _formatAccountExpiry(int ft) {
  if (ft <= 0 || ft == 9223372036854775807) return 'Kein Ablauf';
  final unixMs = (ft ~/ 10000) - 11644473600000;
  if (unixMs <= 0) return 'Kein Ablauf';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toLocal();
  final now = DateTime.now();
  final daysLeft = dt.difference(now).inDays;
  final dateStr = '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year}';
  if (daysLeft < 0) return '<span style="color:var(--red);">Abgelaufen ($dateStr)</span>';
  if (daysLeft <= 7) return '<span style="color:#92400e;">In $daysLeft Tagen ($dateStr)</span>';
  return dateStr;
}

String _extractCn(String dn) {
  final match = RegExp(r'^CN=([^,]+)', caseSensitive: false).firstMatch(dn);
  return _esc(match?.group(1) ?? dn);
}

String _extractOu(String dn) {
  final matches = RegExp(r'OU=([^,]+)', caseSensitive: false).allMatches(dn);
  return _esc(matches.map((m) => m.group(1) ?? '').join(' › '));
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// ── Hausplan ──────────────────────────────────────────────────────────────────

// Abteilung → (Bild, Marker-X%, Marker-Y%)
const _deptMarkers = <String, (String, double, double)>{
  'IT-Services':           ('attika.png', 26.0, 68.0),
  'Kundenservice':         ('2og.png',   50.0, 72.0),
  'Somedia Distribution':  ('1og.png',   94.0, 45.0),
  'SO Online Zeitung':     ('1og.png',   24.0, 45.0),
  'Zeitung Produktion':    ('1og.png',   38.0, 45.0),
  'Digital & KI':          ('1og.png',   50.0, 28.0),
  'SO Audio Video':        ('1og.png',   80.0, 45.0),
  'TV':                    ('2og.png',   18.0, 45.0),
  'Creation':              ('2og.png',   92.0, 30.0),
};

// Büro-Code → Bild (Fallback wenn keine Abteilung bekannt)
String? _floorImg(String office) {
  final up = office.toUpperCase();
  if (up.startsWith('AT')) return 'attika.png';
  if (up.startsWith('2.OG') || up.startsWith('2OG')) return '2og.png';
  if (up.startsWith('1.OG') || up.startsWith('1OG')) return '1og.png';
  return null;
}

String _floorplanBlock(String office, String dept) {
  if (office.isEmpty) return '';
  final deptEntry = _deptMarkers[dept];
  String? img;
  double? mx, my;
  if (deptEntry != null) {
    img = deptEntry.$1; mx = deptEntry.$2; my = deptEntry.$3;
  } else {
    img = _floorImg(office);
  }
  if (img == null) return '';

  final marker = (mx != null && my != null) ? '''
    <div style="position:absolute;left:${mx}%;top:${my}%;transform:translate(-50%,-50%);pointer-events:none;z-index:2;">
      <div style="width:18px;height:18px;border-radius:50%;background:#2563eb;border:3px solid #fff;box-shadow:0 0 0 2px #2563eb,0 2px 8px rgba(37,99,235,.5);"></div>
    </div>''' : '';

  return '''
  <div class="field-item" style="grid-column:1/-1;">
    <div class="field-label">Standort – ${_esc(office)}</div>
    <div style="position:relative;width:100%;margin-top:.5rem;border-radius:8px;overflow:hidden;border:1px solid var(--gray-200);background:#f8f9fa;">
      <img src="/floorplan/$img" style="width:100%;display:block;">
      $marker
    </div>
  </div>''';
}

String renderFloorplanPreview(String username) {
  final colors = ['#2563eb','#dc2626','#16a34a','#d97706','#7c3aed','#0891b2','#db2777','#65a30d'];
  int colorIdx = 0;

  String planSection(String title, String imgFile) {
    final depts = _deptMarkers.entries.where((e) => e.value.$1 == imgFile).toList();
    final startIdx = colorIdx;
    final markers = StringBuffer();
    for (var i = 0; i < depts.length; i++) {
      final e = depts[i];
      final color = colors[(startIdx + i) % colors.length];
      markers.write('<div style="position:absolute;left:${e.value.$2}%;top:${e.value.$3}%;transform:translate(-50%,-50%);z-index:2;">'
          '<div style="width:16px;height:16px;border-radius:50%;background:$color;border:2px solid #fff;box-shadow:0 0 0 1.5px $color,0 2px 6px rgba(0,0,0,.3);"></div>'
          '<div style="position:absolute;top:18px;left:50%;transform:translateX(-50%);white-space:nowrap;font:600 10px sans-serif;color:$color;background:rgba(255,255,255,.9);padding:1px 4px;border-radius:3px;border:1px solid $color;">${_esc(e.key)}</div>'
          '</div>');
    }
    colorIdx += depts.length;

    final legend = StringBuffer();
    for (var i = 0; i < depts.length; i++) {
      final e = depts[i];
      final color = colors[(startIdx + i) % colors.length];
      legend.write('<div style="display:flex;align-items:center;gap:.4rem;font:400 .78rem sans-serif;">'
          '<span style="width:10px;height:10px;border-radius:50%;background:$color;flex-shrink:0;"></span>'
          '${_esc(e.key)}</div>');
    }

    return '''
    <div class="card" style="margin-bottom:1.5rem;">
      <div style="padding:.75rem 1.25rem;border-bottom:1px solid var(--gray-100);font:700 .85rem var(--sans);color:var(--gray-700);">$title</div>
      <div style="padding:1rem 1.25rem;">
        <div style="position:relative;width:100%;border-radius:6px;overflow:hidden;border:1px solid var(--gray-200);background:#f8f9fa;margin-bottom:.75rem;">
          <img src="/floorplan/$imgFile" style="width:100%;display:block;">
          ${markers.toString()}
        </div>
        ${depts.isEmpty ? '<em style="color:var(--gray-400);font-size:.8rem;">Keine Abteilungen zugewiesen</em>' : '<div style="display:flex;flex-wrap:wrap;gap:.5rem .75rem;">${legend.toString()}</div>'}
      </div>
    </div>''';
  }

  return _layout(username, 'Hausplan Vorschau', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1.25rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <h1 style="font:700 16px var(--sans);color:var(--gray-800);">Hausplan – Abteilungs-Übersicht</h1>
    </div>
    <div class="alert" style="margin-bottom:1.25rem;background:var(--blue-lt);border:1px solid #93c5fd;color:var(--blue);">
      Vorschau aller Abteilungs-Marker. Stimmt etwas nicht? Sag mir welcher Punkt wohin soll.
    </div>
    ${planSection('Attika', 'attika.png')}
    ${planSection('2. Obergeschoss', '2og.png')}
    ${planSection('1. Obergeschoss', '1og.png')}
  ''', active: '');
}

// ── Feature: Inaktive User ────────────────────────────────────────────────────

String renderInactiveUsers(String username, List<Map<String, dynamic>> users) {
  final rows = users.map((u) {
    final dn = u['dn'] ?? '';
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final lastLogin = _formatFileTime(u['lastLogonTimestamp']?.toString());
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
    return '<tr onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">'
        '<td><strong>$cn</strong></td><td>$sam</td><td>$lastLogin</td>'
        '<td><a href="$detailUrl" class="btn btn-ghost btn-xs" onclick="event.stopPropagation()">Details</a></td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Inaktive Benutzer', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Inaktive Benutzer</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">Letzter Login vor mehr als 90 Tagen (aktive Accounts)</p>
      </div>
    </div>
    <div class="card">
      ${users.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine inaktiven Benutzer gefunden.</em></div>'
        : '''
        <div class="card-pad" style="padding-bottom:.5rem;">
          <span style="font:500 .82rem var(--sans);color:var(--gray-500);">${users.length} Benutzer</span>
        </div>
        <table class="result-table">
          <thead><tr><th>Name</th><th>Benutzername</th><th>Letzter Login</th><th></th></tr></thead>
          <tbody>$rows</tbody>
        </table>'''}
    </div>
  ''', active: 'inactive');
}

// ── Feature: Service-Accounts ─────────────────────────────────────────────────

String renderServiceAccounts(String username, List<Map<String, dynamic>> users) {
  final rows = users.map((u) {
    final dn = u['dn'] ?? '';
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final desc = _esc(u['description'] ?? '–');
    final pwdSet = _formatFileTime(u['pwdLastSet']?.toString());
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
    return '<tr onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">'
        '<td><strong>$cn</strong></td><td>$sam</td><td>$desc</td><td>$pwdSet</td>'
        '<td><a href="$detailUrl" class="btn btn-ghost btn-xs" onclick="event.stopPropagation()">Details</a></td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Service-Accounts', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Service-Accounts</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">Benutzer mit "Passwort läuft nie ab" (UAC Bit 65536)</p>
      </div>
    </div>
    <div class="card">
      ${users.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine Service-Accounts gefunden.</em></div>'
        : '''
        <div class="card-pad" style="padding-bottom:.5rem;">
          <span style="font:500 .82rem var(--sans);color:var(--gray-500);">${users.length} Accounts</span>
        </div>
        <table class="result-table">
          <thead><tr><th>Name</th><th>Benutzername</th><th>Beschreibung</th><th>PW gesetzt am</th><th></th></tr></thead>
          <tbody>$rows</tbody>
        </table>'''}
    </div>
  ''', active: 'service');
}

// ── Feature: Accounts ohne E-Mail ────────────────────────────────────────────

String renderUsersNoEmail(String username, List<Map<String, dynamic>> users) {
  final rows = users.map((u) {
    final dn = u['dn'] ?? '';
    final cn = _esc(u['cn'] ?? '–');
    final sam = _esc(u['sAMAccountName'] ?? '–');
    final dept = _esc(u['department'] ?? '–');
    final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
    final badge = (uac & 2) != 0
        ? '<span class="badge badge-disabled">Inaktiv</span>'
        : '<span class="badge badge-active">Aktiv</span>';
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
    return '<tr onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">'
        '<td><strong>$cn</strong></td><td>$sam</td><td>$dept</td><td>$badge</td>'
        '<td><a href="$detailUrl" class="btn btn-ghost btn-xs" onclick="event.stopPropagation()">Details</a></td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Ohne E-Mail', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Benutzer ohne E-Mail-Adresse</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">Accounts ohne gesetztes mail-Attribut</p>
      </div>
    </div>
    <div class="card">
      ${users.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Alle Benutzer haben eine E-Mail-Adresse.</em></div>'
        : '''
        <div class="card-pad" style="padding-bottom:.5rem;">
          <span style="font:500 .82rem var(--sans);color:var(--gray-500);">${users.length} Benutzer</span>
        </div>
        <table class="result-table">
          <thead><tr><th>Name</th><th>Benutzername</th><th>Abteilung</th><th>Status</th><th></th></tr></thead>
          <tbody>$rows</tbody>
        </table>'''}
    </div>
  ''', active: 'noemail');
}

// ── Feature: Passwort-Policy ──────────────────────────────────────────────────

String renderPasswordPolicy(String username, Map<String, String> policy) {
  int parseNegFt(String? val, int divisor) {
    final v = int.tryParse(val ?? '0') ?? 0;
    if (v == 0) return 0;
    return (v.abs() ~/ divisor);
  }

  final minLen = policy['minPwdLength'] ?? '–';
  final histLen = policy['pwdHistoryLength'] ?? '–';
  final maxPwdAgeDays = parseNegFt(policy['maxPwdAge'], 10000000 * 86400);
  final minPwdAgeDays = parseNegFt(policy['minPwdAge'], 10000000 * 86400);
  final lockoutThreshold = policy['lockoutThreshold'] ?? '–';
  final lockoutDurMins = parseNegFt(policy['lockoutDuration'], 10000000 * 60);
  final observeWinMins = parseNegFt(policy['lockoutObservationWindow'], 10000000 * 60);
  final pwdProps = int.tryParse(policy['pwdProperties'] ?? '0') ?? 0;
  final complexity = (pwdProps & 1) != 0 ? 'Ja' : 'Nein';

  String row(String label, String value, {String? icon}) => '''
    <div style="display:flex;align-items:center;justify-content:space-between;padding:.8rem 0;border-bottom:1px solid var(--gray-100);">
      <div style="display:flex;align-items:center;gap:.6rem;">
        ${icon != null ? '<span style="font-size:1.1rem;">$icon</span>' : '<span style="width:1.6rem;display:inline-block;"></span>'}
        <span style="font:500 .9rem var(--sans);color:var(--gray-700);">$label</span>
      </div>
      <span style="font:700 .9rem var(--mono);color:var(--gray-800);">$value</span>
    </div>''';

  return _layout(username, 'Passwort-Policy', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <h2 style="font-size:1rem;font-weight:600;">Domain Passwort-Policy</h2>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;">
      <div class="card card-pad">
        <div class="card-section-title">Passwort-Einstellungen</div>
        ${row('Mindestlänge', minLen, icon: '🔢')}
        ${row('Passwort-Verlauf', '$histLen Passwörter', icon: '📋')}
        ${row('Max. Gültigkeit', maxPwdAgeDays > 0 ? '$maxPwdAgeDays Tage' : 'Unbegrenzt', icon: '📅')}
        ${row('Min. Gültigkeit', minPwdAgeDays > 0 ? '$minPwdAgeDays Tage' : 'Keine', icon: '⏱')}
        ${row('Komplexitätsanforderung', complexity, icon: '🔐')}
      </div>
      <div class="card card-pad">
        <div class="card-section-title">Kontosperrung</div>
        ${row('Schwellwert (Fehlversuche)', lockoutThreshold == '0' ? 'Deaktiviert' : lockoutThreshold, icon: '🚫')}
        ${row('Sperrdauer', lockoutDurMins > 0 ? '$lockoutDurMins Minuten' : 'Manuell aufheben', icon: '⏳')}
        ${row('Beobachtungsfenster', observeWinMins > 0 ? '$observeWinMins Minuten' : '–', icon: '🔭')}
      </div>
    </div>
    ${policy.isEmpty ? '<div class="alert alert-error">Keine Policy-Daten geladen. Prüfe LDAP-Verbindung.</div>' : ''}
  ''', active: 'policy');
}

// ── Feature: User-Vergleich ───────────────────────────────────────────────────

String renderUserCompareForm(String username, Map<String, dynamic> userA) {
  final dnA = _esc(userA['dn'] ?? '');
  final cnA = _esc(userA['cn'] ?? '–');
  return _layout(username, 'User vergleichen', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/user?dn=${Uri.encodeComponent(userA['dn'] ?? '')}" class="btn btn-ghost btn-sm">← Zurück</a>
      <h2 style="font-size:1rem;font-weight:600;">User vergleichen</h2>
    </div>
    <div class="card card-pad">
      <div style="background:var(--blue-lt);border:1px solid #93c5fd;border-radius:8px;padding:.75rem 1rem;margin-bottom:1rem;">
        <strong>Benutzer A:</strong> $cnA <span style="font:400 .78rem var(--mono);color:var(--gray-500);">$dnA</span>
      </div>
      <form action="/user/compare" method="get">
        <input type="hidden" name="a" value="${userA['dn'] ?? ''}">
        <div style="margin-bottom:1rem;">
          <label style="display:block;font:600 .8rem var(--sans);color:var(--gray-600);margin-bottom:.4rem;">Name oder Benutzername von Benutzer B:</label>
          <input type="text" name="b" required placeholder="z.B. mb0223 oder Max Muster" autofocus
                 style="width:100%;padding:.55rem .85rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
        </div>
        <button type="submit" class="btn btn-primary">⚖ Vergleichen</button>
      </form>
    </div>
  ''', active: 'search');
}

String renderUserCompare(String username, Map<String, dynamic> userA, Map<String, dynamic> userB) {
  const compareAttrs = ['cn', 'mail', 'department', 'title', 'description', 'telephoneNumber', 'company'];
  final attrLabels = {
    'cn': 'Name', 'mail': 'E-Mail', 'department': 'Abteilung', 'title': 'Titel',
    'description': 'Beschreibung', 'telephoneNumber': 'Telefon', 'company': 'Firma',
  };

  final uacA = int.tryParse(userA['userAccountControl']?.toString() ?? '0') ?? 0;
  final uacB = int.tryParse(userB['userAccountControl']?.toString() ?? '0') ?? 0;
  final ltA = int.tryParse(userA['lockoutTime']?.toString() ?? '0') ?? 0;
  final ltB = int.tryParse(userB['lockoutTime']?.toString() ?? '0') ?? 0;
  String statusStr(int uac, int lt) {
    if (lt > 0) return 'Gesperrt';
    if ((uac & 2) != 0) return 'Deaktiviert';
    return 'Aktiv';
  }

  final rows = <String>[];
  for (final attr in compareAttrs) {
    final valA = _esc(userA[attr]?.toString() ?? '');
    final valB = _esc(userB[attr]?.toString() ?? '');
    final isDiff = valA != valB;
    final bg = isDiff ? 'background:rgba(255,200,0,.08);' : '';
    final label = attrLabels[attr] ?? attr;
    rows.add('<tr style="$bg">'
        '<td style="font:600 .8rem var(--mono);color:var(--gray-400);width:130px;">$label</td>'
        '<td style="${isDiff ? 'color:var(--blue);font-weight:600;' : ''}">${valA.isNotEmpty ? valA : '<em style="color:var(--gray-300)">–</em>'}</td>'
        '<td style="${isDiff ? 'color:var(--blue);font-weight:600;' : ''}">${valB.isNotEmpty ? valB : '<em style="color:var(--gray-300)">–</em>'}</td>'
        '</tr>');
  }
  // Status row
  final statA = statusStr(uacA, ltA);
  final statB = statusStr(uacB, ltB);
  final statDiff = statA != statB;
  rows.add('<tr style="${statDiff ? 'background:rgba(255,200,0,.08);' : ''}">'
      '<td style="font:600 .8rem var(--mono);color:var(--gray-400);">Status</td>'
      '<td style="${statDiff ? 'color:var(--blue);font-weight:600;' : ''}">$statA</td>'
      '<td style="${statDiff ? 'color:var(--blue);font-weight:600;' : ''}">$statB</td>'
      '</tr>');

  // Groups comparison
  final groupsA = ((userA['memberOf'] as List?)?.cast<String>() ?? []).map((g) => g.toLowerCase()).toSet();
  final groupsB = ((userB['memberOf'] as List?)?.cast<String>() ?? []).map((g) => g.toLowerCase()).toSet();
  final allGroupDns = [...(userA['memberOf'] as List? ?? []).cast<String>(),
                       ...(userB['memberOf'] as List? ?? []).cast<String>()]
      .toSet().toList()..sort((a, b) => _extractCn(a).compareTo(_extractCn(b)));

  final groupRows = allGroupDns.map((gdn) {
    final inA = groupsA.contains(gdn.toLowerCase());
    final inB = groupsB.contains(gdn.toLowerCase());
    final gName = _extractCn(gdn);
    String style, markers;
    if (inA && inB) {
      style = 'background:var(--gray-50);color:var(--gray-500);';
      markers = '<td style="text-align:center;">✓</td><td style="text-align:center;">✓</td>';
    } else if (inA) {
      style = 'background:#fae9e9;';
      markers = '<td style="text-align:center;color:var(--red);font-weight:700;">✓</td><td style="text-align:center;color:var(--gray-300);">–</td>';
    } else {
      style = 'background:#eaf5ee;';
      markers = '<td style="text-align:center;color:var(--gray-300);">–</td><td style="text-align:center;color:var(--green);font-weight:700;">✓</td>';
    }
    return '<tr style="$style"><td style="font-size:.85rem;">$gName</td>$markers</tr>';
  }).join('\n');

  final cnA = _esc(userA['cn'] ?? 'User A');
  final cnB = _esc(userB['cn'] ?? 'User B');

  return _layout(username, 'Vergleich: $cnA vs $cnB', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/user?dn=${Uri.encodeComponent(userA['dn'] ?? '')}" class="btn btn-ghost btn-sm">← Zurück</a>
      <h2 style="font-size:1rem;font-weight:600;">User-Vergleich</h2>
    </div>
    <div class="card" style="margin-bottom:1rem;">
      <div class="card-pad" style="padding-bottom:.5rem;">
        <div class="card-section-title">Attribute</div>
      </div>
      <table>
        <thead><tr>
          <th style="width:130px;">Attribut</th>
          <th>${cnA}<br><span style="font:400 .7rem var(--mono);color:var(--gray-400);">${_esc(userA['sAMAccountName'] ?? '')}</span></th>
          <th>${cnB}<br><span style="font:400 .7rem var(--mono);color:var(--gray-400);">${_esc(userB['sAMAccountName'] ?? '')}</span></th>
        </tr></thead>
        <tbody>${rows.join('\n')}</tbody>
      </table>
    </div>
    ${allGroupDns.isNotEmpty ? '''
    <div class="card">
      <div class="card-pad" style="padding-bottom:.5rem;">
        <div class="card-section-title">Gruppen</div>
        <div style="display:flex;gap:.5rem;font-size:.78rem;margin-bottom:.5rem;flex-wrap:wrap;">
          <span style="background:#fae9e9;padding:.2rem .5rem;border-radius:4px;color:var(--red);">Nur in $cnA</span>
          <span style="background:#eaf5ee;padding:.2rem .5rem;border-radius:4px;color:var(--green);">Nur in $cnB</span>
          <span style="background:var(--gray-50);padding:.2rem .5rem;border-radius:4px;color:var(--gray-500);">Beide</span>
        </div>
      </div>
      <table>
        <thead><tr><th>Gruppe</th><th style="text-align:center;">$cnA</th><th style="text-align:center;">$cnB</th></tr></thead>
        <tbody>$groupRows</tbody>
      </table>
    </div>''' : ''}
  ''', active: 'search');
}

// ── Feature: Verschachtelte Gruppen ──────────────────────────────────────────

String renderEffectiveGroups(String username, Map<String, dynamic>? user, String dn,
    List<Map<String, dynamic>> groups) {
  final cn = _esc(user?['cn'] ?? _extractCn(dn));
  final sam = _esc(user?['sAMAccountName'] ?? '');
  final direct = groups.where((g) => g['isDirect'] == true).toList();
  final nested = groups.where((g) => g['isDirect'] != true).toList();

  String groupRow(Map<String, dynamic> g, bool isDirect) {
    final gCn = _esc(g['cn'] ?? '–');
    final gDn = _esc(g['dn'] ?? '');
    return '<tr>'
        '<td><strong>$gCn</strong></td>'
        '<td style="font:400 .72rem var(--mono);color:var(--gray-400);">$gDn</td>'
        '<td>${isDirect ? '<span class="badge badge-active">Direkt</span>' : '<span class="badge" style="background:var(--blue-lt);color:var(--blue);">Verschachtelt</span>'}</td>'
        '</tr>';
  }

  final allRows = [
    ...direct.map((g) => groupRow(g, true)),
    ...nested.map((g) => groupRow(g, false)),
  ].join('\n');

  return _layout(username, 'Effektive Gruppen', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/user?dn=${Uri.encodeComponent(dn)}" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Effektive Gruppen: $cn</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">$sam · ${groups.length} Gruppen total (${direct.length} direkt, ${nested.length} verschachtelt)</p>
      </div>
    </div>
    <div class="card">
      ${groups.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine Gruppen gefunden.</em></div>'
        : '''
        <table class="result-table">
          <thead><tr><th>Gruppe</th><th>DN</th><th>Typ</th></tr></thead>
          <tbody>$allRows</tbody>
        </table>'''}
    </div>
  ''', active: 'search');
}

// ── Feature: CSV Bulk-Update ──────────────────────────────────────────────────


// ── Feature: Computer-Browser ─────────────────────────────────────────────────

String renderComputers(String username, List<Map<String, dynamic>> computers) {
  final lagerOu = _appLagerOu;
  final rows = computers.map((c) {
    final cn = _esc(c['cn'] ?? '–');
    final dn = _esc(c['dn'] ?? '');
    final dns = _esc(c['dNSHostName'] ?? '–');
    final os = _esc(c['operatingSystem'] ?? '–');
    final osVer = _esc(c['operatingSystemVersion'] ?? '');
    final lastLogon = _formatFileTime(c['lastLogonTimestamp']?.toString());
    final desc = _esc(c['description'] ?? '');
    final isAlreadyInLager = (c['dn'] as String? ?? '').toLowerCase().contains('lager_deaktivierte');
    final lagerBtn = isAlreadyInLager
        ? '<span style="font-size:.75rem;color:var(--gray-400);padding:.35rem .6rem;">Im Lager</span>'
        : '''<form method="post" action="/computer/move-lager" style="margin:0;"
               onsubmit="return confirm('Gerät $cn wirklich ins Lager verschieben?')">
             <input type="hidden" name="dn" value="$dn">
             <input type="hidden" name="target_ou" value="${_esc(lagerOu)}">
             <button type="submit"
               style="background:#f97316;color:#fff;border:none;border-radius:6px;padding:.35rem .75rem;font:600 .78rem var(--sans);cursor:pointer;white-space:nowrap;letter-spacing:.01em;box-shadow:0 1px 4px rgba(249,115,22,.35);"
               title="Ins Lager verschieben">&#128230; Ins Lager</button>
           </form>''';
    return '<tr>'
        '<td><strong>$cn</strong></td>'
        '<td style="font:400 .8rem var(--mono);">$dns</td>'
        '<td>$os${osVer.isNotEmpty ? '<br><span style="font-size:.72rem;color:var(--gray-400);">$osVer</span>' : ''}</td>'
        '<td>$lastLogon</td>'
        '<td style="font-size:.82rem;color:var(--gray-400);">$desc</td>'
        '<td>$lagerBtn</td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Computer', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Computer-Browser</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">${computers.length} Computer im Verzeichnis</p>
      </div>
    </div>
    <div class="card card-pad" style="margin-bottom:1rem;">
      <input type="text" id="computer-search" placeholder="Computer suchen..." autofocus
             oninput="filterComputers(this.value)"
             style="width:100%;padding:.65rem 1rem;border:1.5px solid var(--gray-200);border-radius:8px;font:400 14px var(--sans);">
    </div>
    <div class="card">
      ${computers.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine Computer gefunden.</em></div>'
        : '''
        <table class="result-table" id="computer-table">
          <thead><tr><th>Name</th><th>DNS-Name</th><th>Betriebssystem</th><th>Letzter Login</th><th>Beschreibung</th><th></th></tr></thead>
          <tbody>$rows</tbody>
        </table>'''}
    </div>
    <script>
    function filterComputers(q) {
      q = q.toLowerCase().trim();
      document.querySelectorAll('#computer-table tbody tr').forEach(function(row) {
        var text = row.textContent.toLowerCase();
        row.style.display = (!q || text.includes(q)) ? '' : 'none';
      });
    }
    </script>
  ''', active: 'computers');
}

// ── Feature: Erweiterte Suche ─────────────────────────────────────────────────

String renderAdvancedSearch(String username, List<Map<String, dynamic>> ous,
    Map<String, String> params, List<Map<String, dynamic>>? results) {
  final ouOptions = ous.toList()
      ..sort((a, b) => (a['ou'] ?? a['dn'] ?? '').compareTo(b['ou'] ?? b['dn'] ?? ''));
  final ouOptHtml = ouOptions.map((o) {
    final label = _esc(o['ou'] as String? ?? o['dn'] as String? ?? '');
    final val = _esc(o['dn'] as String? ?? '');
    final selected = val == _esc(params['ou'] ?? '') ? ' selected' : '';
    return '<option value="$val"$selected>$label</option>';
  }).join('\n');

  final statusOptions = [
    ('all', 'Alle'), ('active', 'Aktiv'), ('disabled', 'Deaktiviert'), ('locked', 'Gesperrt'),
  ].map((opt) {
    final selected = (params['status'] ?? 'all') == opt.$1 ? ' selected' : '';
    return '<option value="${opt.$1}"$selected>${opt.$2}</option>';
  }).join('\n');

  String? resultsHtml;
  if (results != null) {
    final rows = results.map((u) {
      final dn = u['dn'] ?? '';
      final cn = _esc(u['cn'] ?? '–');
      final sam = _esc(u['sAMAccountName'] ?? '–');
      final mail = _esc(u['mail'] ?? '–');
      final dept = _esc(u['department'] ?? '–');
      final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
      final lt = int.tryParse(u['lockoutTime']?.toString() ?? '0') ?? 0;
      final badge = lt > 0
          ? '<span class="badge badge-locked">Gesperrt</span>'
          : (uac & 2) != 0
              ? '<span class="badge badge-disabled">Inaktiv</span>'
              : '<span class="badge badge-active">Aktiv</span>';
      final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
      return '<tr onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">'
          '<td><strong>$cn</strong></td><td>$sam</td><td>$mail</td><td>$dept</td><td>$badge</td>'
          '</tr>';
    }).join('\n');

    resultsHtml = '''
      <div class="card" style="margin-top:1rem;">
        ${results.isEmpty
          ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine Benutzer gefunden.</em></div>'
          : '''
          <div class="card-pad" style="padding-bottom:.5rem;">
            <span style="font:500 .82rem var(--sans);color:var(--gray-500);">${results.length} Benutzer</span>
          </div>
          <table class="result-table">
            <thead><tr><th>Name</th><th>Benutzername</th><th>E-Mail</th><th>Abteilung</th><th>Status</th></tr></thead>
            <tbody>$rows</tbody>
          </table>'''}
      </div>''';
  }

  return _layout(username, 'Erweiterte Suche', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <h2 style="font-size:1rem;font-weight:600;">Erweiterte Suche</h2>
    </div>
    <div class="card card-pad">
      <form action="/search/advanced" method="get">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin-bottom:1rem;">
          <div>
            <label style="display:block;font:600 .8rem var(--sans);color:var(--gray-600);margin-bottom:.3rem;">Name / Benutzername</label>
            <input type="text" name="name" value="${_esc(params['name'] ?? '')}" placeholder="z.B. Muster" autofocus
                   style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
          <div>
            <label style="display:block;font:600 .8rem var(--sans);color:var(--gray-600);margin-bottom:.3rem;">Abteilung</label>
            <input type="text" name="department" value="${_esc(params['department'] ?? '')}" placeholder="z.B. IT"
                   style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
          <div>
            <label style="display:block;font:600 .8rem var(--sans);color:var(--gray-600);margin-bottom:.3rem;">OU einschränken</label>
            <select name="ou" style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;background:white;">
              <option value="">Alle OUs</option>
              $ouOptHtml
            </select>
          </div>
          <div>
            <label style="display:block;font:600 .8rem var(--sans);color:var(--gray-600);margin-bottom:.3rem;">Status</label>
            <select name="status" style="width:100%;padding:.5rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;background:white;">
              $statusOptions
            </select>
          </div>
        </div>
        <div style="display:flex;gap:.75rem;">
          <button type="submit" class="btn btn-primary">Suchen</button>
          <a href="/search/advanced" class="btn btn-ghost">Zurücksetzen</a>
        </div>
      </form>
    </div>
    ${resultsHtml ?? ''}
  ''', active: 'advsearch');
}

// ── Feature 1: Org-Chart ──────────────────────────────────────────────────────

String renderOrgChartForm(String username) => _layout(username, 'Org-Chart', '''
  <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
    <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
    <div>
      <h2 style="font-size:1rem;font-weight:600;">Org-Chart / Manager-Hierarchie</h2>
      <p style="font-size:.78rem;color:var(--gray-400);">Vorgesetzten-Kette und direkte Berichte anzeigen</p>
    </div>
  </div>
  <div class="card card-pad">
    <form action="/orgchart" method="get" class="search-box">
      <input type="text" name="dn" placeholder="Distinguished Name eingeben (z.B. CN=Max Muster,OU=Users,DC=...)" autofocus style="font-size:.85rem;">
      <button type="submit" class="btn btn-primary">Anzeigen</button>
    </form>
    <p style="font-size:.78rem;color:var(--gray-400);margin-top:.75rem;">Tipp: Zuerst einen Benutzer suchen, dann via "Org-Chart" öffnen.</p>
  </div>
''', active: 'orgchart');

String _orgCard(Map<String, dynamic> u, {bool isMain = false, bool isManager = false}) {
  final dn = u['dn'] as String? ?? '';
  final cn = _esc(u['cn'] as String? ?? '–');
  final title = _esc(u['title'] as String? ?? '');
  final dept = _esc(u['department'] as String? ?? '');
  final initial = cn.isNotEmpty ? cn[0].toUpperCase() : '?';
  final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
  final disabled = (uac & 2) != 0;
  final color = isMain ? 'var(--blue)' : (isManager ? 'var(--gray-500)' : 'var(--green)');
  final bgColor = isMain ? 'var(--blue-lt)' : (isManager ? 'var(--gray-100)' : 'var(--green-lt)');
  final border = isMain ? '2px solid var(--blue)' : '1px solid var(--gray-200)';
  final size = isMain ? '200px' : '160px';
  final photo = u['jpegPhoto'] as String?;
  final avatarHtml = photo != null && photo.isNotEmpty
      ? '<img src="$photo" style="width:${isMain ? '48px' : '36px'};height:${isMain ? '48px' : '36px'};border-radius:50%;object-fit:cover;border:2px solid white;">'
      : '<div style="width:${isMain ? '48px' : '36px'};height:${isMain ? '48px' : '36px'};border-radius:50%;background:$color;color:white;display:flex;align-items:center;justify-content:center;font:700 ${isMain ? '18px' : '14px'} var(--mono);border:2px solid white;">$initial</div>';

  return '''<a href="/orgchart?dn=${Uri.encodeComponent(dn)}" style="text-decoration:none;display:flex;flex-direction:column;align-items:center;gap:.4rem;background:var(--surface);border:$border;border-radius:10px;padding:.85rem .75rem;width:$size;transition:box-shadow .15s,transform .15s;${disabled ? 'opacity:.65;' : ''}" onmouseover="this.style.boxShadow='var(--shadow-md)';this.style.transform='translateY(-2px)'" onmouseout="this.style.boxShadow='';this.style.transform=''">
    $avatarHtml
    <div style="text-align:center;">
      <div style="font:600 ${isMain ? '14px' : '12px'} var(--sans);color:var(--gray-800);">$cn</div>
      ${title.isNotEmpty ? '<div style="font-size:.72rem;color:var(--gray-400);margin-top:2px;">$title</div>' : ''}
      ${dept.isNotEmpty ? '<div style="font-size:.68rem;color:var(--gray-400);">$dept</div>' : ''}
    </div>
  </a>''';
}

String renderOrgChart(String username, Map<String, dynamic> user,
    List<Map<String, dynamic>> managers, List<Map<String, dynamic>> reports) {
  final cn = _esc(user['cn'] as String? ?? '–');
  final dn = user['dn'] as String? ?? '';

  final managerCards = managers.map((m) => _orgCard(m, isManager: true)).join(
    '<div style="display:flex;flex-direction:column;align-items:center;padding:.2rem 0;"><div style="width:1px;height:20px;background:var(--gray-300);"></div><div style="width:6px;height:6px;border-radius:50%;background:var(--gray-300);"></div></div>'
  );

  final reportCards = reports.isEmpty ? '' : reports.map((r) => _orgCard(r)).join('\n');

  return _layout(username, 'Org-Chart: $cn', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1.5rem;">
      <a href="/orgchart" class="btn btn-ghost btn-sm">← Org-Chart</a>
      <a href="/user?dn=${Uri.encodeComponent(dn)}" class="btn btn-ghost btn-sm">👤 Profil</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Org-Chart: $cn</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">${managers.length} Vorgesetzte · ${reports.length} direkte Berichte</p>
      </div>
    </div>

    <div style="display:flex;flex-direction:column;align-items:center;gap:0;">
      ${managers.isNotEmpty ? '''
      <div style="display:flex;flex-direction:column;align-items:center;gap:0;">
        $managerCards
        <div style="width:1px;height:20px;background:var(--gray-300);margin:.2rem 0;"></div>
        <div style="width:6px;height:6px;border-radius:50%;background:var(--gray-300);"></div>
        <div style="width:1px;height:20px;background:var(--blue);margin-bottom:.2rem;"></div>
      </div>''' : ''}

      <!-- Aktueller User -->
      ${_orgCard(user, isMain: true)}

      ${reports.isNotEmpty ? '''
      <div style="display:flex;flex-direction:column;align-items:center;">
        <div style="width:1px;height:24px;background:var(--blue);margin:.2rem 0;"></div>
        <div style="height:1px;width:${(reports.length * 176).clamp(0, 800)}px;max-width:90vw;background:var(--gray-300);"></div>
        <div style="display:flex;flex-wrap:wrap;gap:1rem;justify-content:center;margin-top:.5rem;">
          $reportCards
        </div>
      </div>''' : '<div style="text-align:center;margin-top:1rem;font-size:.82rem;color:var(--gray-400);">Keine direkten Berichte</div>'}
    </div>
  ''', active: 'orgchart');
}

// ── Feature 2: Telefonverzeichnis ─────────────────────────────────────────────

String renderDirectory(String username, List<Map<String, dynamic>> users) {
  final rows = users.map((u) {
    final dn = u['dn'] as String? ?? '';
    final cn = _esc(u['cn'] as String? ?? '–');
    final sam = _esc(u['sAMAccountName'] as String? ?? '–');
    final dept = _esc(u['department'] as String? ?? '–');
    final phone = _esc(u['telephoneNumber'] as String? ?? '');
    final mobile = _esc(u['mobile'] as String? ?? '');
    final mail = _esc(u['mail'] as String? ?? '');
    final initial = cn.isNotEmpty ? cn[0].toUpperCase() : '?';
    final uac = int.tryParse(u['userAccountControl']?.toString() ?? '0') ?? 0;
    final disabled = (uac & 2) != 0;
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
    // Nur Ziffern aus Nummern, für Teilnummern-Suche (z.B. letzte 4 Ziffern)
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final mobileDigits = mobile.replaceAll(RegExp(r'\D'), '');
    return '<tr class="dir-row" '
        'data-name="${cn.toLowerCase()} ${sam.toLowerCase()}" '
        'data-dept="${dept.toLowerCase()}" '
        'data-phone="$phoneDigits $mobileDigits">'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;"><div class="avatar-placeholder">$initial</div></td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;"><strong>${disabled ? '<s>' : ''}$cn${disabled ? '</s>' : ''}</strong><br><span style="font-size:.75rem;color:var(--gray-400);">$sam</span></td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;font-size:.9rem;">$dept</td>'
        '<td style="font-size:.9rem;white-space:nowrap;">${phone.isNotEmpty ? '<a href="tel:$phone" style="color:inherit;text-decoration:none;">📞 $phone</a>' : '<em style="color:var(--gray-300);">–</em>'}</td>'
        '<td style="font-size:.9rem;white-space:nowrap;">${mobile.isNotEmpty ? '<a href="tel:$mobile" style="color:inherit;text-decoration:none;">📱 $mobile</a>' : '<em style="color:var(--gray-300);">–</em>'}</td>'
        '<td style="font-size:.9rem;">${mail.isNotEmpty ? '<a href="mailto:$mail" style="color:var(--blue);text-decoration:none;">$mail</a>' : '<em style="color:var(--gray-300);">–</em>'}</td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Telefonverzeichnis', '''
    <style>
      .dir-filter-wrap { display:flex; gap:.75rem; flex-wrap:wrap; }
      .dir-filter-wrap input { flex:1; min-width:180px; padding:.6rem .9rem; border:1.5px solid var(--gray-200); border-radius:8px; font:400 14px var(--sans); transition:border-color .15s,box-shadow .15s; }
      .dir-filter-wrap input:focus { outline:none; border-color:var(--blue); box-shadow:0 0 0 3px rgba(37,99,235,.1); }
      .dir-filter-wrap .filter-label { display:block; font:600 10px var(--sans); letter-spacing:.06em; text-transform:uppercase; color:var(--gray-400); margin-bottom:.3rem; }
      #dir-count { font:500 13px var(--sans); color:var(--gray-400); padding:.5rem 1rem .25rem; }
    </style>
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;flex-wrap:wrap;">
      <div style="flex:1;">
        <h2 style="font-size:1.05rem;font-weight:700;">Telefonliste</h2>
        <p style="font-size:.82rem;color:var(--gray-400);margin-top:.15rem;">${users.length} Einträge · Telefon &amp; Mobil</p>
      </div>
      <a href="/export/directory" class="btn btn-ghost btn-sm">⬇ CSV exportieren</a>
    </div>

    <div class="card card-pad" style="margin-bottom:1rem;">
      <div class="dir-filter-wrap">
        <div style="flex:2;min-width:200px;">
          <span class="filter-label">Name oder Abteilung</span>
          <input type="text" id="dir-filter-name"
                 placeholder="z.B. Müller oder IT-Abteilung"
                 oninput="dirFilter()">
        </div>
        <div style="flex:1;min-width:160px;">
          <span class="filter-label">Telefon / Mobil (Teilnummer)</span>
          <input type="text" id="dir-filter-phone"
                 placeholder="z.B. 1234 oder +41 79"
                 oninput="dirFilter()">
        </div>
      </div>
      <div id="dir-count" style="display:none;"></div>
    </div>

    <div class="card">
      <div class="table-wrap">
        <table class="result-table" id="dir-table">
          <thead><tr>
            <th style="width:44px;"></th>
            <th>Name</th>
            <th>Abteilung</th>
            <th>Telefon</th>
            <th>Mobil</th>
            <th>E-Mail</th>
          </tr></thead>
          <tbody>$rows</tbody>
        </table>
      </div>
      ${users.isEmpty ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine Einträge gefunden.</em></div>' : ''}
    </div>

    <script>
    function dirFilter() {
      var nameQ = (document.getElementById('dir-filter-name').value || '').toLowerCase().trim();
      var rawPhone = (document.getElementById('dir-filter-phone').value || '').trim();
      // Nur Ziffern aus der Eingabe — so matcht "079 123 45 67" auch auf "1234"
      var phoneQ = rawPhone.replace(/\\D/g, '');

      var rows = document.querySelectorAll('#dir-table .dir-row');
      var visible = 0;
      rows.forEach(function(row) {
        var nameOk = !nameQ ||
          row.dataset.name.includes(nameQ) ||
          row.dataset.dept.includes(nameQ);
        var phoneOk = !phoneQ ||
          row.dataset.phone.replace(/\\s/g,'').includes(phoneQ);
        var show = nameOk && phoneOk;
        row.style.display = show ? '' : 'none';
        if (show) visible++;
      });

      var countEl = document.getElementById('dir-count');
      if (nameQ || phoneQ) {
        countEl.style.display = '';
        countEl.textContent = visible + ' von ${users.length} Einträgen';
      } else {
        countEl.style.display = 'none';
      }
    }
    </script>
  ''', active: 'directory');
}

// ── Feature 3: Abteilungs-Statistik ──────────────────────────────────────────

String renderDeptStats(String username, List<MapEntry<String, int>> depts) {
  final maxCount = depts.isEmpty ? 1 : depts.first.value;
  final colors = ['#2563eb', '#3b82f6', '#60a5fa', '#6ea6f5', '#4aafdb', '#3dbfa0', '#3dc97a'];

  var _barIdx = 0;
  final bars = depts.map((e) {
    final i = _barIdx++;
    final name = _esc(e.key);
    final count = e.value;
    final width = (count / maxCount * 100).toStringAsFixed(1);
    final color = colors[i % colors.length];
    final searchLink = '/search/advanced?department=${Uri.encodeComponent(e.key)}';
    return '''<a href="$searchLink" style="text-decoration:none;display:flex;align-items:center;gap:.75rem;padding:.45rem 0;border-bottom:1px solid var(--gray-100);" onmouseover="this.style.background='var(--gray-50)'" onmouseout="this.style.background=''">
      <div style="width:180px;flex-shrink:0;font:500 .85rem var(--sans);color:var(--gray-700);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="$name">$name</div>
      <div style="flex:1;height:18px;background:var(--gray-100);border-radius:4px;overflow:hidden;">
        <div style="height:100%;width:$width%;background:$color;border-radius:4px;transition:width .3s;"></div>
      </div>
      <div style="width:40px;text-align:right;font:600 .85rem var(--mono);color:var(--gray-700);">$count</div>
    </a>''';
  }).join('\n');

  return _layout(username, 'Abteilungen', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Abteilungs-Statistik</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">Aktive Benutzer nach Abteilung (Top ${depts.length})</p>
      </div>
    </div>
    <div class="card card-pad">
      ${depts.isEmpty
        ? '<em style="color:var(--gray-400);">Keine Daten vorhanden.</em>'
        : '<div style="display:flex;flex-direction:column;">$bars</div>'}
    </div>
  ''', active: 'depts');
}

// ── Feature 4: Bulk PW-Reset ──────────────────────────────────────────────────


// ── Feature 5: Ablaufende Accounts ───────────────────────────────────────────

String renderExpiringAccounts(String username, List<Map<String, dynamic>> users) {
  final rows = users.map((u) {
    final dn = u['dn'] as String? ?? '';
    final cn = _esc(u['cn'] as String? ?? '–');
    final sam = _esc(u['sAMAccountName'] as String? ?? '–');
    final daysLeft = u['_daysLeft'] as int? ?? 0;
    final expiry = u['_expiry'];
    String expiryStr = '–';
    if (expiry is DateTime) {
      expiryStr = '${expiry.day.toString().padLeft(2,'0')}.${expiry.month.toString().padLeft(2,'0')}.${expiry.year}';
    }
    final colorClass = daysLeft < 7 ? 'badge-disabled' : (daysLeft < 15 ? 'badge-locked' : 'badge-active');
    final detailUrl = '/user?dn=${Uri.encodeComponent(dn)}';
    return '<tr>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;"><strong>$cn</strong></td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">$sam</td>'
        '<td onclick="location.href=\'$detailUrl\'" style="cursor:pointer;">$expiryStr</td>'
        '<td><span class="badge $colorClass">$daysLeft Tage</span></td>'
        '<td><a href="$detailUrl" class="btn btn-ghost btn-xs">Details</a></td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Ablaufende Accounts', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <a href="/" class="btn btn-ghost btn-sm">← Zurück</a>
      <div>
        <h2 style="font-size:1rem;font-weight:600;">Ablaufende Accounts</h2>
        <p style="font-size:.78rem;color:var(--gray-400);">Accounts die in den nächsten 30 Tagen ablaufen (${users.length} gefunden)</p>
      </div>
    </div>
    <div style="display:flex;gap:.65rem;margin-bottom:.85rem;flex-wrap:wrap;">
      <span class="badge badge-disabled">Rot: &lt; 7 Tage</span>
      <span class="badge badge-locked">Gelb: 7–14 Tage</span>
      <span class="badge badge-active">Grün: 15–30 Tage</span>
    </div>
    <div class="card">
      ${users.isEmpty
        ? '<div class="card-pad"><em style="color:var(--gray-400);">Keine ablaufenden Accounts in den nächsten 30 Tagen.</em></div>'
        : '''<table class="result-table">
          <thead><tr>
            <th>Name</th><th>Benutzername</th><th>Ablaufdatum</th><th>Tage bis Ablauf</th><th></th>
          </tr></thead>
          <tbody>$rows</tbody>
        </table>'''}
    </div>
  ''', active: 'expiring');
}

// ── Konfigurations-UI ────────────────────────────────────────────────────────

String renderConfigPage(String username, dynamic config, {bool saved = false, String csrfToken = ''}) {
  // config is a Config object with fields: server, port, useSsl, bindUser, bindPassword, baseDn
  final server      = _esc(config.server?.toString() ?? '');
  final port        = _esc(config.port?.toString() ?? '389');
  final ssl         = config.useSsl == true ? 'true' : 'false';
  final bindUser    = _esc(config.bindUser?.toString() ?? '');
  final baseDn      = _esc(config.baseDn?.toString() ?? '');

  return _layout(username, 'Konfiguration', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <h2 style="font-size:1rem;font-weight:600;">Konfiguration</h2>
    </div>
    ${saved ? '<div class="alert alert-success" style="margin-bottom:1rem;"><svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 8.5l3.5 3.5 6.5-7" stroke-linecap="round" stroke-linejoin="round"/></svg>Konfiguration gespeichert.</div>' : ''}
    <div class="card card-pad">
      <form method="post" action="/config">
        <input type="hidden" name="_csrf" value="${_esc(csrfToken)}">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1.25rem 2rem;margin-bottom:1.5rem;">
          <div>
            <label style="display:block;font:600 .7rem var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);margin-bottom:.4rem;">LDAP-Server</label>
            <input type="text" name="AD_SERVER" value="$server" placeholder="10.1.200.23" style="width:100%;padding:.55rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
          <div>
            <label style="display:block;font:600 .7rem var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);margin-bottom:.4rem;">Port</label>
            <input type="text" name="AD_PORT" value="$port" placeholder="636" style="width:100%;padding:.55rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
          <div>
            <label style="display:block;font:600 .7rem var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);margin-bottom:.4rem;">SSL/TLS</label>
            <select name="AD_SSL" style="width:100%;padding:.55rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;background:white;">
              <option value="true"${ssl == 'true' ? ' selected' : ''}>Ja (empfohlen)</option>
              <option value="false"${ssl == 'false' ? ' selected' : ''}>Nein</option>
            </select>
          </div>
          <div>
            <label style="display:block;font:600 .7rem var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);margin-bottom:.4rem;">Base DN</label>
            <input type="text" name="BASE_DN" value="$baseDn" placeholder="DC=suedostschweiz,DC=ch" style="width:100%;padding:.55rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
          <div>
            <label style="display:block;font:600 .7rem var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);margin-bottom:.4rem;">Bind-Benutzer (DN)</label>
            <input type="text" name="AD_USER" value="$bindUser" placeholder="CN=svc_ldap,OU=Service,DC=..." style="width:100%;padding:.55rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
          <div>
            <label style="display:block;font:600 .7rem var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--gray-400);margin-bottom:.4rem;">Bind-Passwort (leer = unverändert)</label>
            <input type="password" name="AD_PASSWORD" placeholder="••••••••" autocomplete="new-password" style="width:100%;padding:.55rem .8rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.9rem;">
          </div>
        </div>
        <div style="display:flex;gap:.75rem;">
          <button type="submit" class="btn btn-primary">Speichern</button>
          <a href="/" class="btn btn-ghost">Abbrechen</a>
        </div>
      </form>
    </div>
    <div class="card card-pad" style="margin-top:1rem;background:var(--amber-lt);border-color:#fcd34d;">
      <p style="font:500 .82rem var(--sans);color:var(--amber);">
        <strong>Hinweis:</strong> Änderungen werden sofort in der .env-Datei gespeichert und im laufenden Prozess aktualisiert.
        LDAP-Verbindungen werden beim nächsten Request mit den neuen Werten aufgebaut.
      </p>
    </div>
  ''', active: 'config', csrfToken: csrfToken);
}

// ── Rollen-Verwaltung ────────────────────────────────────────────────────────

String renderRolesPage(String username, Map<String, dynamic> roles, {String csrfToken = ''}) {
  final rolesList = roles.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  String roleOption(String key, dynamic current, String val, String label) =>
      '<option value="$val"${current.toString() == val ? ' selected' : ''}>$label</option>';

  final rows = rolesList.map((e) {
    final u = _esc(e.key);
    final role = e.value.toString();
    return '<tr>'
        '<td style="font:500 .88rem var(--mono);">$u</td>'
        '<td><select name="${_esc(e.key)}" style="padding:.3rem .6rem;border:1px solid var(--gray-200);border-radius:6px;font-size:.85rem;">'
        '${roleOption(e.key, role, 'admin', 'Admin (alles)')} '
        '${roleOption(e.key, role, 'operator', 'Operator (keine Attribut-Bearbeitung)')} '
        '${roleOption(e.key, role, 'readonly', 'Nur-Lesen')}'
        '</select></td>'
        '</tr>';
  }).join('\n');

  return _layout(username, 'Benutzer-Rollen', '''
    <div style="display:flex;align-items:center;gap:.75rem;margin-bottom:1rem;">
      <h2 style="font-size:1rem;font-weight:600;">Benutzer-Rollen</h2>
    </div>
    <div class="card card-pad" style="margin-bottom:1rem;background:var(--blue-lt);border-color:rgba(37,99,235,.3);">
      <p style="font:500 .82rem var(--sans);color:var(--blue);">
        Rollen werden in <code>roles.json</code> neben der ldap_tool.exe gespeichert.
        Benutzer ohne Eintrag erhalten automatisch die Rolle <strong>Admin</strong>.
      </p>
    </div>
    <div class="card card-pad">
      <form method="post" action="/admin/roles">
        <input type="hidden" name="_csrf" value="${_esc(csrfToken)}">
        ${rolesList.isEmpty
          ? '<p style="color:var(--gray-400);font-size:.85rem;">Keine benutzerdefinierten Rollen vorhanden. Alle angemeldeten Benutzer sind standardmäßig Admin.</p>'
          : '''<table class="result-table" style="margin-bottom:1.25rem;">
            <thead><tr><th>Benutzername</th><th>Rolle</th></tr></thead>
            <tbody>$rows</tbody>
          </table>'''}
        <div style="margin-top:.5rem;">
          <h3 style="font:600 .8rem var(--mono);text-transform:uppercase;letter-spacing:.1em;color:var(--gray-400);margin-bottom:.75rem;">Neuen Benutzer hinzufügen</h3>
          <div style="display:flex;gap:.6rem;flex-wrap:wrap;align-items:center;">
            <input type="text" name="_new_user_name_display" id="new-role-user" placeholder="Benutzername (sAMAccountName)" style="flex:1;min-width:180px;padding:.45rem .75rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.88rem;">
            <select id="new-role-val" style="padding:.45rem .75rem;border:1.5px solid var(--gray-200);border-radius:7px;font-size:.88rem;">
              <option value="admin">Admin</option>
              <option value="operator">Operator</option>
              <option value="readonly">Nur-Lesen</option>
            </select>
            <button type="button" class="btn btn-ghost btn-sm" onclick="addRoleRow()">+ Hinzufügen</button>
          </div>
          <div id="new-role-rows"></div>
        </div>
        <div style="margin-top:1.25rem;display:flex;gap:.75rem;">
          <button type="submit" class="btn btn-primary">Rollen speichern</button>
          <a href="/" class="btn btn-ghost">Abbrechen</a>
        </div>
      </form>
    </div>
    <script>
    function addRoleRow() {
      var u = document.getElementById('new-role-user').value.trim();
      var r = document.getElementById('new-role-val').value;
      if (!u) return;
      var form = document.querySelector('form[action="/admin/roles"]');
      var inp = document.createElement('input');
      inp.type = 'hidden'; inp.name = u; inp.value = r;
      form.appendChild(inp);
      var container = document.getElementById('new-role-rows');
      container.innerHTML += '<div style="padding:.35rem .6rem;margin-top:.4rem;background:var(--gray-50);border-radius:6px;font:.88rem var(--mono);color:var(--gray-600);">' + u + ' → ' + r + '</div>';
      document.getElementById('new-role-user').value = '';
    }
    </script>
  ''', active: 'roles', csrfToken: csrfToken);
}

// ── Verbindungsfehler-Seite ───────────────────────────────────────────────────

String renderConnectionError(String username, String message) =>
    _layout(username, 'Verbindungsfehler', '''
    <div class="card card-pad" style="max-width:520px;margin:2rem auto;text-align:center;">
      <div style="width:56px;height:56px;border-radius:50%;background:var(--red-lt);color:var(--red);display:flex;align-items:center;justify-content:center;margin:0 auto 1rem;">
        <svg width="24" height="24" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="8" cy="8" r="6.5"/><line x1="8" y1="5" x2="8" y2="8.5" stroke-linecap="round"/><circle cx="8" cy="11" r=".5" fill="currentColor" stroke="none"/></svg>
      </div>
      <h2 style="font:600 16px var(--sans);color:var(--gray-800);margin-bottom:.5rem;">Verbindungsfehler</h2>
      <p style="font-size:.875rem;color:var(--gray-500);margin-bottom:1.5rem;">${_esc(message)}</p>
      <div style="display:flex;gap:.75rem;justify-content:center;">
        <button onclick="location.reload()" class="btn btn-primary">Erneut versuchen</button>
        <a href="/" class="btn btn-ghost">Zum Dashboard</a>
      </div>
    </div>
  ''');

