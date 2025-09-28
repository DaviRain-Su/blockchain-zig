use std::{cmp::Ordering, collections::HashMap, env, str::FromStr};

use anyhow::{Context, Result, anyhow};
use helius::{
    Helius,
    rpc_client::RpcClient as HeliusRpcClient,
    types::{Asset, Cluster, GetAsset, GetAssetOptions, GetAssetSignatures, GetTokenAccounts},
};
use reqwest::Client;
use serde::Deserialize;
use solana_client::nonblocking::rpc_client::RpcClient as SolanaRpcClient;
use solana_sdk::pubkey::Pubkey;
use spl_token::{
    solana_program::program_pack::Pack,
    state::{Account as TokenAccountState, Mint},
};

const DEFAULT_CLUSTER: Cluster = Cluster::MainnetBeta;
const JUPITER_PRICE_ENDPOINT: &str = "https://price.jup.ag/v4/price";

struct HolderSnapshot {
    token_account: String,
}

struct AggregatedHolder {
    owner: String,
    total_raw: u128,
    token_accounts: Vec<HolderSnapshot>,
}

impl AggregatedHolder {
    fn total_ui(&self, decimals: u8) -> f64 {
        let factor = 10f64.powi(decimals as i32);
        (self.total_raw as f64) / factor
    }

    fn primary_account(&self) -> Option<&str> {
        self.token_accounts
            .first()
            .map(|snapshot| snapshot.token_account.as_str())
    }

    fn account_count(&self) -> usize {
        self.token_accounts.len()
    }
}

struct HolderToken {
    mint: String,
    amount_ui: f64,
    decimals: u8,
    metadata: TokenMetadata,
    price_usd: Option<f64>,
    value_usd: Option<f64>,
}

#[derive(Clone, Default)]
struct TokenMetadata {
    name: Option<String>,
    symbol: Option<String>,
    decimals: Option<u8>,
    price_usd: Option<f64>,
}

impl TokenMetadata {
    fn label(&self, fallback: &str) -> String {
        if let Some(symbol) = self.symbol.as_ref().filter(|s| !s.is_empty()) {
            if let Some(name) = self
                .name
                .as_ref()
                .filter(|n| !n.is_empty() && n.as_str() != symbol.as_str())
            {
                return format!("{} / {}", symbol, name);
            }
            return symbol.clone();
        }
        if let Some(name) = self.name.as_ref().filter(|n| !n.is_empty()) {
            return name.clone();
        }
        fallback.to_string()
    }
}

impl PriceFetcher {
    fn new() -> Result<Self> {
        let client = Client::builder()
            .user_agent("solana-cli-jupiter-price")
            .build()
            .context("初始化 Jupiter HTTP 客户端失败")?;
        Ok(Self {
            client,
            cache: HashMap::new(),
        })
    }

    async fn get_price(&mut self, mint: &str) -> Result<Option<f64>> {
        if let Some(cached) = self.cache.get(mint) {
            return Ok(*cached);
        }

        let url = format!("{}?ids={}", JUPITER_PRICE_ENDPOINT, mint);
        let response = self.client.get(&url).send().await;

        let price = match response {
            Ok(resp) => {
                if resp.status().is_success() {
                    let payload: JupiterPriceResponse = resp
                        .json()
                        .await
                        .context("解析 Jupiter price 响应失败")?;
                    payload
                        .data
                        .get(mint)
                        .and_then(|entry| entry.price)
                } else {
                    None
                }
            }
            Err(err) => {
                println!(
                    "    › Jupiter price 请求失败 ({}): {}",
                    mint, err
                );
                None
            }
        };

        self.cache.insert(mint.to_string(), price);
        Ok(price)
    }
}

struct PriceFetcher {
    client: Client,
    cache: HashMap<String, Option<f64>>,
}

#[derive(Deserialize)]
struct JupiterPriceResponse {
    #[serde(default)]
    data: HashMap<String, JupiterPriceEntry>,
}

#[derive(Deserialize)]
struct JupiterPriceEntry {
    #[serde(default)]
    price: Option<f64>,
}

