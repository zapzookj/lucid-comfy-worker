# FIELD_SPEC — 워크플로우 치환 필드 명세 (v2 · 2026-07-17 정정판)

> Lucid Chat UGC 파이프라인 · 기준: **실제 Export JSON 3종이 진실원본** (2026-07-17 종원 확정)
> 이 문서는 `RunPodComfyClient`(백엔드 `UgcComfyClient`/`UgcWorkflowFactory`) 구현의 입력이다.
> **repo의 `workflows_json/`에는 반드시 Export (API) 형식으로 커밋할 것** (일반 Export는 워커가 못 읽음).
>
> **v2 정정 이력** (v1 문서의 오류 — 2026-07-17 코드 대조로 확정):
> 1. 자산 파일명: v1의 (b)세트(waiNSFW…/detailer/anzhc…)가 아니라 **JSON·Dockerfile 실체인 (a)세트가 정본**.
> 2. WF-3: InspyrenetRembg(노드 "10"/"11"/"12")가 아니라 **코어 BiRefNet 체인(노드 "1"/"23"/"22:x")**.
> 3. 동결 파라미터: euler_ancestral/normal·832×1216·WF-2 denoise 0.35 표기는 스테일 — **JSON 값이 정본**.
> 4. 유일한 예외: **WF-1 FaceDetailer는 cfg 4 / denoise 0.4** (Export 원본 cfg 8/0.5에서 종원 결정으로 교체 — JSON에 반영 완료).

---

## 0. 공통 규약

- **치환 방식**: API Export JSON을 템플릿으로 로드 → 아래 명세된 `"{노드ID}".inputs.{키}` 경로의 값을 교체 → `input.workflow`로 제출. 명세에 없는 경로는 절대 건드리지 않는다 (파라미터는 검증값으로 동결).
- **seed 정책**: API Export에는 `control_after_generate`(randomize)가 포함되지 않고 seed 값만 남는다. 즉 **서버가 매 잡마다 난수 seed를 생성해 주입하지 않으면 같은 이미지가 반복**된다. KSampler·FaceDetailer의 seed 모두 잡마다 `SecureRandom` 64-bit 양수로 주입.
- **입력 이미지 주입**: `input.images[]`의 `name`과 LoadImage의 `inputs.image` 값을 **동일 문자열**로 맞춘다. base64 크기 제한: /run 10MB, /runsync 20MB.
- **출력 회수**: worker 5.x 응답 `output.images[] = {filename, type: "s3_url", data}`. `data`는 **만료가 있는 presigned URL**이며 키 구조는 전용 버킷(`lucidchat-ugc-gen`) 루트의 `<job_id>/<파일명>`이다. **백엔드는 이 URL을 저장하지 않는다** — 수신 즉시 객체를 서비스 자산 S3(CloudFront 경로)로 복사하고 우리 키를 보관한다.
- **자산 파일명 매니페스트** (워크플로우 JSON ↔ S3 `assets-build/` ↔ Dockerfile COPY 3중 일치 대상):

