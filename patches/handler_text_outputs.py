"""[2026-11-07] worker-comfyui 5.8.6 /handler.py 패치 — WD14 태거의 텍스트 출력을 응답에 포함한다.

업스트림 핸들러는 노드 출력 중 "images"만 수집하고 나머지 키는 경고 로그만 남기고 버린다
(handler.py "Check for other output types"). WD14Tagger 노드는 {"ui": {"tags": [...]}}로
태그 문자열을 내보내므로, 이 키를 output.texts[] = {"node_id", "tags"}로 돌려주게 바꾼다.

앵커 문자열이 정확히 1회씩 있어야만 적용한다 — 베이스 이미지 버전을 올려 핸들러가 바뀌면
빌드가 실패해 조용한 미적용을 막는다. 사용: python handler_text_outputs.py /handler.py
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8", newline="").read()

PATCHES = [
    (
        "    output_data = []\n    errors = []\n",
        "    output_data = []\n    text_outputs = []  # [lucid patch] WD14 태거 텍스트 출력\n    errors = []\n",
    ),
    (
        "            # Check for other output types\n"
        "            other_keys = [k for k in node_output.keys() if k != \"images\"]\n",
        "            # [lucid patch] 텍스트 출력(WD14Tagger ui.tags) 수집\n"
        "            if \"tags\" in node_output:\n"
        "                text_outputs.append({\"node_id\": node_id, \"tags\": node_output[\"tags\"]})\n"
        "            # Check for other output types\n"
        "            other_keys = [k for k in node_output.keys() if k not in (\"images\", \"tags\")]\n",
    ),
    (
        "    final_result = {}\n\n    if output_data:\n        final_result[\"images\"] = output_data\n",
        "    final_result = {}\n\n    if output_data:\n        final_result[\"images\"] = output_data\n\n"
        "    if text_outputs:  # [lucid patch]\n        final_result[\"texts\"] = text_outputs\n",
    ),
]

for anchor, replacement in PATCHES:
    count = src.count(anchor)
    if count != 1:
        sys.exit(f"[lucid patch] 앵커 {count}회 발견(1회 필요) — 업스트림 handler.py 변경 의심: {anchor[:60]!r}")
    src = src.replace(anchor, replacement)

# 이미지가 없고 텍스트만 있는 잡(태거 전용 워크플로)은 업스트림이 status=success_no_images로 돌려준다.
# texts는 위에서 이미 final_result에 담기므로 별도 처리가 필요 없다.
open(path, "w", encoding="utf-8", newline="").write(src)
print("[lucid patch] handler text outputs: applied")
