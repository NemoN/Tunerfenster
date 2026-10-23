#!/usr/bin/env python3
"""Local playback fixture. Use only generated test video; never production credentials.

ffmpeg -f lavfi -i testsrc2=size=640x360:rate=25 -f lavfi -i sine=frequency=440 -t 30 -c:v libx264 -preset ultrafast -c:a aac -f mpegts /tmp/test.ts
python3 scripts/qa-server.py /tmp/test.ts /tmp/tunerfenster-qa
Launch Tunerfenster --env-file /tmp/tunerfenster-qa/fixture.env.
Set the fixture's active file to 0 to simulate the original viewer leaving.
Add --showcase for an eight-tuner demo with fictitious channels, EPG and picon.
"""
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

clip = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()
root.mkdir(exist_ok=True, parents=True)
(root / 'active').write_text('1')
(root / 'fixture.env').write_text('TVH_URL=http://127.0.0.1:18781\nTVH_USER=fixture\nTVH_PASS=fixture\nTVH_AUTH=digest\n')
lock = threading.Lock()
streams = {}
serial = 0
recordings = {}
showcase = '--showcase' in sys.argv[3:]
numbers = [1, 2, 4, 5] if showcase else [1, 2]
network = 'Demo Satellite' if showcase else 'Testnetz'
def channel_name(i):
    return {1: 'Spectrum HD', 2: 'Horizont HD', 4: 'Atelier HD', 5: 'Panorama HD'}.get(i, f'Demo {i}') if showcase else f'Testbild {i}'
def input_name(i): return f'DVB-S2 #{i}' if showcase else f'Testtuner #{i}'
def service_path(i): return f'{input_name(i)}/{network}/Mux{i}/{channel_name(i)}'