| 자산 | 파일명 (정본 = JSON/Dockerfile 실체) | 배치 경로 |
|---|---|---|
| Checkpoint | `wai_illustrious.safetensors` | `models/checkpoints/` |
| 디테일 LoRA | `detail_lora.safetensors` | `models/loras/` |
| 얼굴 검출 YOLO | `anime_face_yolov8.pt` | `models/ultralytics/bbox/` |
| 누끼 모델 | `birefnet.safetensors` (~424MB, [Comfy-Org/BiRefNet](https://huggingface.co/Comfy-Org/BiRefNet)) | `models/background_removal/` — **checkpoints 아님** |

- **베이스 이미지**: `runpod/worker-comfyui:5.8.6-base` 이상 필수 — wf3의 배경 제거 노드는 ComfyUI **코어**(v0.21.0+, PR #12747)라 커스텀 팩 설치가 없고, 5.8.5-base(번들 ≈ v0.17)에는 존재하지 않는다.

---

## 1. WF-1 · 황금샷 t2i + FaceDetailer (`wf1_goldenshot.json`)

Stage 1(황금샷 후보 배치 생성)과 유저 리롤에 사용.

| JSON Path | 노드 | 용도 | 값 소스 | 구분 |
|---|---|---|---|---|
| `"12".inputs.text` | CLIPTextEncode(pos) | 외형 태그 + 씬 연출 프롬프트 | Stage 0 LLM 산출 (품질 프리픽스 `masterpiece, best quality, newest, absurdres`는 서버 상수) | **치환** |
| `"13".inputs.text` | CLIPTextEncode(neg) | 네거티브 | 서버 상수 (검증 Export 값 유지) | 치환 가능 |
| `"11".inputs.seed` | KSampler | 시드 | 잡마다 난수 (리롤 = 새 난수) | **치환** |
| `"17".inputs.seed` | FaceDetailer | 디테일러 시드 | 잡마다 난수 | **치환** |
| `"6".inputs.batch_size` | EmptyLatentImage | 후보 장수 | 프로덕션 4 (Export 원본은 1) | **치환** |
| `"9".inputs.filename_prefix` | SaveImage | 잡 추적 프리픽스 | `job_{id}_golden` | **치환** |
| `"6".inputs.width` / `.height` | EmptyLatentImage | **1024 × 1024** (JSON 정본) | 동결 | 동결 |
| `"11".inputs.steps/cfg/sampler_name/scheduler/denoise` | KSampler | 30 / 4 / **euler / simple** / 1.0 | 동결 | 동결 |
| `"17".inputs.*` (seed 외) | FaceDetailer | guide 512/1024, steps 20, **cfg 4, denoise 0.4** (종원 결정 예외 — JSON 반영 완료), wildcard "" | 동결 | 동결 |
| `"1".inputs.ckpt_name` / `"2".inputs.lora_name` / `"18".inputs.model_name` | 로더 | (a)세트 매니페스트 | 동결 | 동결 |

## 2. WF-2 · i2i 리파인 + FaceDetailer (`wf2_refine.json`)

Stage 2(스탠딩 베이스 리파인)와 Stage 3(감정 파생 후처리) **공용** — positive의 감정 태그만 다르다.

| JSON Path | 노드 | 용도 | 값 소스 | 구분 |
|---|---|---|---|---|
| `"19".inputs.image` | LoadImage | 입력 이미지 파일명 | `input.images[].name`과 동일 문자열 | **치환** |
| `"12".inputs.text` | CLIPTextEncode(pos) | `[품질 프리픽스] + 1girl, solo + [외형 태그] + standing, cowboy shot, looking at viewer + [EMOTION_TAGS] + simple background, [BG_COLOR] background, flat lighting` — 씬·소품 태그 절대 금지 | Stage 0 + 감정 상수맵 + §4 | **치환** |
| `"13".inputs.text` | CLIPTextEncode(neg) | 네거티브 | 서버 상수 | 치환 가능 |
| `"11".inputs.seed` / `"17".inputs.seed` | KSampler / FaceDetailer | 시드 (감정 컷 리롤 = 새 난수) | 잡마다 난수 | **치환** |
| `"9".inputs.filename_prefix` | SaveImage | 잡 추적 프리픽스 | `job_{id}_{emotion}` | **치환** |
| `"11".inputs.denoise` | KSampler | **0.4 (JSON 정본)** — 품질 노브로 config화(`ugc.generation.refine-denoise`, 0.30~0.45) | 동결(설정화) | 동결(설정화) |
| `"11".inputs.steps/cfg/sampler_name/scheduler` | KSampler | 30 / 4 / euler / simple | 동결 | 동결 |
| `"17".inputs.*` (seed 외) | FaceDetailer | cfg 4 / denoise 0.4 / wildcard "detailed beautiful eyes" (JSON 정본) | 동결 | 동결 |

## 3. WF-3 · 누끼 (`wf3_rembg.json`) — v2 전면 정정

코어 BiRefNet 체인 (서브그래프 평탄화 export — `"22:x"` 노드 ID는 정상):
`"1"` LoadImage → `"22:14"` LoadBackgroundRemovalModel(`birefnet.safetensors`) → `"22:13"` RemoveBackground(MASK) → `"22:15"` InvertMask → `"22:16"` JoinImageWithAlpha → `"23"` SaveImage(RGBA PNG)

| JSON Path | 노드 | 용도 | 값 소스 | 구분 |
|---|---|---|---|---|
| `"1".inputs.image` | LoadImage | 입력 이미지 파일명 | `input.images[].name`과 동일 | **치환** |
| `"23".inputs.filename_prefix` | SaveImage | 잡 추적 프리픽스 | `job_{id}_cut_{emotion}` | **치환** |
| `"22:14".inputs.bg_removal_name` | LoadBackgroundRemovalModel | `birefnet.safetensors` | 동결 | 동결 |

## 4. BG_COLOR 슬롯 — 동적 배경색 설계

**배경: 누끼는 피사체-배경 대비 기반이므로, 캐릭터의 머리·의상 색과 명도가 겹치는 배경은 경계 품질을 떨어뜨린다** (은발 × white 검증에서 확인).

- Stage 0의 LLM이 외형 태그에서 지배 색(머리 우선, 의상 보조)을 판정해 **대비되는 저채도 배경색 1개**를 선택한다.
- 팔레트: `light gray`(기본·만능) / `pale blue gray` / `muted teal` / `soft beige` / `dusty lavender`. 팔레트 밖 값은 서버가 `light gray`로 폴백.
- 주입 지점 **2곳 동일 값**: ① Qwen 변환 패스 2의 배경 지시문(`plain solid {BG_COLOR} background`), ② WF-2 positive의 `{BG_COLOR} background`. 불일치 시 리파인이 배경색을 되돌리려 하므로 반드시 동기화.
- WF-3은 색 무관(대비만 확보되면 됨) — 치환 불필요.

## 5. 파이프라인 단계 ↔ 워크플로우 매핑 (오케스트레이터 참조용)

```
Stage 1  황금샷 배치        → WF-1 (batch_size 4, 유저 리롤 = seed 재주입)
Stage 2  스탠딩 베이스      → [Qwen 2패스: 자세·구도 → 배경·조명] → WF-2 (EMOTION_TAGS = neutral)
Stage 3  감정 14종 파생     → 각 감정: [Qwen 감정 편집(베이스에서 직접 — 스타 토폴로지)] → WF-2 (감정별)
Stage 4  누끼              → WF-3 (NEUTRAL 포함 총 15종 전부)
```

Qwen 편집(fal.ai `fal-ai/qwen-image-edit-2511`) 스펙: 입력 키는 **`image_urls` 배열**(단수 아님) ·
negative_prompt 지원 · steps 기본 28 · guidance 4.5 · `image_size` 생략 시 입력 해상도 유지 ·
과금 $0.03/MP · 계정 동시성 기본 2(큐 대기 무제한). 프롬프트 템플릿은 백엔드
`UgcPromptAssembler`가 단일 소스다.
