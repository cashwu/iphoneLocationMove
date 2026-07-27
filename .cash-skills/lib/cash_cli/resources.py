from __future__ import annotations

from dataclasses import dataclass


LOCALE = "Traditional Chinese (繁體中文)"


@dataclass(frozen=True, slots=True)
class ArtifactResource:
    id: str
    output_path: str
    description: str
    dependencies: tuple[str, ...]
    template: str


ARTIFACT_GRAPH = (
    ArtifactResource(
        id="proposal",
        output_path="proposal.md",
        description="說明變更動機、方案、能力與影響範圍。",
        dependencies=(),
        template=(
            "## Summary\n\n"
            "## Motivation\n\n"
            "## Proposed Solution\n\n"
            "## Non-Goals\n\n"
            "## Alternatives Considered\n\n"
            "## Capabilities\n\n"
            "### New Capabilities\n\n"
            "### Modified Capabilities\n\n"
            "## Impact\n\n"
            "- Affected specs:\n"
            "- Affected code:\n"
            "  - New:\n"
            "  - Modified:\n"
            "  - Removed:\n"
        ),
    ),
    ArtifactResource(
        id="design",
        output_path="design.md",
        description="記錄技術決策、Implementation Contract、風險與遷移計畫。",
        dependencies=("proposal",),
        template=(
            "## Context\n\n"
            "## Goals / Non-Goals\n\n"
            "## Decisions\n\n"
            "## Implementation Contract\n\n"
            "## Risks / Trade-offs\n"
        ),
    ),
    ArtifactResource(
        id="specs",
        output_path="specs/**/*.md",
        description="以 requirement 與 scenario 定義可觀察行為。",
        dependencies=("proposal",),
        template=(
            "## ADDED Requirements\n\n"
            "### Requirement: <title>\n\n"
            "系統 SHALL 定義可觀察行為。\n\n"
            "#### Scenario: <scenario>\n\n"
            "- **WHEN** 發生動作\n"
            "- **THEN** 產生預期結果\n"
        ),
    ),
    ArtifactResource(
        id="tasks",
        output_path="tasks.md",
        description="將設計拆成具體、可驗證的實作任務。",
        dependencies=("proposal", "design", "specs"),
        template="## 1. Implementation\n\n- [ ] 1.1 實作具體行為並執行驗證\n",
    ),
)

ARTIFACTS_BY_ID = {artifact.id: artifact for artifact in ARTIFACT_GRAPH}

APPLY_INSTRUCTION = (
    "讀取 context files，依文件順序完成 pending tasks，"
    "每項驗證通過後立即標記 checkbox；遇到 contract 或範圍變更時暫停。"
)

DISCIPLINES = {
    "tdd": (
        "TDD discipline 依下列 precedence 由前至後判定，每個 task 命中後不再落入後續分支。\n"
        "1. bug fix 且存在實際可行的自動測試邊界：先以能辨識該缺陷的失敗測試重現；"
        "修正後以最小實作使重現測試通過，並保留為 regression evidence。\n"
        "2. 非 bug fix 的可觀察可執行行為變更，且存在實際可行的自動測試邊界："
        "執行 Red-Green-Refactor；先建立因目標行為尚未存在而失敗的測試，"
        "再以最小實作使測試通過，只在綠燈狀態進行 refactor。\n"
        "3. 不改變可觀察行為的純 refactor：使用既有 regression tests；"
        "證據不足時才補 characterization test，不要求 red phase。\n"
        "4. 其餘 task，包括沒有實際可行自動測試邊界的 bug fix，"
        "以及文件、metadata、checker-only task：執行命名的 verification target；"
        "有可用自動 checker 時可以使用，不要求 red phase。\n"
        "需要 red phase 時，測試必須因目標行為尚未存在而失敗；"
        "不相關的較早 guard、pre-existing suite failure 或只有相同 exit code 不構成有效 red。"
        "加入 diagnostic、state、artifact 或等價 assertion 以辨識目標路徑，"
        "或改用更適合的驗證邊界。本 discipline 不要求特定程式語言或 test framework。"
    ),
    "audit": (
        "完成 API、設定或外部輸入邊界前，依 Scoundrel、Lazy Developer、"
        "Confused Developer 三個角度確認安全預設、明確驗證與失敗可見性。"
    ),
}


def artifact_resource(artifact_id: str) -> ArtifactResource:
    try:
        return ARTIFACTS_BY_ID[artifact_id]
    except KeyError as error:
        raise KeyError(f"Unknown artifact: {artifact_id}") from error