/// 使用 Helius Rust SDK (RPC) 分析指定 SPL 代币
pub async fn analyze_token(
    mint: &str,
    api_key: Option<String>,
    _page: u64,
    _page_size: u64,
    top_holders: usize,
    top_other_tokens: usize,
    transfer_limit: usize,
    holders_only: bool,
    solana_rpc: &SolanaRpcClient,
) -> Result<()> {
    let api_key = resolve_api_key(api_key)?;
    let mint_pubkey = Pubkey::from_str(mint).context("无效的代币 mint 地址")?;

    let decimals = fetch_mint_decimals(solana_rpc, &mint_pubkey).await?;
    let supply_info = solana_rpc.get_token_supply(&mint_pubkey).await.ok();

    let helius = Helius::new_with_async_solana(api_key.as_str(), DEFAULT_CLUSTER)
        .context("初始化 Helius SDK 失败")?;
    let helius_rpc = helius.rpc_client.clone();

    let mut metadata_cache: HashMap<String, TokenMetadata> = HashMap::new();
    let mut decimals_cache = HashMap::new();
    decimals_cache.insert(mint.to_string(), decimals);
    let mut price_fetcher = PriceFetcher::new()?;

    let mint_metadata =
        match get_or_fetch_metadata(mint, &mut metadata_cache, helius_rpc.as_ref()).await {
            Ok(meta) => {
                if let Some(meta_decimals) = meta.decimals {
                    decimals_cache
                        .entry(mint.to_string())
                        .or_insert(meta_decimals);
                }
                meta
            }
            Err(err) => {
                println!("提示：获取代币元数据失败 ({})，将仅显示 Mint 地址。", err);
                TokenMetadata::default()
            }
        };
    let base_label = mint_metadata.label(mint);

    let largest_accounts = solana_rpc
        .get_token_largest_accounts(&mint_pubkey)
        .await
        .context("获取代币最大持有人失败")?;

    if largest_accounts.is_empty() {
        println!("RPC 未返回任何代币账户，可能该代币暂无持仓或 mint 地址无效。");
        return Ok(());
    }

    let mut account_pubkeys = Vec::new();
    let mut account_balances = Vec::new();
    for balance in largest_accounts {
        if let Ok(pubkey) = Pubkey::from_str(&balance.address) {
            account_pubkeys.push(pubkey);
            account_balances.push(balance);
        }
    }

    if account_pubkeys.is_empty() {
        println!("未能解析 RPC 返回的代币账户地址。");
        return Ok(());
    }

    let account_infos = solana_rpc
        .get_multiple_accounts(&account_pubkeys)
        .await
        .context("获取代币账户详情失败")?;

    let mut aggregated_map: HashMap<String, AggregatedHolder> = HashMap::new();
    for ((balance, pubkey), account_opt) in account_balances
        .into_iter()
        .zip(account_pubkeys.into_iter())
        .zip(account_infos.into_iter())
    {
        let Some(account) = account_opt else { continue };
        let token_account = TokenAccountState::unpack(&account.data)
            .map_err(|_| anyhow!("解析代币账户 {} 失败", pubkey))?;
        let owner_key = token_account.owner.to_string();
        let raw_amount = balance.amount.amount.parse::<u128>().unwrap_or_default();
        if raw_amount == 0 {
            continue;
        }

        let entry = aggregated_map
            .entry(owner_key.clone())
            .or_insert_with(|| AggregatedHolder {
                owner: owner_key.clone(),
                total_raw: 0,
                token_accounts: Vec::new(),
            });
        entry.total_raw += raw_amount;
        entry.token_accounts.push(HolderSnapshot {
            token_account: pubkey.to_string(),
        });
    }

    if aggregated_map.is_empty() {
        println!("未能汇总出有效的持有人数据。");
        return Ok(());
    }

    let mut holders = aggregated_map.into_values().collect::<Vec<_>>();
    holders.sort_by(|a, b| b.total_raw.cmp(&a.total_raw));

    let display_count = holders.len().min(top_holders.max(1));

    println!(
        "=== {} ({}) 的持有人清单 (前 {} 名 / 共 {} 名) ===",
        base_label,
        mint,
        display_count,
        holders.len()
    );
    println!("代币精度: {} 位小数", decimals);
    if let Some(supply) = supply_info {
        if let Some(ui_amount) = supply.ui_amount {
            println!("链上报告的总供应量: {:.6}", ui_amount);
        }
    }

    let mut total_raw = 0u128;
    for (idx, holder) in holders.iter().enumerate().take(display_count) {
        total_raw += holder.total_raw;
        let account_hint = holder
            .primary_account()
            .unwrap_or("<unknown-token-account>");
        println!(
            "{:>3}. {} 持有 {:.6} 枚 (共 {} 个代币账户，示例: {})",
            idx + 1,
            holder.owner,
            holder.total_ui(decimals),
            holder.account_count(),
            account_hint
        );
    }

    let total_ui = total_raw as f64 / 10f64.powi(decimals as i32);
    println!("小计 (前 {} 名): {:.6} 枚", display_count, total_ui);

    if holders_only {
        println!("\n提示：使用 --top-holders N 可调整展示数量。");
        return Ok(());
    }

    println!("\n=== 持有人常见其它 SPL 代币持仓 (按余额排序) ===");
    for holder in holders.iter().take(display_count) {
        let others = match fetch_owner_top_tokens(
            helius_rpc.as_ref(),
            &holder.owner,
            mint,
            top_other_tokens,
            &mut price_fetcher,
            &mut decimals_cache,
            &mut metadata_cache,
            solana_rpc,
        )
        .await
        {
            Ok(tokens) => tokens,
            Err(err) => {
                println!("- {} 的其它 SPL 代币未能成功获取 ({})", holder.owner, err);
                continue;
            }
        };

        if others.is_empty() {
            println!("- {} 暂无其它 SPL 代币余额 (或不足筛选条件)", holder.owner);
            continue;
        }

        println!("- {} 还持有:", holder.owner);
        for token in others {
            let token_label = token.metadata.label(&token.mint);
            let price_info = token
                .price_usd
                .map(|p| format!("价格: ${:.6}", p))
                .unwrap_or_else(|| "价格: 未知".to_string());
            let value_info = token
                .value_usd
                .map(|v| format!("≈ ${:.2}", v))
                .unwrap_or_else(|| "≈ $-".to_string());
            println!(
                "    - {} ({}) : {:.6} 枚 (精度: {}) [{} | {}]",
                token_label, token.mint, token.amount_ui, token.decimals, price_info, value_info
            );
        }
    }

    if transfer_limit > 0 {
        if decimals > 0 {
            println!(
                "\n提示：getSignaturesForAsset 主要适用于 NFT/cNFT。当前代币精度为 {}，跳过签名查询。",
                decimals
            );
        } else {
            println!(
                "\n=== 最近的 {} 条代币相关交易签名 (基于 DAS getSignaturesForAsset) ===",
                transfer_limit
            );
            match helius_rpc
                .get_signatures_for_asset(GetAssetSignatures {
                    id: Some(mint.to_string()),
                    limit: Some(transfer_limit.min(u32::MAX as usize) as u32),
                    ..Default::default()
                })
                .await
            {
                Ok(signatures) => {
                    if signatures.items.is_empty() {
                        println!("未获取到交易签名，可稍后再试或调整 limit 值。");
                    } else {
                        for (sig, _slot) in signatures.items {
                            println!("- {}", sig);
                        }
                    }
                }
                Err(err) => {
                    println!(
                        "未能获取交易签名，Helius 返回: {} (部分资产暂不支持该接口)",
                        err
                    );
                }
            }
        }
    } else {
        println!("\n提示：使用 --transfer-limit N 可查看近期代币交易签名。");
    }

    println!(
        "\n说明：当前使用 Helius RPC SDK 获取数据，无法直接获得成本或 USD 估值。如需更全面的 Token API，请关注官方更新。"
    );

    Ok(())
}

