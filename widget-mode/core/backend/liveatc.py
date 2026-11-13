"""On-demand public feed lookup; no crawling, proxying, or access-control bypass."""
from html.parser import HTMLParser
import re
from urllib.parse import urljoin, urlsplit, parse_qs
from urllib.request import Request, urlopen


def station_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError('Enter a LiveATC stream or listen URL')
    parsed = urlsplit(value.strip())
    host = parsed.hostname or ''
    if parsed.scheme not in ('https', 'http') or parsed.username or parsed.password or not (host == 'liveatc.net' or host.endswith('.liveatc.net')):
        raise ValueError('Use an http(s) address hosted by LiveATC.net')
    if parsed.path == '/hlisten.php':
        mount = parse_qs(parsed.query).get('mount', [''])[0]
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', mount):
            raise ValueError('This listen address has no valid feed ID')
        return f'https://www.liveatc.net/play/{mount}.pls'
    return value.strip()


class FeedLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.feeds = {}

    def handle_starttag(self, tag, attrs):
        if tag != 'a':
            return
        href = dict(attrs).get('href', '')
        url = urljoin('https://www.liveatc.net/', href)
        parsed = urlsplit(url)
        mount = parse_qs(parsed.query).get('mount', [''])[0] if parsed.path == '/hlisten.php' else ''
        if not mount:
            match = re.fullmatch(r'/play/([A-Za-z0-9_-]+)\.(?:pls|m3u)', parsed.path)
            mount = match[1] if match else ''
        if re.fullmatch(r'[A-Za-z0-9_-]{1,100}', mount):
            self.feeds[mount] = {'name': mount, 'url': station_url(f'https://www.liveatc.net/hlisten.php?mount={mount}')}


def search(code):
    code = code.upper().strip() if isinstance(code, str) else ''
    if not re.fullmatch(r'[A-Z0-9]{3,4}', code):
        raise ValueError('Use a 3–4 character airport code')
    request = Request(f'https://www.liveatc.net/search/?icao={code}', headers={'User-Agent':'someProducts-monitor/1.24 (personal desktop player)'})
    with urlopen(request, timeout=7) as response:
        html = response.read(1_000_001)
        if len(html) > 1_000_000:
            raise ValueError('Search response is too large')
    parser = FeedLinks()
    parser.feed(html.decode('utf-8', errors='replace'))
    return list(parser.feeds.values())[:60]


def resolve(value):
    url = station_url(value)
    if urlsplit(url).path.lower().endswith(('.pls', '.m3u')):
        with urlopen(Request(url, headers={'User-Agent':'someProducts-monitor/1.24'}), timeout=7) as response:
            data = response.read(32769)
            if len(data) > 32768:
                raise ValueError('Playlist is too large')
        for line in data.decode('utf-8', errors='replace').splitlines():
            candidate = line.split('=', 1)[1].strip() if line.lower().startswith('file1=') else line.strip()
            if candidate.startswith(('https://', 'http://')):
                return station_url(candidate)
        raise ValueError('Playlist contains no playable LiveATC stream')
    if urlsplit(url).path.lower().endswith(('.php', '.html', '/')):
        raise ValueError('Use a feed Listen URL or direct stream, not a web page')
    return url
