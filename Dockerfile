# ── L0: 베이스 (가장 안 바뀜) ─────────────────────────────
# 5.8.6-base (2026-06-17): 번들 ComfyUI ≈ v0.25 — wf3의 RemoveBackground/
# LoadBackgroundRemovalModel(코어 노드, v0.21.0+ / ComfyUI PR #12747)이 포함된 최소 라인.
# ⚠ 5.8.5-base(번들 ≈ v0.17)로 내리면 wf3가 unknown node type으로 실패한다.
FROM runpod/worker-comfyui:5.8.6-base

# ── L1: 커스텀 노드 (가끔 바뀜) ───────────────────────────
# comfy-node-install: worker 제공 CLI. 이름은 https://registry.comfy.org 에서 확인
RUN comfy-node-install comfyui-impact-pack comfyui-impact-subpack
# 누끼는 커스텀 노드 불필요 — wf3의 배경 제거 체인(RemoveBackground 등)은 ComfyUI 코어다.

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