def event(kind, **fields):
    with lock, (root / 'events.jsonl').open('a') as out:
        out.write(json.dumps({'event': kind, **fields}) + '\n')

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def auth(self):
        value = self.headers.get('Authorization', '')
        if value.startswith('Digest '):
            fields = dict((k, a or b) for k,a,b in re.findall(r'(\w+)=(?:"([^"]*)"|([^,\s]+))', value))
            md5 = lambda s: hashlib.md5(s.encode()).hexdigest()
            expected = md5(':'.join([md5('fixture:Tunerfenster QA:fixture'), fields.get('nonce',''), fields.get('nc',''), fields.get('cnonce',''), 'auth', md5(self.command + ':' + fields.get('uri',''))]))
            if fields.get('username') == 'fixture' and fields.get('response') == expected:
                return True
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Digest realm="Tunerfenster QA", nonce="local-fixture-nonce", algorithm=MD5, qop="auth"')
        self.send_header('Content-Length', '0')
        self.end_headers()
        return False
    def json(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        global serial
        path = urlsplit(self.path).path
        ticket = parse_qs(urlsplit(self.path).query).get('ticket') == ['local-test-ticket']
        if not ((path.startswith('/stream/') or path.startswith('/dvrfile/')) and ticket) and not self.auth(): return
        active = (root / 'active').read_text().strip() == '1'
        if path == '/api/dvr/entry/grid':
            mode = (root/'dvr-mode').read_text().strip() if (root/'dvr-mode').exists() else 'configured'
            if mode == 'forbidden':
                self.send_error(403)
                return
            entries = [{'uuid':str(i)*32, 'disp_title':title, 'disp_description':'Generated local test video for recording playback.',
                        'channelname':channel_name(1 if i == 1 else 2), 'start':int(time.time())-i*3600, 'stop':int(time.time())-i*3600+30,
                        'duration':30, 'filesize':clip.stat().st_size if i < 3 else 0,
                        'sched_status':'scheduled' if i == 4 else 'completed', 'url':f'dvrfile/{str(i)*32}'}
                       for i,title in [(1,'Signal & colour'),(2,'Studio session'),(3,'Missing test file'),(4,'Future timer')]] if mode != 'empty' else []
            return self.json({'entries':entries, 'total':len(entries)})
        if path.startswith('/dvrfile/'):
            if path.rsplit('/',1)[1] not in ('1'*32, '2'*32):
                self.send_error(404)
                return
            data = clip.read_bytes()
            start, end = 0, len(data)-1
            range_header = self.headers.get('Range')
            if range_header:
                match = re.fullmatch(r'bytes=(\d+)-(\d*)',range_header)
                if not match:
                    self.send_error(416)
                    return
                start = int(match[1]); end = min(end, int(match[2]) if match[2] else end)
            if start > end:
                self.send_error(416)
                return
            event('recording-file', uuid=path.rsplit('/',1)[1], range=range_header)
            self.send_response(206 if range_header else 200)
            self.send_header('Content-Type','video/MP2T')
            self.send_header('Accept-Ranges','bytes')
            self.send_header('Content-Length',str(end-start+1))
            if range_header: self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
            self.end_headers()
            try: self.wfile.write(data[start:end+1])
            except (BrokenPipeError, ConnectionResetError): pass
            return
        if path in ('/api/dvr/config/grid', '/api/dvr/entry/grid_upcoming'):
            mode = (root/'dvr-mode').read_text().strip() if (root/'dvr-mode').exists() else 'configured'
            if mode == 'forbidden':
                self.send_error(403)
                return
            entries = [{'uuid':'qa-dvr-profile', 'name':'', 'enabled':True, 'storage':'/local-fixture-recordings'}] if path.endswith('config/grid') and mode != 'unconfigured' else []
            return self.json({'entries':entries, 'total':len(entries)})
        if path == '/api/idnode/load':
            uuid = parse_qs(urlsplit(self.path).query).get('uuid', [''])[0]
            with lock:
                entries = [item.copy() for item in recordings.values() if item['uuid'] == uuid]
            return self.json({'entries':entries})
        if path.startswith('/play/ticket/stream/') or path.startswith('/play/ticket/dvrfile/'):
            stream_path = path.removeprefix('/play/ticket')
            data = f'#EXTM3U\nhttp://127.0.0.1:18781{stream_path}?ticket=local-test-ticket&profile=pass\n'.encode()
            self.send_response(200)
            self.send_header('Content-Type','audio/x-mpegurl')
            self.send_header('Content-Length',str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == '/api/mpegts/service/grid':
            return self.json({'entries':[{'uuid':f'service-{i}', 'network':network, 'multiplex':f'Mux{i}', 'multiplex_uuid':f'mux-{i}', 'svcname':channel_name(i)} for i in numbers], 'total':len(numbers)})
        if path == '/api/channel/grid':
            entries = [{'uuid':f'channel-{i}', 'name':channel_name(i), 'enabled':True, 'services':[f'service-{i}'], 'icon_public_url':'/imagecache/demo.png'} for i in numbers] if showcase else []
            return self.json({'entries':entries, 'total':len(entries)})
        if path == '/api/mpegts/mux/grid':
            entries = [{'uuid':f'mux-{i}', 'name':f'Mux{i}', 'network':network, 'delsys':'DVB-S2', 'frequency':(11494 + i * 83)*1000, 'polarisation':'H' if i%2 else 'V', 'symbolrate':22000000, 'modulation':'8PSK', 'fec':'2/3', 'orbital':'19.2E', 'satellite':True} for i in range(1,9)]
            return self.json({'entries':entries, 'total':len(entries)})
        if path == '/api/epg/events/grid' and showcase:
            query = parse_qs(urlsplit(self.path).query)
            channel = query.get('channel',['channel-1'])[0]
            english = query.get('lang',['eng']) == ['eng']
            now = int(time.time())
            titles = ['Signal & colour', 'Studio session'] if english else ['Signal & Farbe', 'Aus dem Studio']
            detail = 'Locally generated test signals and demo programme data. No broadcast footage or private server data is used in these screenshots.' if english else 'Lokal erzeugte Testsignale und Beispieldaten für den Programmführer. Die Screenshots enthalten keine Fernsehaufnahmen und keine privaten Serverdaten.'
            entries = [{'eventId':i+1,'channelUuid':channel,'start':now-900+i*3600,'stop':now+2700+i*3600,'title':title,'subtitle':'Tunerfenster · Demo','description':detail} for i,title in enumerate(titles)]
            with lock:
                for entry in entries:
                    if str(entry['eventId']) in recordings:
                        recording = recordings[str(entry['eventId'])]
                        if recording['channel'] == channel:
                            entry.update(dvrUuid=recording['uuid'], dvrState=recording['sched_status'])
            return self.json({'entries':entries})
        if path == '/imagecache/demo.png' and (root/'picon.png').is_file():
            data=(root/'picon.png').read_bytes()
            self.send_response(200)
            self.send_header('Content-Type','image/png')
            self.send_header('Content-Length',str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == '/api/status/inputs':
            return self.json({'entries':[{'uuid':f'tuner-{i}', 'input':input_name(i), 'stream': f'Mux{i} in {network}' if i in numbers+[3] else None, 'subs':1 if i in numbers+[3] else 0,'signal':56000-i*350,'signal_scale':1,'snr':31000,'snr_scale':2,'cc':0,'bps':4600000-i*120000} for i in range(1,9 if showcase else 15)]})
        if path == '/api/status/subscriptions':
            subs = [{'id':i, 'channel':channel_name(i), 'service':service_path(i), 'client':'External QA viewer', 'title':'HTTP','state':'Running'} for i in numbers] if active else []
            subs.append({'id':3, 'service':f'{input_name(3)}/{network}/Mux3/Raw PID Subscription', 'title':'epggrab','state':'Running'})
            with lock:
                subs.extend({'id':100+k,'service':service_path(v),'client':'Tunerfenster/1.0','title':'HTTP','state':'Running'} for k,v in streams.items())
            return self.json({'entries':subs})
        if path.startswith('/stream/service/service-'):
            number = int(path.rsplit('-',1)[1])
            with lock:
                serial += 1
                key = serial
                streams[key] = number
            event('stream-open', stream=number, client=self.headers.get('User-Agent'), authentication='Ticket', weight=parse_qs(urlsplit(self.path).query).get('weight'))
            self.send_response(200)
            self.send_header('Content-Type','video/MP2T')
            self.end_headers()
            selected_clip = root/f'channel-{number}.ts'
            process = subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-re','-stream_loop','-1','-i',str(selected_clip if selected_clip.exists() else clip),'-c','copy','-f','mpegts','pipe:1'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            try:
                while data := process.stdout.read(188*40):
                    self.wfile.write(data)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError): pass
            finally:
                process.terminate()
                process.wait(timeout=5)
                process.stdout.close()
                with lock: streams.pop(key,None)
                event('stream-close', stream=number)
            return
        self.send_error(404)

    def do_POST(self):
        if not self.auth(): return
        path = urlsplit(self.path).path
        if path not in ('/api/dvr/entry/create_by_event', '/api/dvr/entry/stop'):
            self.send_error(404)
            return
        form = parse_qs(self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode())
        mode = (root/'dvr-mode').read_text().strip() if (root/'dvr-mode').exists() else 'configured'
        if mode == 'forbidden':
            self.send_error(403)
            return
        if path == '/api/dvr/entry/stop':
            if form.get('uuid') != ['qa-created-recording']:
                self.send_error(404)
                return
            with lock:
                recordings['1']['sched_status'] = 'completed'
            event('recording-stopped', method='POST', uuid='qa-created-recording', file_kept=(root/'qa-created-recording.ts').is_file())
            return self.json({'success':1})
        if mode in ('reject', 'unconfigured') or form.get('event_id') != ['1'] or form.get('config_uuid') != ['qa-dvr-profile']:
            return self.json({})
        shutil.copyfile(clip, root/'qa-created-recording.ts')
        with lock:
            recordings['1'] = {'uuid':'qa-created-recording', 'channel':'channel-1', 'broadcast':1, 'sched_status':'recording'}
        event('recording-created', method='POST', event_id='1', profile='qa-dvr-profile')
        self.json({'uuid':['qa-created-recording']})

print('Local digest-auth playback fixture: 127.0.0.1:18781',flush=True)
ThreadingHTTPServer(('127.0.0.1',18781),Handler).serve_forever()
