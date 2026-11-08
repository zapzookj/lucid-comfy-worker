"""[2026-11-07] WD14 태거 모델 베이크 — SmilingWolf/wd-eva02-large-tagger-v3 @ b25b82a, sha256 고정.

노드(ComfyUI-WD14-Tagger)는 models/<이름>.onnx + <이름>.csv 쌍을 설치 모델로 인식한다.
사용: python fetch_tagger_model.py <노드 models 디렉터리>
"""
import hashlib
import pathlib
import sys
import urllib.request

BASE = "https://huggingface.co/SmilingWolf/wd-eva02-large-tagger-v3/resolve/b25b82a03f7282e41aa2f257a52c7583b710bd1c/"
FILES = {
    "model.onnx": ("wd-eva02-large-tagger-v3.onnx", "9e768793060c7939b277ccb382783e8670e8a042d29d77aa736be0c8cc898bfc"),
    "selected_tags.csv": ("wd-eva02-large-tagger-v3.csv", "298633d94d0031d2081c0893f29c82eab7f0df00b08483ba8f29d1e979441217"),
}

target = pathlib.Path(sys.argv[1])
target.mkdir(parents=True, exist_ok=True)
for src, (name, sha) in FILES.items():
    data = urllib.request.urlopen(BASE + src, timeout=900).read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != sha:
        sys.exit(f"tagger checksum mismatch: {src} {actual}")
    (target / name).write_bytes(data)
    print(f"wd14 tagger: {name} {len(data)} bytes OK")
