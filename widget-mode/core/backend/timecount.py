"""Durable, append-only-by-API project time; no reset, subtraction or delete."""
from datetime import date, datetime, time as day_time, timedelta
import os
from pathlib import Path
import re
import sqlite3
import threading
import time


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', value):
        raise ValueError('Use a 1–64 character identifier')
    return value


def projects_list(value):
    if not isinstance(value, list) or not 0 <= len(value) <= 32:
        raise ValueError('Use at most 32 projects')
    seen = set()
    for row in value:
        if not isinstance(row, dict) or set(row) != {'id', 'name'}:
            raise ValueError('Projects require id and name')
        key = identifier(row['id'])
        if key in seen:
            raise ValueError('Duplicate project ID')
        seen.add(key)
        name = row['name']
        if not isinstance(name, str) or not name.strip() or len(name) > 64 or any(ord(c) < 32 for c in name):
            raise ValueError('Use a readable project name of 1–64 characters')
    return value


class TimecountStore:
    LEASE = 6.0

    def __init__(self, path=None, monotonic=time.monotonic, wall=time.time, timezone=None):
        self.path = Path(path) if path else Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/'monitor-dashboard/timecount.sqlite3'
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        os.close(descriptor)
        self.db = sqlite3.connect(self.path, check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.executescript('''CREATE TABLE IF NOT EXISTS projects (
            profile TEXT, id TEXT, name TEXT NOT NULL, PRIMARY KEY(profile,id));
            CREATE TABLE IF NOT EXISTS daily (
            profile TEXT, project TEXT, day TEXT, ms INTEGER NOT NULL CHECK(ms>=0),
            PRIMARY KEY(profile,project,day));
            CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY, profile TEXT NOT NULL, project TEXT NOT NULL,
            started_at REAL NOT NULL, last_at REAL NOT NULL, ended_at REAL,
            ms INTEGER NOT NULL DEFAULT 0 CHECK(ms>=0));
            CREATE INDEX IF NOT EXISTS session_latest ON sessions(profile,project,id DESC);''')
        # A prior process may have died between checkpoints. Close that interval
        # at its last durable sample; never count the time spent offline.
        with self.db:
            self.db.execute('UPDATE sessions SET ended_at=last_at WHERE ended_at IS NULL')
        self.lock = threading.RLock()
        self.monotonic, self.wall, self.timezone = monotonic, wall, timezone
        self.running = {}
        self.clients = {}
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._keep, daemon=True, name='timecount')

    def _local(self, stamp):
        return datetime.fromtimestamp(stamp, self.timezone)

    def _credit(self, profile, project, start, milliseconds):
        # Segment by actual local midnight, including DST's 23/25-hour days.
        remaining = milliseconds
        cursor = start
        while remaining > 0:
            local = self._local(cursor)
            boundary = datetime.combine(local.date()+timedelta(days=1), day_time(), tzinfo=self.timezone).timestamp()
            part = min(remaining, max(1, round((boundary-cursor)*1000)))
            self.db.execute('''INSERT INTO daily VALUES(?,?,?,?) ON CONFLICT(profile,project,day)
                DO UPDATE SET ms=ms+excluded.ms''', (profile, project, local.date().isoformat(), part))
            cursor += part/1000
            remaining -= part

    def _tick(self, profile):
        now = self.monotonic()
        leases = self.clients.setdefault(profile, {})
        last_expiry = max(leases.values(), default=now)
        run = self.running.get(profile)
        if run:
            end = min(now, last_expiry)
            milliseconds = max(0, int((end-run['last'])*1000))
            if milliseconds:
                start_at=self.wall()-(now-run['last'])
                self._credit(profile, run['id'], start_at, milliseconds)
                self.db.execute('UPDATE sessions SET ms=ms+?,last_at=? WHERE id=?',
                                (milliseconds,start_at+milliseconds/1000,run['session_id']))
                run['last'] += milliseconds/1000
            if not any(expiry > now for expiry in leases.values()):
                self._finish(profile,self.wall()-(now-end))
        self.clients[profile] = {client: expiry for client, expiry in leases.items() if expiry > now}

    def _finish(self, profile, ended_at=None):
        run=self.running.pop(profile,None)
        if run is not None:
            self.db.execute('UPDATE sessions SET ended_at=? WHERE id=? AND ended_at IS NULL',
                            (self.wall() if ended_at is None else ended_at,run['session_id']))

    def _state(self, profile, projects):
        today = self._local(self.wall()).date()
        week, month = today-timedelta(days=today.weekday()), today.replace(day=1)
        first = today-timedelta(days=today.weekday()+52*7)
        active = self.running.get(profile, {}).get('id', '')
        result = []
        for project in projects:
            data = dict(self.db.execute('SELECT day,ms FROM daily WHERE profile=? AND project=?', (profile, project['id'])))
            active_dates = sorted(date.fromisoformat(day) for day, ms in data.items() if ms > 0)
            longest, streak, previous = 0, 0, None
            for current in active_dates:
                streak = streak+1 if previous and current-previous == timedelta(days=1) else 1
                longest = max(longest, streak)
                previous = current
            current_streak, cursor = 0, today if data.get(today.isoformat(), 0) else today-timedelta(days=1)
            while data.get(cursor.isoformat(), 0):
                current_streak += 1
                cursor -= timedelta(days=1)
            days = []
            for offset in range(371):
                day = first+timedelta(days=offset)
                seconds = data.get(day.isoformat(), 0)/1000
                days.append({'date': day.isoformat(), 'seconds': seconds, 'future': day > today,
                             'level': 0 if not seconds else 1 if seconds < 900 else 2 if seconds < 3600 else 3 if seconds < 10800 else 4})
            live=self.db.execute('SELECT started_at,ms FROM sessions WHERE id=?',
                (self.running[profile]['session_id'],)).fetchone() if active==project['id'] else None
            last=self.db.execute('SELECT started_at,ended_at,ms FROM sessions WHERE profile=? AND project=? AND ended_at IS NOT NULL ORDER BY id DESC LIMIT 1',
                                 (profile,project['id'])).fetchone()
            result.append({**project, 'session_seconds': live[1]/1000 if live else 0,
                           'session_started_at': live[0] if live else None,
                           'last_session': {'started_at':last[0],'ended_at':last[1],'seconds':last[2]/1000} if last else None,
                           'total': sum(data.values())/1000, 'today': data.get(today.isoformat(), 0)/1000,
                           'week': sum(ms for day, ms in data.items() if week.isoformat() <= day <= today.isoformat())/1000,
                           'month': sum(ms for day, ms in data.items() if month.isoformat() <= day <= today.isoformat())/1000,
                           'active_days': len(active_dates), 'streak': current_streak, 'longest_streak': longest,
                           'running': active == project['id'], 'days': days})
        return {'projects': result, 'running': active, 'observed_at': self.wall()}

    def control(self, payload):
        if not isinstance(payload, dict):
            raise ValueError('Invalid request')
        profile, client = identifier(payload.get('profile', 'default')), identifier(payload.get('client'))
        action = payload.get('action')
        if action not in ('sync', 'start', 'pause', 'release'):
            raise ValueError('Only sync, start, pause and release are supported')
        projects = projects_list(payload.get('projects'))
        project = payload.get('project', '')
        if action in ('start', 'pause') and project not in {row['id'] for row in projects}:
            raise ValueError('Unknown project')
        with self.lock, self.db:
            self._tick(profile)
            if action == 'release':
                self.clients[profile].pop(client, None)
                if not self.clients[profile]:
                    self._finish(profile)
            else:
                if client not in self.clients[profile] and len(self.clients[profile]) >= 64:
                    raise ValueError('Too many clients')
                self.clients[profile][client] = self.monotonic()+self.LEASE
            for row in projects if action != 'release' else []:
                self.db.execute('INSERT INTO projects VALUES(?,?,?) ON CONFLICT(profile,id) DO UPDATE SET name=excluded.name WHERE name<>excluded.name', (profile, row['id'], row['name']))
            if action == 'sync' and self.running.get(profile, {}).get('id') not in {row['id'] for row in projects}:
                self._finish(profile)
            if action == 'start':
                if self.running.get(profile, {}).get('id') != project:
                    self._finish(profile)
                    started_at=self.wall()
                    cursor=self.db.execute('INSERT INTO sessions(profile,project,started_at,last_at,ms) VALUES(?,?,?,?,0)',
                                           (profile,project,started_at,started_at))
                    self.running[profile] = {'id': project, 'last': self.monotonic(),'session_id':cursor.lastrowid}
            elif action == 'pause' and self.running.get(profile, {}).get('id') == project:
                self._finish(profile)
            return self._state(profile, projects)

    def _keep(self):
        while not self.stop.wait(2):
            with self.lock, self.db:
                for profile in list(self.running):
                    self._tick(profile)

    def shutdown(self):
        self.stop.set()
        if self.thread.is_alive():
            self.thread.join(timeout=3)
        with self.lock, self.db:
            for profile in list(self.running):
                self._tick(profile)
            for profile in list(self.running):
                self._finish(profile)
        self.db.close()
