# Rebuilds ../dinorobong_tubo.html from template.html + ../../game_logic/chip.js + assets/
import base64, json, glob, os
h = os.path.dirname(os.path.abspath(__file__)); A = os.path.join(h, 'assets')
b64 = lambda p: base64.b64encode(open(p, 'rb').read()).decode()
assets = {"frames": ['data:image/jpeg;base64,' + b64(f) for f in sorted(glob.glob(os.path.join(A, 'frames', '*.jpg')))],
          "audio": b64(os.path.join(A, 'audio.wav')),
          "err": 'data:image/jpeg;base64,' + b64(os.path.join(A, 'err.jpg')),
          "webm": 'data:video/webm;base64,' + b64(os.path.join(A, 'video.webm')),
          "mp4": 'data:video/mp4;base64,' + b64(os.path.join(A, 'video.mp4'))}
chip = open(os.path.join(h, '..', '..', 'game_logic', 'chip.js')).read()
t = open(os.path.join(h, 'template.html')).read().replace('/*__CHIP__*/', chip).replace('/*__ASSETS__*/', json.dumps(assets))
out = os.path.join(h, '..', 'dinorobong_tubo.html'); open(out, 'w').write(t); print('wrote', out)
