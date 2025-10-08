# PLANNING.md

## 概要

本ドキュメントは、Quantstamp による監査レポート（2025 年 9 月 30 日）で指摘された問題点（KYU-1〜KYU-4, S1〜S5）を体系的に修正するための具体的な改善計画です。
各修正は独立したコミットとして進め、`audit-fixes` ブランチ上で順次対応していきます。

---

## 対象範囲

- 対象リポジトリ: `KyuzanInc/simple-p2e-game`
- 対象ファイル: 主に `SBTSale.sol`, `SoulboundToken.sol`, `ISBTSale.sol`
- 目的: コントラクトの安全性・信頼性・可読性を高め、再監査に十分耐え得る状態にすること

---

## KYU-1：スリッページ制御の実効化（Medium）

### 問題点

`_validateSlippage()` が実質的に機能していない状態でした。
また、`_swapSMPtoOASForRevenueRecipient()` において `minOut` の制約がなく、板の薄い状態で不利な価格約定を許容してしまう可能性があります。
さらに `_provideLiquidity()` 内で `minBPT = 0` となっており、受け取る BPT 数量に下限が設定されていません。

### 改善方針（Quantstamp 推奨に準拠）

1. **署名ペイロードの変更**
   - `maxSlippageBps` パラメータを削除
   - `minRevenueOAS` パラメータを追加（収益受取者が受け取るべき最小 OAS 量）
   - オフチェーンで `amount` にスリッページを含めて計算（例: 期待値 x、許容 5% なら `amount = x * 1.05`）

2. **`_validateSlippage()` の削除**
   - オフチェーンで `amount` にスリッページが含まれるため、オンチェーンでの検証は不要

3. **`_swapSMPtoOASForRevenueRecipient()` の改善**
   - `minRevenueOAS` を引数として受け取る
   - `revenueOAS >= minRevenueOAS` を必須条件とする

4. **`_provideLiquidity()` の改善**
   - 受け取った BPT が必ず `> 0` であることを確認

### 想定コミット

- `feat: implement effective slippage control with off-chain calculation and minRevenueOAS`

### テスト観点

- `minRevenueOAS` 未達時に revert すること
- 流動性提供で BPT = 0 の場合に revert すること
- 通常時は期待通りの価格帯で約定すること
- 署名検証が新しいペイロード構造で正しく機能すること

---

## KYU-2：所有権移転の安全化（Low）

### 問題点

`transferOwnership` がワンショットで完了するため、誤ったアドレスを指定した場合に回復不能になるリスクがあります。

### 改善方針

`OwnableUpgradeable` を `Ownable2StepUpgradeable` に置き換え、所有権移転を二段階承認方式に変更します。
`transferOwnership(newOwner)` 後、`acceptOwnership()` によってのみ新オーナーへ移転が確定するようにします。

### 想定コミット

- `refactor: migrate to Ownable2StepUpgradeable for safer ownership transfer`

### テスト観点

- `transferOwnership` の後は旧オーナーが引き続き有効であること。
- `acceptOwnership` により新オーナーへ確実に移転されること。
- 無効アドレスや同一アドレス指定時には revert すること。

---

## KYU-3：所有権放棄の防止（Low）

### 問題点

`renounceOwnership()` がそのまま実行可能なため、誤操作によりコントラクト管理不能となるリスクがあります。

### 改善方針

1. `ISBTSale.sol` にカスタムエラー `OwnershipCannotBeRenounced()` を定義
2. `SBTSale.sol` で `renounceOwnership()` をオーバーライドし、常にカスタムエラーで revert
3. 他のエラーとの一貫性を保ち、ガス効率も向上

これにより、コントラクトの意図しない放棄を防ぎます。

### 想定コミット

- `fix: disable renounceOwnership to avoid accidental loss of control`

### テスト観点

- `renounceOwnership()` 呼び出し時に `OwnershipCannotBeRenounced` エラーで revert すること
- 非オーナーが呼び出した場合も適切に revert すること

---

## KYU-4：SoulboundToken のインターフェース対応強化（Undetermined）

### 問題点

`SoulboundToken` の `supportsInterface()` が `ISBTSaleERC721` に対応しておらず、
`SBTSale.setSBTContract()` での型検証が不完全でした。

### 改善方針

