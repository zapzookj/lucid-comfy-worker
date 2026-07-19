# ── L0: 베이스 (가장 안 바뀜) ─────────────────────────────
# 5.8.6-base (2026-06-17): 번들 ComfyUI ≈ v0.25 — wf3의 RemoveBackground/
# LoadBackgroundRemovalModel(코어 노드, v0.21.0+ / ComfyUI PR #12747)이 포함된 최소 라인.
# ⚠ 5.8.5-base(번들 ≈ v0.17)로 내리면 wf3가 unknown node type으로 실패한다.
FROM runpod/worker-comfyui:5.8.6-base

# ── L1: 커스텀 노드 (가끔 바뀜) ───────────────────────────
# 버전 핀: 재현성 확보 (registry 최신 Active 버전, 2026-07-20 기준)
RUN comfy-node-install comfyui-impact-pack@8.28.3 comfyui-impact-subpack@1.3.5
# 누끼는 커스텀 노드 불필요 — wf3의 배경 제거 체인(RemoveBackground 등)은 ComfyUI 코어다.

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
 && /opt/venv/bin/python -c "import cv2, ultralytics, segment_anything, piexif, dill; import numpy; print('deps OK, numpy', numpy.__version__)"

# ── L2: 대형 고정 모델 (거의 안 바뀜) ─────────────────────
# models_local/ 은 GHA가 S3에서 받아 채운다 (3.3)
COPY models_local/checkpoints/wai_illustrious.safetensors /comfyui/models/checkpoints/wai_illustrious.safetensors

# ── L3: 소형 모델 (변경 가능성 있음 → 마지막) ─────────────
COPY models_local/loras/detail_lora.safetensors /comfyui/models/loras/detail_lora.safetensors
RUN mkdir -p /comfyui/models/ultralytics/bbox /comfyui/models/background_removal
COPY models_local/ultralytics/bbox/anime_face_yolov8.pt /comfyui/models/ultralytics/bbox/anime_face_yolov8.pt
# wf3 누끼 모델 — 출처: https://huggingface.co/Comfy-Org/BiRefNet (background_removal/birefnet.safetensors, ~424MB)
#   sha256=9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154
#   S3 assets-build/background_removal/ 에 미러 후 빌드 (checkpoints 폴더 아님에 주의)
COPY models_local/background_removal/birefnet.safetensors /comfyui/models/background_removal/birefnet.safetensors
# (선택) COPY models_local/sams/... /comfyui/models/sams/...