fn resolve_api_key(api_key: Option<String>) -> Result<String> {
    if let Some(explicit) = api_key {
        if !explicit.trim().is_empty() {
            return Ok(explicit);
        }
    }

    env::var("HELIUS_API_KEY").map_err(|_| {
        anyhow!("未提供 Helius API key。请使用 --api-key 或设置环境变量 HELIUS_API_KEY")
    })
}

fn build_token_accounts_request(
    owner: Option<String>,
    mint: Option<String>,
    page: u64,
    page_size: u64,
) -> GetTokenAccounts {
    GetTokenAccounts {
        owner,
        mint,
        limit: Some(page_size.min(u32::MAX as u64) as u32),
        page: Some(page.min(u32::MAX as u64) as u32),
        before: None,
        after: None,
        options: None,
        cursor: None,
    }
}

async fn fetch_owner_top_tokens(
    helius_rpc: &HeliusRpcClient,
    owner: &str,
    skip_mint: &str,
    limit: usize,
    price_fetcher: &mut PriceFetcher,
    decimals_cache: &mut HashMap<String, u8>,
    metadata_cache: &mut HashMap<String, TokenMetadata>,
    solana_rpc: &SolanaRpcClient,
) -> Result<Vec<HolderToken>> {
    if limit == 0 {
        return Ok(Vec::new());
    }

    let request =
        build_token_accounts_request(Some(owner.to_string()), None, 1, (limit * 5) as u64);
    let response = helius_rpc
        .get_token_accounts(request)
        .await
        .context("调用 getTokenAccounts(owner) 失败")?;

    let mut tokens = Vec::new();
    for account in response.token_accounts {
        let mint = match account.mint {
            Some(m) => m,
            None => continue,
        };
        if mint == skip_mint {
            continue;
        }
        let amount_raw = account.amount.unwrap_or(0);
        if amount_raw == 0 {
            continue;
        }

        let decimals = match get_or_fetch_decimals(&mint, decimals_cache, solana_rpc).await {
            Ok(value) => value,
            Err(err) => {
                println!("    › 获取 {} 精度失败 ({})，已跳过", mint, err);
                continue;
            }
        };

        let mut metadata = get_or_fetch_metadata(&mint, metadata_cache, helius_rpc)
            .await
            .unwrap_or_default();
        if let Some(meta_decimals) = metadata.decimals {
            decimals_cache.entry(mint.clone()).or_insert(meta_decimals);
        }

        let price_usd = match metadata.price_usd {
            Some(price) => Some(price),
            None => price_fetcher.get_price(&mint).await?,
        };

        let price_usd = match price_usd {
            Some(price) => {
                metadata.price_usd = Some(price);
                metadata_cache.insert(mint.clone(), metadata.clone());
                price
            }
            None => {
                println!("    › {} 暂无 Jupiter 报价，已跳过", mint);
                continue;
            }
        };

        let amount_ui = ui_amount(amount_raw, decimals);
        tokens.push(HolderToken {
            mint,
            amount_ui,
            decimals,
            metadata,
            price_usd: Some(price_usd),
            value_usd: Some(price_usd * amount_ui),
        });
    }

    tokens.sort_by(|a, b| {
        b.value_usd
            .unwrap_or(0.0)
            .partial_cmp(&a.value_usd.unwrap_or(0.0))
            .unwrap_or(Ordering::Equal)
    });
    tokens.truncate(limit);

    Ok(tokens)
}

