# ── L0: 베이스 (가장 안 바뀜) ─────────────────────────────
FROM runpod/worker-comfyui:5.8.5-base

# ── L1: 커스텀 노드 (가끔 바뀜) ───────────────────────────
# comfy-node-install: worker 제공 CLI. 이름은 https://registry.comfy.org 에서 확인
RUN comfy-node-install comfyui-impact-pack comfyui-impact-subpack
# 누끼 노드: PoC-6 확정 후 주석 해제 (정확한 registry 명칭 확인)
# RUN comfy-node-install comfyui-inspyrenet-rembg

# ── L2: 대형 고정 모델 (거의 안 바뀜) ─────────────────────
# models_local/ 은 GHA가 S3에서 받아 채운다 (3.3)
COPY models_local/checkpoints/wai_illustrious.safetensors /comfyui/models/checkpoints/wai_illustrious.safetensors

# ── L3: 소형 모델 (변경 가능성 있음 → 마지막) ─────────────
COPY models_local/loras/detail_lora.safetensors /comfyui/models/loras/detail_lora.safetensors
RUN mkdir -p /comfyui/models/ultralytics/bbox
COPY models_local/ultralytics/bbox/anime_face_yolov8.pt /comfyui/models/ultralytics/bbox/anime_face_yolov8.pt
# (선택) COPY models_local/sams/... /comfyui/models/sams/...