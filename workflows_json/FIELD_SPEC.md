# FIELD_SPEC — 워크플로우 치환 필드 명세

> Lucid Chat UGC 파이프라인 · 기준: WF-1/2/3 확정본 (2026-07-16, 은발 교수 캐릭터로 검증 완료)
> 이 문서는 `RunPodComfyClient` 개정과 `CharacterCreationJob` 오케스트레이터 구현의 입력이다.
> **repo의 `workflows_json/`에는 반드시 Export (API) 형식으로 커밋할 것** (일반 Export는 워커가 못 읽음). 노드 ID는 두 형식에서 동일하므로 본 명세의 ID는 그대로 유효하다.

---

## 0. 공통 규약

- **치환 방식**: API Export JSON을 템플릿으로 로드 → 아래 명세된 `"{노드ID}".inputs.{키}` 경로의 값을 교체 → `input.workflow`로 제출. 명세에 없는 경로는 절대 건드리지 않는다 (파라미터는 Pod 검증값으로 동결).
- **seed 정책**: API Export에는 `control_after_generate`(randomize)가 포함되지 않고 seed 값만 남는다. 즉 **서버가 매 잡마다 난수 seed를 생성해 주입하지 않으면 같은 이미지가 반복**된다. KSampler·FaceDetailer의 seed 모두 잡마다 `SecureRandom` 64-bit 양수로 주입.
- **입력 이미지 주입**: `input.images[]`의 `name`과 LoadImage의 `inputs.image` 값을 **동일 문자열**로 맞춘다. 서버가 잡 ID 기반 파일명(예: `job_{id}_base.png`)을 생성해 양쪽에 동일 주입. base64 크기 제한: /run 10MB, /runsync 20MB.
- **출력 회수**: worker 5.x 응답 `output.images[] = {filename, type: "s3_url", data}`. filename_prefix(WF-1/2/3)로 워크플로우 판별 가능하나, 잡 단위 매핑은 RunPod job id 기준으로 한다.
- **자산 파일명 매니페스트** (워크플로우 JSON ↔ S3 `assets-build/` ↔ Dockerfile COPY 3중 일치 대상):

| 자산 | 파일명 (워크플로우 확정값) | 배치 경로 |
|---|---|---|
| Checkpoint | `waiNSFWIllustrious_v150.safetensors` | `models/checkpoints/` |
| 디테일 LoRA | `detailer.safetensors` | `models/loras/` |
| 얼굴 검출 YOLO | `Anzhc Face seg 640 v2 y8n.pt` → **`anzhc_face_seg_640_v2_y8n.pt`로 리네임 권장** (공백 제거, 워크플로우 드롭다운 재선택 필요) | `models/ultralytics/bbox/` |
| 누끼 노드 | `comfyui-inspyrenet-rembg` (커스텀 노드, Dockerfile L1) | — |

---

## 1. WF-1 · 황금샷 t2i + FaceDetailer (`wf1_goldenshot.json`)

Stage 1(황금샷 후보 배치 생성)과 유저 리롤에 사용.

| JSON Path | 노드 | 용도 | 값 소스 | 구분 |
|---|---|---|---|---|
| `"12".inputs.text` | CLIPTextEncode(pos) | 외형 태그 + 씬 연출 프롬프트 | Stage 0 LLM 산출 (품질 태그 프리픽스는 서버 상수) | **치환** |
| `"13".inputs.text` | CLIPTextEncode(neg) | 네거티브 | 서버 상수 (현 검증값을 기본값으로) | 치환 가능 |
| `"11".inputs.seed` | KSampler | 시드 | 잡마다 난수 (리롤 = 새 난수) | **치환** |
| `"17".inputs.seed` | FaceDetailer | 디테일러 시드 | 잡마다 난수 | **치환** |
| `"6".inputs.batch_size` | EmptyLatentImage | 후보 장수 | 프로덕션 4 (검증본은 1) | **치환** |
| `"6".inputs.width` / `.height` | EmptyLatentImage | 832 × 1216 | 서버 상수 | 동결 |
| `"11".inputs.steps/cfg/sampler_name/scheduler/denoise` | KSampler | 30 / 4 / euler_ancestral / normal / 1.0 | Pod 검증값 | 동결 |
| `"17".inputs.*` (seed 외 전부) | FaceDetailer | guide 512/1024, steps 20, cfg 4, denoise 0.4, wildcard "" 등 | Pod 검증값 | 동결 |
| `"1".inputs.ckpt_name` / `"2".inputs.lora_name` | 로더 | 자산 파일명 | 매니페스트 | 동결 |
| `"9".inputs.filename_prefix` | SaveImage | `WF-1` | (선택) `job_{id}` 프리픽스로 치환하면 추적 편의 | 선택 |