async fn get_or_fetch_decimals(
    mint: &str,
    cache: &mut HashMap<String, u8>,
    solana_rpc: &SolanaRpcClient,
) -> Result<u8> {
    if let Some(decimals) = cache.get(mint) {
        return Ok(*decimals);
    }

    let mint_pubkey = Pubkey::from_str(mint).context("解析其他代币 mint 失败")?;
    let decimals = fetch_mint_decimals(solana_rpc, &mint_pubkey).await?;
    cache.insert(mint.to_string(), decimals);
    Ok(decimals)
}

async fn fetch_mint_decimals(client: &SolanaRpcClient, mint_pubkey: &Pubkey) -> Result<u8> {
    let account = client
        .get_account(mint_pubkey)
        .await
        .with_context(|| format!("获取 mint {} 账户失败", mint_pubkey))?;

    let mint_state = Mint::unpack(&account.data).map_err(|_| anyhow!("解析 mint 账户数据失败"))?;

    Ok(mint_state.decimals)
}

async fn get_or_fetch_metadata(
    mint: &str,
    cache: &mut HashMap<String, TokenMetadata>,
    helius_rpc: &HeliusRpcClient,
) -> Result<TokenMetadata> {
    if let Some(metadata) = cache.get(mint) {
        return Ok(metadata.clone());
    }

    let asset = helius_rpc
        .get_asset(GetAsset {
            id: mint.to_string(),
            display_options: Some(GetAssetOptions {
                show_fungible: true,
                ..Default::default()
            }),
        })
        .await?
        .map(token_metadata_from_asset)
        .unwrap_or_default();

    cache.insert(mint.to_string(), asset.clone());
    Ok(asset)
}

fn token_metadata_from_asset(asset: Asset) -> TokenMetadata {
    let name = asset
        .content
        .as_ref()
        .and_then(|content| content.metadata.name.clone());
    let symbol = asset
        .content
        .as_ref()
        .and_then(|content| content.metadata.symbol.clone())
        .or_else(|| {
            asset
                .token_info
                .as_ref()
                .and_then(|info| info.symbol.clone())
        });
    let decimals = asset
        .token_info
        .as_ref()
        .and_then(|info| info.decimals)
        .and_then(|d| {
            if d >= 0 && d <= u8::MAX as i32 {
                Some(d as u8)
            } else {
                None
            }
        });
    let price_usd = asset
        .token_info
        .as_ref()
        .and_then(|info| info.price_info.as_ref())
        .map(|info| info.price_per_token as f64);

    TokenMetadata {
        name,
        symbol,
        decimals,
        price_usd,
    }
}

fn ui_amount(raw: u64, decimals: u8) -> f64 {
    let factor = 10f64.powi(decimals as i32);
    (raw as f64) / factor
}
