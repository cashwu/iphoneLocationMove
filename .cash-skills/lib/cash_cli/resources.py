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
        description=(
            "將設計拆成具體、可驗證的實作任務；每個 checkbox task 必須在同一行明列 "
            "delivery、verification、regression、success 與 red 五個欄位。"
            "delivery 列出具體的 project-root-relative delivery paths；"
            "verification 恰好命名一個 primary test、CLI、analyzer 或 manual assertion；"
            "regression 命名相關的 regression targets，"
            "只有 primary target 已涵蓋完整相關範圍時才填 N/A 並附上理由；"
            "success 只描述該 primary target 可直接觀察的成功 marker，"
            "不得混入 regression、publication 或 task completion 結果；"
            "red 在需要 red phase 時描述該 primary target 可辨識的 failure marker，"
            "不適用時填 N/A 並指明 pure-refactor 或 remaining-task 分類理由。"
            "五個欄位都不得留空，也不得填 TBD 或 TODO。"
        ),
        dependencies=("proposal", "design", "specs"),
        template=(
            "## 1. Implementation\n\n"
            "- [ ] 1.1 實作具體行為並執行驗證；"
            "delivery: <project-root-relative paths>；"
            "verification: <單一 primary target>；"
            "regression: <相關 targets，或 N/A 加上 primary 已涵蓋完整相關範圍的理由>；"
            "success: <primary target 可直接觀察的成功 marker>；"
            "red: <primary target 可辨識的 failure marker，"
            "或 N/A 加上 pure-refactor／remaining-task 分類理由>\n"
        ),
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
        "需要 red phase 時，必須在任何 production edit 前實際執行目前 workflow 命名的 "
        "primary verification target；測試必須因目標行為尚未存在而失敗，"
        "並實際觀察到目前 workflow 命名的 failure marker。"
        "未實際執行、primary target 通過、execution error、"
        "不相關的較早 guard、pre-existing suite failure 或只有相同 exit code 不構成有效 red。"
        "加入 diagnostic、state、artifact 或等價 assertion 以辨識目標路徑，"
        "或改用更適合的驗證邊界。\n"
        "production edit 後必須重跑同一個 primary verification target，"
        "觀察到目前 workflow 命名的 success marker，"
        "再執行目前 workflow 命名的相關 regression targets。\n"
        "evidence carrier 由目前 workflow 命名，本 discipline 不假設任何特定檔案，"
        "也不要求特定程式語言或 test framework。"
    ),
    "test-quality": (
        "測試品質 discipline 只治理已決定新增或修改的測試，"
        "不要求沒有測試需求的 task 為形式而新增測試。\n"
        "1. 寫 test body 前先命名一個會使該測試失敗的 realistic production defect；"
        "無法命名時改測 observable contract。\n"
        "2. expected value 以 literal 或手工驗證 fixture 獨立推導，"
        "不得由受測程式、其 helper 或同一套邏輯推導。\n"
        "3. 斷言 consumer-visible output、state、side effect 或 failure mode；"
        "不得以 source text、private structure 或 mock 自身存在代替結果，"
        "除非該 call shape 本身就是 contract。\n"
        "4. mock 只切 slow 或 external boundary，並保留測試依賴的真實 side effects；"
        "mock response 必須涵蓋該測試路徑實際消費的完整 contract shape。\n"
        "5. 完成前對與 task contract 相關的 wrong branch／argument、missing side effect、"
        "empty／default return 與必要 validation 執行有限 mutation check；"
        "有限 mutation check 可以是 mental check 或局部 fixture，"
        "不要求新增 mutation framework、外部 dependency 或無關 coverage threshold。\n"
        "本 discipline 不要求特定程式語言或 test framework。"
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
