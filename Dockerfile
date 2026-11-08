# ── L0: 베이스 (가장 안 바뀜) ─────────────────────────────
# 5.8.6-base (2026-06-17): 번들 ComfyUI ≈ v0.25 — wf3의 RemoveBackground/
# LoadBackgroundRemovalModel(코어 노드, v0.21.0+ / ComfyUI PR #12747)이 포함된 최소 라인.
# ⚠ 5.8.5-base(번들 ≈ v0.17)로 내리면 wf3가 unknown node type으로 실패한다.
FROM runpod/worker-comfyui:5.8.6-base

# ── L1: 커스텀 노드 (가끔 바뀜) ───────────────────────────
# 버전 핀: 재현성 확보 (registry 최신 Active 버전, 2026-07-20 기준)
RUN comfy-node-install comfyui-impact-pack@8.28.3 comfyui-impact-subpack@1.3.5
# 누끼는 커스텀 노드 불필요 — wf3의 배경 제거 체인(RemoveBackground 등)은 ComfyUI 코어다.

# [2026-11-07 레퍼런스 빌더] WD14 태거 — 원화에서 정체성 태그 역추출(aichat docs/56 §10).
#   커밋 고정 클론. onnxruntime은 CPU판을 먼저 핀 설치해 아래 L1.5 미러링 루프가 비고정 설치하지 않게 한다.
#   노드 기본 공급자에 CUDA가 있어 CPU 런타임에서 매 실행 경고가 나므로 CPU 전용으로 고정한다(1장 ~10초).
RUN git clone https://github.com/pythongosssss/ComfyUI-WD14-Tagger /comfyui/custom_nodes/ComfyUI-WD14-Tagger \
 && git -C /comfyui/custom_nodes/ComfyUI-WD14-Tagger checkout 9e0a6e700299182fc05c58b62e7ad9f72182a78b \
 && /opt/venv/bin/pip install onnxruntime==1.22.0 \
 && /opt/venv/bin/python -c "import json, pathlib; p=pathlib.Path('/comfyui/custom_nodes/ComfyUI-WD14-Tagger/pysssss.json'); c=json.loads(p.read_text()); c['settings']['ortProviders']=['CPUExecutionProvider']; c['settings']['model']='wd-eva02-large-tagger-v3'; p.write_text(json.dumps(c, indent=2))"

