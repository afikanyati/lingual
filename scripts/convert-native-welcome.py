"""Convert the bundled NSKeyedArchive and its two CAF recordings for optional browser onboarding.

Only explicit Entry/EntrySegment fields are read; cyclic entry references and native identity/telemetry
are not traversed. Original archives remain untouched. Audio time offsets survive mono PCM resampling.
"""
import datetime
import json
import math
from pathlib import Path
import plistlib
import subprocess
import wave

ROOT = Path(__file__).resolve().parent.parent
source = next((ROOT / 'diction-processor/entries').glob('*.lingual'))
objects = plistlib.loads(source.read_bytes())
archive = objects['$objects']

def value(item):
    return archive[item.data] if isinstance(item, plistlib.UID) else item

def dictionary(item):
    item = value(item)
    if isinstance(item, dict) and 'NS.keys' in item:
        return {value(k): dictionary(v) for k, v in zip(item['NS.keys'], item['NS.objects'])}
    return item

def seconds(item):
    return item['value'] / item['timescale']

entry = value(objects['$top']['root'])
segments = [value(item) for item in value(entry['entrySegments'])['NS.objects']]
output = ROOT / 'web/public/welcome'
output.mkdir(exist_ok=True)
text = ''
spans = []
clips = {}
word_ordinal = -1
for ordinal, segment in enumerate(segments):
    word = value(segment['word'])
    if word: word_ordinal += 1
    if not word or segment['deleted'] or segment['voiceCommandWord']:
        continue
    timing = dictionary(segment['sourceTimeRange'])
    start, end = seconds(timing['start']), seconds(timing['end'])
    if any(char.isalnum() for char in word):
        assert end > start >= 0, f"Invalid original word time: {ordinal}"
    filename = value(segment['trackURL'])
    clip_id = value(segment['clipUID'])
    clips[clip_id] = filename
    if text and not all(not c.isalnum() for c in word):
        text += ' '
    offset = len(text)
    text += word
    if not any(char.isalnum() for char in word):
        continue
    span = dict(start=offset, end=len(text), clipId=clip_id, ordinal=word_ordinal,
                sourceStart=start, sourceEnd=end, rate=round(segment['rate'], 3), gain=1,
                recordingId=clip_id, recordedStart=start, recordedEnd=end,
                power=segment['power'], speakingRate=segment['speakingRate'])
    if 'pitchFrequency' in segment: span['pitch'] = segment['pitchFrequency']
    for field in ["pitch", "power", "speakingRate"]:
        if field in span and not math.isfinite(span[field]): del span[field]
    if 'pitch' in span and not 82 <= span['pitch'] <= 1047: del span['pitch']
    spans.append(span)

created = datetime.datetime.fromtimestamp(entry['dateCreated'],datetime.timezone.utc).isoformat()
result = dict(id='native-welcome-v1', title='Welcome to Lingual', createdAt=created, updatedAt=created,
              text=text, spans=spans, selection=dict(start=0,end=0), history=[], future=[], clipIds=list(clips))
metadata = []
for clip_id, name in clips.items():
    target = output / (clip_id + '.wav')
    if not target.exists():
        subprocess.run(['ffmpeg','-v','error','-i',str(ROOT/'diction-processor/sounds'/name),'-ac','1','-ar','16000','-c:a','pcm_s16le',str(target)],check=True)
    with wave.open(str(target)) as audio:
        duration = audio.getnframes()/audio.getframerate()
    metadata.append(dict(id=clip_id,entryId=result['id'],createdAt=created,duration=duration,
                         transcript='',transcribed=True,file=target.name))
    assert all(s['sourceEnd'] <= duration + .02 for s in spans if s['clipId']==clip_id)
(output/'manifest.json').write_text(json.dumps(dict(entry=result, clips=metadata),indent=2,allow_nan=False)+'\n')
print(json.dumps(dict(words=len(spans),clips=len(clips),audioBytes=sum(p.stat().st_size for p in output.glob('*.wav')))))
