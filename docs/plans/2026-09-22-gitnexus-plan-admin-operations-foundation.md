# GitNexus Engineering Plan — 1day Admin

> Task: 运营后台设计、数据契约与独立本地交互原型。
> Evidence verified at commit 50431c6bd3a67c0a2e8ef563968387a00ad6c8ef; index HEAD matches but two source files are dirty; source-weighted planning, no core code edits.
> Evidence provenance schema 2; global dirty digest 8afc935dd959d9e12ce46b45f14b43158586bd908e4d891bb5e91ea9e335c57a; 8 cited paths; exact generated plan path excluded.

## Objective (§1)
完成可实施spec及可评审原型，明确生产服务、iOS接入、验收和发布边界。

## Current Behaviour (§2–3)
- [verified] README.md 定义单人/多人、一天/七天、端上成片的产品流程。
- [verified] ios/project.yml 是SwiftUI App工程生成配置；当前version=1.4，build=24。
- [verified] PromptSuggestionMetrics.swift 是只保存在本地的AI采用/改写计数，不能视作已上线埋点。
- [verified] FilmView.swift:204–247 合成有被替代和会话结束判断；失败率不能混入这些结果。
- [verified] 已有 workers/suggest-prompts/package.json，可运行 node --test test/*.test.mjs。

## Findings (§4–5)
- [graph] query('challenge create save clip film render prompt suggestion')定位FilmView.render与建议服务；当前源码已核实。
- impact(ChallengeStore, upstream, depth=1)返回广泛模块引用；本切片不修改该符号，因此不据图声称低风险。
- 未建立PDG约束：当前写入仅设计文档和仓库外原型，无现有核心函数变更。
- 索引因Localization.swift与CloudKitService.swift内容漂移而stale；不刷新其他任务工作区；正式修改前重新做精确impact。

## Proposed Changes (§6)
- [inferred] 后台采用独立Web+API，主题与配置原子发布，已创建故事冻结快照。
- [inferred] 数据采集与运营配置存储分离；行为分析只传白名单结构字段。
- 本轮新增用户交付spec、事件JSON Schema、HTML原型；仅本计划写入项目docs/plans。
- 生产候选目录：admin-web、workers/operations-api、workers/analytics-ingest、contracts/operations；尚未创建。

## Implementation Sequence (§7)
1. 确定指标分母、时间窗、身份、事件、发布与错误状态契约。
2. 并行编写spec和原型：主Agent负责设计/契约，工程Agent独占HTML与局部测试。
3. 本地验证筛选、双语主题编辑、草稿、发布、回滚和存储失败。
4. 浏览器验收桌面与手机尺寸，修复发现的问题；输出实际验证结果。
5. 后续生产M1–M5参照spec，iOS接入须基于当时已协调的工作树。

## Test Strategy (§8)
原型行为测试覆盖不可变发布快照、单调版本、坏数据回退、持久化失败、筛选口径。
事件Schema验证合法fixture与敏感属性/错误类型拒绝。生产服务和iOS并未实施，不能宣称其测试通过。

## Implementation Context (§11)
```json
{
  "task": "1day运营后台设计与本地交互原型；后续生产接入按里程碑执行",
  "category": "feature",
  "generated_plan_path": "docs/plans/2026-09-22-gitnexus-plan-admin-operations-foundation.md",
  "verified_at_commit": "50431c6bd3a67c0a2e8ef563968387a00ad6c8ef",
  "evidence_provenance": {
    "schema_version": 2,
    "head_commit": "50431c6bd3a67c0a2e8ef563968387a00ad6c8ef",
    "generated_plan_path": "docs/plans/2026-09-22-gitnexus-plan-admin-operations-foundation.md",
    "global_dirty_digest": {
      "algorithm": "sha256",
      "canonicalization": "gitnexus-evidence-provenance-v2 NUL-framed UTF-8 records",
      "value": "8afc935dd959d9e12ce46b45f14b43158586bd908e4d891bb5e91ea9e335c57a"
    },
    "cited_path_manifest": [
      {
        "path": "AGENTS.md",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:ae3925a245aae41731f8efbac4f4844921816de02173b03632d730304e2c9b54",
        "index_digest": "sha256:ae3925a245aae41731f8efbac4f4844921816de02173b03632d730304e2c9b54",
        "worktree_digest": "sha256:ae3925a245aae41731f8efbac4f4844921816de02173b03632d730304e2c9b54",
        "untracked_digest": "absent"
      },
      {
        "path": "README.md",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:2c776005d3c51b9e69de4273d8da78f0b4ee74b4787d39e847424713f3fcc3d7",
        "index_digest": "sha256:2c776005d3c51b9e69de4273d8da78f0b4ee74b4787d39e847424713f3fcc3d7",
        "worktree_digest": "sha256:2c776005d3c51b9e69de4273d8da78f0b4ee74b4787d39e847424713f3fcc3d7",
        "untracked_digest": "absent"
      },
      {
        "path": "ios/AISetlog/Services/PromptSuggestionMetrics.swift",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:0b8d81fd58116d6fcc1253c3047a5d975c7fdd2c856cbd1cf69a50fb340bc9ad",
        "index_digest": "sha256:0b8d81fd58116d6fcc1253c3047a5d975c7fdd2c856cbd1cf69a50fb340bc9ad",
        "worktree_digest": "sha256:0b8d81fd58116d6fcc1253c3047a5d975c7fdd2c856cbd1cf69a50fb340bc9ad",
        "untracked_digest": "absent"
      },
      {
        "path": "ios/AISetlog/Services/PromptSuggestionService.swift",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:34ad380ee8bf23ccc979acb5da4546e01fb04926c496ef85958943517c8a799b",
        "index_digest": "sha256:34ad380ee8bf23ccc979acb5da4546e01fb04926c496ef85958943517c8a799b",
        "worktree_digest": "sha256:34ad380ee8bf23ccc979acb5da4546e01fb04926c496ef85958943517c8a799b",
        "untracked_digest": "absent"
      },
      {
        "path": "ios/AISetlog/Views/Film/FilmView.swift",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:c629c740698c2074aeaf7095919cdb04bf86d7c8d9605390f722489e4f7e7349",
        "index_digest": "sha256:c629c740698c2074aeaf7095919cdb04bf86d7c8d9605390f722489e4f7e7349",
        "worktree_digest": "sha256:c629c740698c2074aeaf7095919cdb04bf86d7c8d9605390f722489e4f7e7349",
        "untracked_digest": "absent"
      },
      {
        "path": "ios/project.yml",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:eeec8db4d195c004ca6f5a9c09e47a48b5a55ae6e34898608aa4c825af0aba28",
        "index_digest": "sha256:eeec8db4d195c004ca6f5a9c09e47a48b5a55ae6e34898608aa4c825af0aba28",
        "worktree_digest": "sha256:eeec8db4d195c004ca6f5a9c09e47a48b5a55ae6e34898608aa4c825af0aba28",
        "untracked_digest": "absent"
      },
      {
        "path": "landing-page/package.json",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "unstaged",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:f19556eb47475c6f3d79e1c43beee248e18a017a99beb4b42afa1808563fb58e",
        "index_digest": "sha256:f19556eb47475c6f3d79e1c43beee248e18a017a99beb4b42afa1808563fb58e",
        "worktree_digest": "sha256:a52b5acdec70f79c80fac046bd2ab96199525d5fe930d59a723308a53ca4c9e2",
        "untracked_digest": "absent"
      },
      {
        "path": "workers/suggest-prompts/package.json",
        "object_kind": {
          "head": "regular",
          "index": "regular",
          "worktree": "regular",
          "untracked": "absent"
        },
        "state": "clean",
        "rename_from": null,
        "rename_to": null,
        "head_digest": "sha256:be6ec3e9f54e8afc15450fb74d66ad45c1d66f62dc731393a4a6cb41b347e999",
        "index_digest": "sha256:be6ec3e9f54e8afc15450fb74d66ad45c1d66f62dc731393a4a6cb41b347e999",
        "worktree_digest": "sha256:be6ec3e9f54e8afc15450fb74d66ad45c1d66f62dc731393a4a6cb41b347e999",
        "untracked_digest": "absent"
      }
    ]
  },
  "primary_symbols": [
    {
      "symbol": "PromptSuggestionMetrics",
      "file": "ios/AISetlog/Services/PromptSuggestionMetrics.swift",
      "lines": "1-88",
      "role": "existing local-only AI metrics; preserve semantics"
    },
    {
      "symbol": "render",
      "file": "ios/AISetlog/Views/Film/FilmView.swift",
      "lines": "204-247",
      "role": "render outcome and cancellation-aware future event boundary"
    }
  ],
  "related_symbols": [],
  "execution_path": [
    "draft complete product/API/event specification",
    "build isolated local HTML prototype",
    "test persistence, immutable releases, filters and rollback",
    "review browser render and interactions",
    "later implement server and iOS after baseline and external environment are resolved"
  ],
  "pdg_constraints": [],
  "architectural_patterns": [
    {
      "pattern": "local-first media workflow",
      "example_location": "README.md",
      "usage_guidance": "remote config and analytics must never gate local recording"
    }
  ],
  "files_to_modify": [],
  "tests": [
    {
      "file": "new independent prototype behavior test outside repo",
      "scenarios": [
        "publish vs draft isolation",
        "rollback creates new revision",
        "storage failure preserves active version",
        "filters derive from same records"
      ]
    }
  ],
  "verification_commands": [
    "node --check <extracted prototype script>",
    "node <prototype behavior test>"
  ],
  "risks": [
    "Graph stale for CloudKitService and Localization; no production edits permitted in this design slice",
    "Local HTML does not prove server auth or transactional correctness",
    "Public repo; no secrets or private footage in artifacts"
  ],
  "assumptions": [
    "Cloudflare and PostHog deployment credentials/region remain unverified; resolve only before actual deployment",
    "Independent prototype is the current design deliverable; production integration is milestone M1 onward"
  ],
  "open_questions": [
    "Cloud project and domain",
    "PostHog region and project",
    "Owner identity and budget"
  ],
  "avoid": [
    "Do not repeat full repository discovery",
    "Do not overwrite unrelated working-tree edits",
    "Do not publish or deploy demo prototype as production admin",
    "Do not claim raw events are anonymized simply because identifiers are UUIDs"
  ]
}
```

## Assumptions and Open Questions (§12)
- [assumed] Cloudflare可承载独立运营服务，但账户、域名与费用上限仍需在部署前确定。
- [assumed] PostHog作为可替换分析引擎，区域、项目与保留期需在接入时核实。
- 当前交付为设计与可交互原型，非已部署真实管理后台。

## Definition of Done (§13)
完整spec覆盖页面/指标/事件/API/状态/安全/验收；原型真实可操作且明确演示；持久化与回滚验证；浏览器检查；无其他任务改动被覆盖。