# ── L1.5: [FaceDetailer Fix 2026-07-20] 의존성 venv 미러링 + 빌드 시점 검증 ──
# 원인: comfy-node-install(comfy-cli)은 노드 pip 의존성을 워크스페이스 venv(/comfyui/.venv)에
#   설치하지만, start.sh는 ComfyUI를 /opt/venv 파이썬으로 기동한다. 베이스 이미지의 미러링
#   (DR-1170)은 "베이스 빌드 시점"에만 실행되므로, 파생 이미지에서 추가한 Impact Pack의
#   의존성이 /opt/venv에 없어 IMPORT FAILED → FaceDetailer 미등록 → missing_node_type.
#   (참고: runpod-workers/worker-comfyui#86 — 동일 증상)
RUN set -e; for r in /comfyui/custom_nodes/*/requirements.txt; do \
      if [ -f "$r" ]; then /opt/venv/bin/pip install -r "$r"; fi; \
    done

# 빌드 시점 임포트 검증 — IMPORT FAILED가 하나라도 있으면 빌드를 실패시킨다
#   (배포 후 missing_node_type으로 뒤늦게 발견하는 사고 방지. quick-test는 모델 없이 CPU 부팅만 확인)
RUN cd /comfyui \
 && (timeout 300 /opt/venv/bin/python main.py --quick-test-for-ci --cpu 2>&1 | tee /tmp/comfy-boot.log) \
 && ! grep -q "IMPORT FAILED" /tmp/comfy-boot.log \
 && /opt/venv/bin/python -c "import cv2, ultralytics, segment_anything, piexif, dill, onnxruntime; import numpy; print('deps OK, numpy', numpy.__version__, 'ort', onnxruntime.__version__)"


# ── L2: 대형 고정 모델 (거의 안 바뀜) ─────────────────────
# models_local/ 은 GHA가 S3에서 받아 채운다 (3.3)
COPY models_local/checkpoints/wai_illustrious.safetensors /comfyui/models/checkpoints/wai_illustrious.safetensors

# ── L3: 소형 모델 (변경 가능성 있음 → 마지막) ─────────────
COPY models_local/loras/detail_lora.safetensors /comfyui/models/loras/detail_lora.safetensors
# [2026-08-04 남캐 파이프라인] Male_Type(STYLE) LoRA — civitai 1782159.
#   wai_illustrious의 여캐 편향 보정용 — 백엔드가 gender=MALE일 때만 LoraLoader 노드를
#   워크플로 그래프에 조건부 주입한다(여캐 생성 경로는 무영향). S3 assets-build/loras/ 미러.
COPY models_local/loras/male_type.safetensors /comfyui/models/loras/male_type.safetensors
RUN mkdir -p /comfyui/models/ultralytics/bbox /comfyui/models/background_removal
COPY models_local/ultralytics/bbox/anime_face_yolov8.pt /comfyui/models/ultralytics/bbox/anime_face_yolov8.pt
# wf3 누끼 모델 — 출처: https://huggingface.co/Comfy-Org/BiRefNet (background_removal/birefnet.safetensors, ~424MB)
#   sha256=9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154
#   S3 assets-build/background_removal/ 에 미러 후 빌드 (checkpoints 폴더 아님에 주의)
COPY models_local/background_removal/birefnet.safetensors /comfyui/models/background_removal/birefnet.safetensors
# Neutral hand restoration (2026-10-08): pinned detector, separate from anime-face detection.
# Download the small model directly so existing S3 assets and scene workers need no migration.
RUN /opt/venv/bin/python -c "import hashlib, pathlib, urllib.request; p=pathlib.Path('/comfyui/models/ultralytics/bbox/hand_yolov8n.pt'); b=urllib.request.urlopen('https://huggingface.co/Bingsu/adetailer/resolve/53cc19de382014514d9d4038601d261a7faa9b7b/hand_yolov8n.pt', timeout=120).read(); assert hashlib.sha256(b).hexdigest() == '3991202eb69e9ddcb3b9ba80cdeb41e734ffaf844403d6c9f47d515cd88c6f29', 'hand detector checksum mismatch'; p.write_bytes(b)" \
 && /opt/venv/bin/python -c "from ultralytics import YOLO; m=YOLO('/comfyui/models/ultralytics/bbox/hand_yolov8n.pt'); assert set(m.names.values()) == {'hand'}, m.names; print('hand detector OK')"
# [2026-11-07] WD14 태거 모델 — SmilingWolf/wd-eva02-large-tagger-v3 @ b25b82a (model.onnx ~1.26GB, 체크섬 고정).
#   노드 models 디렉터리에 베이크해 런타임 HF 다운로드(콜드스타트 지연·외부 의존)를 없앤다.
COPY patches/fetch_tagger_model.py /tmp/fetch_tagger_model.py
RUN /opt/venv/bin/python /tmp/fetch_tagger_model.py /comfyui/custom_nodes/ComfyUI-WD14-Tagger/models
# (선택) COPY models_local/sams/... /comfyui/models/sams/...

# ── L4: 핸들러 패치 (작은 변경 — 모델 레이어 캐시를 깨지 않도록 마지막) ──
# [2026-11-07] 핸들러 패치 — WD14 태거 텍스트 출력(ui.tags)을 output.texts[]로 반환.
#   업스트림 5.8.6은 images 외 출력을 버린다. 앵커 불일치 시 빌드 실패(베이스 버전 변경 감지).
COPY patches/handler_text_outputs.py /tmp/handler_text_outputs.py
RUN /opt/venv/bin/python /tmp/handler_text_outputs.py /handler.py && /opt/venv/bin/python -m py_compile /handler.py