## 2. WF-2 · i2i 리파인 + FaceDetailer (`wf2_refine.json`)

Stage 2(스탠딩 베이스 리파인)와 Stage 3(감정 15종 후처리) **공용** — positive의 감정 태그만 다르다.

| JSON Path | 노드 | 용도 | 값 소스 | 구분 |
|---|---|---|---|---|
| `"19".inputs.image` | LoadImage | 입력 이미지 파일명 | `input.images[].name`과 동일 문자열 | **치환** |
| `"12".inputs.text` | CLIPTextEncode(pos) | `[품질 태그] + [외형 태그] + standing, cowboy shot, looking at viewer, [EMOTION_TAGS] + simple background, [BG_COLOR] background, flat lighting` | 외형: Stage 0 / EMOTION_TAGS: Stage 2는 `neutral expression`·Stage 3은 EmotionTag별 사전 정의 / BG_COLOR: §4 | **치환** |
| `"13".inputs.text` | CLIPTextEncode(neg) | 네거티브 | 서버 상수 | 치환 가능 |
| `"11".inputs.seed` | KSampler | 시드 (감정 컷 개별 리롤 = 새 난수) | 잡마다 난수 | **치환** |
| `"17".inputs.seed` | FaceDetailer | 디테일러 시드 | 잡마다 난수 | **치환** |
| `"11".inputs.denoise` | KSampler | 0.35 | 서버 상수 (품질 튜닝 노브로 config화 권장, 범위 0.30~0.45) | 동결(설정화) |
| `"11".inputs.steps/cfg/sampler_name/scheduler` | KSampler | 30 / 4 / euler_ancestral / normal | Pod 검증값 | 동결 |
| `"17".inputs.*` (seed 외) | FaceDetailer | WF-1과 동일 검증값 | Pod 검증값 | 동결 |
| `"9".inputs.filename_prefix` | SaveImage | `WF-2` | (선택) 잡 프리픽스 | 선택 |

## 3. WF-3 · 누끼 (`wf3_rembg.json`)

Stage 4(최종 에셋 알파 추출)에 사용.

| JSON Path | 노드 | 용도 | 값 소스 | 구분 |
|---|---|---|---|---|
| `"10".inputs.image` | LoadImage | 입력 이미지 파일명 | `input.images[].name`과 동일 | **치환** |
| `"11".inputs.torchscript_jit` | InspyrenetRembg | `default` | 서버 상수 | 동결 |
| `"12".inputs.filename_prefix` | SaveImage | `WF-3` | (선택) 잡 프리픽스 | 선택 |

## 4. BG_COLOR 슬롯 — 동적 배경색 설계

**배경: 누끼는 피사체-배경 대비 기반이므로, 캐릭터의 머리·의상 색과 명도가 겹치는 배경은 경계 품질을 떨어뜨린다** (은발 × white 검증에서 확인).

- Stage 0의 LLM이 외형 태그에서 지배 색(머리 우선, 의상 보조)을 판정해 **대비되는 저채도 배경색 1개**를 선택한다. 저채도 제약 이유: WF-2 리파인(denoise 0.35)에서 고채도 배경의 색 번짐 방지.
- 팔레트(초안, PoC로 확정): `light gray`(기본·만능) / `pale blue gray` / `muted teal` / `soft beige` / `dusty lavender`. 밝은 머리(은발·금발·백발) → 중간 명도 색, 어두운 머리 → `light gray` 유지.
- 주입 지점 **2곳 동일 값**: ① Qwen 변환 패스 2의 배경 지시문(`plain solid {BG_COLOR} background`), ② WF-2 positive의 `{BG_COLOR} background`. 불일치 시 리파인이 배경색을 되돌리려 하므로 반드시 동기화.
- WF-3은 색 무관(대비만 확보되면 됨) — 치환 불필요.

## 5. 파이프라인 단계 ↔ 워크플로우 매핑 (오케스트레이터 참조용)

```
Stage 1  황금샷 배치     → WF-1 (batch_size 4, 유저 리롤 = seed 재주입)
Stage 2  스탠딩 베이스   → [Qwen 2패스: 자세·구도 → 배경·조명] → WF-2 (EMOTION_TAGS = neutral)
Stage 3  감정 15종      → 각 감정: [Qwen 감정 편집(베이스에서 파생·스타 토폴로지)] → WF-2 (EMOTION_TAGS = 감정별)
Stage 4  누끼           → WF-3 (15종 + neutral 전부)
```

Qwen 편집(fal.ai) 프롬프트 템플릿은 별도 문서(백엔드 설계 시 작성)로 관리 — 본 명세는 RunPod ComfyUI 워크플로우의 치환 계약만 다룬다.
