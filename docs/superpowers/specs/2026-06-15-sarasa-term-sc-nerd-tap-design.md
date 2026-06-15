# Sarasa Term SC Nerd Font — 自动构建 Homebrew Tap 设计

**日期**: 2026-06-15
**状态**: 已批准,待实现

## 目标

自动化生产「保留 CJK 2:1 宽度 + 自定义图标尺寸」的 Nerd Font 补丁版 Sarasa Term SC,通过自有 Homebrew tap 分发,使 `brew update && brew upgrade` 能自动跟随上游 Sarasa 新版本,无需手动重打。

现有的 jonz94/Sarasa-Gothic-Nerd-Fonts 已做类似事情,但使用默认图标尺寸;本项目固化用户调好的 `--cell` 放大参数,这是自建的核心理由。

## 范围 (MVP)

- 家族:**Term**
- 字形集 (orthography):**SC**(简体)
- 字重:**RIBBI** — Regular / Bold / Italic / BoldItalic
- 产物:4 个 patched TTF 合成 **1 个 TTC**;Release 同时附 4 个独立 TTF
- 非目标(以后按需加,仅改配置数组):Mono/Fixed 家族、TC/J/K 字形集、非 RIBBI 字重、Gothic/UI 比例字体

## 架构:单仓库

仓库 `wangkezun/homebrew-sarasa-term-sc-nerd` 同时承担两个角色:

1. **构建自动化**:`.github/workflows/build.yml`
2. **Homebrew tap**:`Casks/font-sarasa-term-sc-nerd.rb`

CI 用内置 `GITHUB_TOKEN` 直接 push 回本仓库更新 cask,无需额外 PAT。

(备选方案 B 双仓库 = jonz94 模式,需跨仓库 PAT;单家族 MVP 不值,故采用单仓库。)

## 安装体验

```bash
brew tap wangkezun/sarasa-term-sc-nerd
brew install --cask font-sarasa-term-sc-nerd     # 装 TTC 单文件
# 之后:
brew update && brew upgrade                       # 自动拿新版本
```

字体族名:`SarasaTermSC Nerd Font Mono`(由 `--makegroups 1` 生成)。

## 构建流水线 (`build.yml`)

**触发**:每日 `schedule` cron + 手动 `workflow_dispatch`。`concurrency` 防并发冲突。

**步骤**:

1. 查 `be5invis/Sarasa-Gothic` 最新 release tag(带 token 防限流)。
2. 与仓库内 `version.txt` 比对,**相同则退出**(no-op,不产生空 release)。
3. 装 fontforge;下载**固定版本**的 nerd-fonts `FontPatcher.zip`(脚本 + `src/glyphs/`)。
4. 下载该版本 Sarasa 源,取 Term SC 的 4 个字重 TTF。
   - 实现注:优先下载上游独立 TTF 包;若上游仅提供 SuperTTC,则用 fontforge 的 `"file.ttc(子字体名)"` 语法抽取单 face。
5. 逐字重打补丁(参数见下)。
6. 用 `fonttools` 的 `TTCollection` 把 4 个 TTF 合成 `SarasaTermSCNerdFontMono.ttc`(相同表自动去重)。
7. **校验**(任一不过即 fail,不静默产坏字体):
   - 中文 `你` (U+4F60) advance = 1000(2:1 保住)
   - 拉丁 `A` advance = 500
   - 字形总数 < 65535
   - 族名 = `SarasaTermSC Nerd Font Mono`,4 个 face 子族正确
   - 关键图标存在(U+F07B folder / U+E725 git / U+F015 home)
   - TTC 含 4 个 face
8. 创建 GitHub Release(tag = Sarasa 版本号),上传 `.ttc` + 4 TTF 的 zip。
9. 算 TTC 的 sha256,更新 `Casks/font-sarasa-term-sc-nerd.rb`(version / sha256 / url),写 `version.txt`,commit & push。

## 打补丁配方(固化的核心参数)

```
fontforge -script font-patcher \
  --single-width-glyphs \           # 只把图标设单宽,不动 CJK → 保 2:1
  --makegroups 1 \                  # 干净族名 "SarasaTermSC Nerd Font Mono"
  --cell "0:540:-285:965" \         # 用户选定的图标放大档(右溢出 ~40)
  --fontawesome --fontawesomeext --fontlogos --octicons --pomicons \
  --powerline --powerlineextra --powersymbols --codicons --weather \
  -out <outdir> <SarasaTermSC-Weight.ttf>
# 关键:不加 --material(Material Design ~7000 字形),否则 SC 全字符集会突破 65535 上限
```

参数来由见「背景:为何是这些参数」。

## 安全 / 可复现 / 合规

- **65535 守门**:校验步骤硬断言字形数 < 65535。未来 Sarasa 增大、即便砍 MD 仍超限时,CI fail 提醒,而非产出无法生成/损坏的字体。
- **版本固定**:FontPatcher 版本写死在 workflow 里,保证跨时间可复现;升级 patcher 是显式动作。
- **限流**:所有 GitHub API 调用带 `GITHUB_TOKEN`。
- **许可证**:Sarasa 为 OFL-1.1,Nerd Fonts 为 MIT/OFL 混合。仓库内附两者协议文件。实现时**核对 Sarasa OFL 是否声明 Reserved Font Name**——若有,需确认 "SarasaTermSC Nerd Font" 这类改名分发合规(业界 jonz94 等已如此分发,大概率 OK,但需落实)。

## 测试策略

1. 先用 `workflow_dispatch` 手动跑通端到端,产出 release。
2. 真机 `brew tap` + `brew install --cask` 验证 TTC 安装、Warp 选用、中文宽度 + 图标正常。
3. 确认无误后再依赖每日 cron。

## 背景:为何是这些参数

源于一次手动打补丁的踩坑过程:

- **`--mono` 会压坏中文**:它把现有字形(含 CJK)全设单宽,中文从 1000 压到 500 导致重叠。正解是 `--single-width-glyphs`,只作用于新增图标。
- **`--complete` 会超 65535**:Sarasa SC 本体 ~5.7 万字形,加全套(含 ~7000 的 Material Design)达 67225,超过 sfnt 上限,fontforge 无法生成。砍掉 `--material` 后约 6 万,通过。lsd 用的图标在 4-hex PUA(Seti/Devicons/FontAwesome),不依赖 MD。
- **图标偏小**:单宽图标被限制在 1 个窄格(=半个 CJK 宽),显小。用 `--cell` 加宽缩放盒到 540 放大约一档;再大(如 650)右侧会溢出顶到后一个字符。540 是用户选定的平衡点(右溢出 ~40,lsd 输出图标后有空格,看不出)。
- **终端不认双宽图标**:Nerd 图标在 PUA(ambiguous width),终端按 wcwidth=1 渲染并忽略字体 advance;故无法靠"双宽图标"自动放大,只能在单宽内用 `--cell` 调。