1. `SoulboundToken.supportsInterface()` に
   `if (interfaceId == type(ISBTSaleERC721).interfaceId) return true;` を追加。
2. `SBTSale.setSBTContract()` に `supportsInterface` チェックを追加し、対応していない実装は拒否。

### 想定コミット

- `fix: add ISBTSaleERC721 to supportsInterface and enforce validation in SBTSale`

### テスト観点

- 正しいインターフェースを実装したコントラクトのみ通過すること。
- 偽装実装の場合は revert すること。

---

## S1：ドキュメントの整備（Info）

### 問題点

ストレージ変数や関数に関する説明コメントが不足しており、仕様理解・保守が難しい状態です。

### 改善方針

すべての public/external 関数に NatSpec コメントを追加します。
また、EIP-712 署名ペイロードの構造を `/docs/contracts/payload.md` に明文化します。

### 想定コミット

- `docs: add full NatSpec and payload specification`

---

## S2：エラーメッセージの文脈強化（Info）

### 問題点

現在のエラーメッセージがシンプルすぎて、トランザクション失敗時の解析が困難です。

### 改善方針

カスタムエラーに引数を追加し、失敗時の具体的値をエラーとして返すようにします。
例：

```solidity
error InvalidRecipient(address recipient);
error InsufficientRevenue(uint256 minRequired, uint256 actual);
error InsufficientBPTReceived(uint256 received);
```

また、主要 setter イベントには old/new 値を含め、監視しやすくします。

### 想定コミット

- `feat: enrich custom errors and events with contextual data`

---

## S3：mintTimeOf() の存在チェック（Info）

### 問題点

存在しないトークン ID に対して `mintTimeOf()` を呼び出した場合に revert しないため、誤った値を返す恐れがあります。

### 改善方針

以下のチェックを追加します：

```solidity
require(_exists(tokenId), "Token does not exist");
```

### 想定コミット

- `fix: add existence check to mintTimeOf()`

---

## S4：OpenZeppelin バージョン固定（Info）

### 問題点

OZ ライブラリを `^5.0.1` のような範囲指定で導入しており、将来的に破壊的変更を取り込むリスクがあります。

### 改善方針

依存を固定し、ビルドの再現性を高めます。

- `package.json` の `openzeppelin` 依存を `=5.0.1` に変更
- `foundry.toml` のライブラリ指定も明示固定

### 想定コミット

- `chore: lock OZ version to ensure stability`

---

## S5：一般的改善・リファクタリング（Info）

### 問題点

コード内に冗長な処理・重複チェック・イベント不足などの軽微な問題が複数存在します。

### 改善方針

- `buyer` 引数を削除し、`msg.sender` に統一
- `_swap` の `deadline` を削除または実効化（TWAP と併用を検討）
- `_getTotalSMPPrice()` の重複チェック削除
- `_payWithSwapToSMP()` の `if (actualOut != requiredSMP)` チェックを削除（`_swap()` で検証済み）
- `setBaseURI()` に `BaseURIUpdated(old, new)` を追加
- `SoulboundToken.setBaseURI()` に空文字列チェックを追加
- `setSigner` / `setSBTContract` に同値チェックを導入（同値なら no-op）
- `type(IFace).interfaceId` を使用してマジック値を排除
- `_isPOAS()` / `_isSMP()` を `getPOAS()` / `getSMP()` に依存させてコード重複を削減
- `_getPoolAssets()` の結果を immutable 化（コスト削減）

### 想定コミット

- `refactor: cleanup redundant checks and add missing events`

---

## テスト強化

最終的に Branch Coverage 85%以上、Line Coverage 95%以上を目標とします。
テスト追加項目は以下の通りです：

- スリッページ制御（`minRevenueOAS` 未達時の revert、BPT = 0 時の revert）
- 所有権移転と renounce 禁止
- `ISBTSaleERC721` 準拠チェック
- `mintTimeOf()` の revert 確認
- 新しい署名ペイロード構造での検証

### 想定コミット

- `test: add boundary and negative case coverage`

---

## リリース

最終ステップとして以下を行います：

1. `CHANGELOG.md` に「Audit Fixes Completed」を追加
2. `/docs/audit/` に監査対応結果をまとめたドキュメントを配置
3. 必要に応じて Quantstamp に再監査を依頼

### 想定コミット

- `chore: finalize audit fixes and update changelog`
