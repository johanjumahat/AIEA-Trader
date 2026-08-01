# AIEA Trader — User Guide

## Getting Started

### Installation

1. **Locate your MT5 data folder**: Open MT5 → File → Open Data Folder
2. **Copy the EA**: Place `AIEA_Trader.mq5` in `MQL5/Experts/`
3. **Copy includes**: Place the entire `AIEA/` folder in `MQL5/Include/`
4. **Compile**: Open MetaEditor (F4), open `AIEA_Trader.mq5`, press F7
5. **Verify**: Check the Errors tab — should show 0 errors, 0 warnings
6. **Attach**: Drag AIEA_Trader from the Navigator panel onto a chart

### Input Parameters

#### General
| Parameter | Default | Description |
|-----------|---------|-------------|
| Timeframe | H1 | Trading timeframe |
| Symbol | (chart) | Symbol to trade (empty = chart symbol) |
| Magic Number | 20260802 | Unique ID for EA trades |
| Slippage | 10 | Maximum slippage in points |

#### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| Risk Percent | 1.0 | Risk per trade as % of equity |
| Max Daily Loss | 5.0 | Halt trading if daily loss exceeds this % |
| Max Drawdown | 20.0 | Halt trading if drawdown exceeds this % |
| Max Positions | 3 | Maximum simultaneous open positions |

#### Learning & Optimization
| Parameter | Default | Description |
|-----------|---------|-------------|
| Min Evidence Trades | 10 | Minimum trades before parameter changes are proposed |
| Auto-Approve Changes | false | If true, parameter changes apply automatically |
| Enable Learning | true | Enable post-trade analysis |
| Enable Optimization | true | Enable parameter optimization |

#### Reporting
| Parameter | Default | Description |
|-----------|---------|-------------|
| Enable Reports | true | Generate periodic reports |
| Enable Dashboard | true | Show on-chart dashboard |
| Report Interval | 60 | Minutes between report updates |
| Optimize Interval | 120 | Minutes between optimization cycles |

## How It Works

### Trading Logic

The EA evaluates a combination of 6 indicators on each new bar:

1. **RSI** — Oversold (<30) = buy signal, Overbought (>70) = sell signal
2. **MA Crossover** — Fast EMA above Slow EMA = bullish, below = bearish
3. **MACD** — Main above signal = bullish, below = bearish
4. **Stochastic** — Oversold (<20) = buy, Overbought (>80) = sell
5. **Bollinger Bands** — Price at lower band = buy, at upper band = sell
6. **ATR** — Used for dynamic stop loss and take profit placement

Each indicator contributes to a **confidence score** (0-100). The EA only enters a trade if confidence exceeds the configured threshold.

### Stop Loss & Take Profit

SL and TP are calculated dynamically using ATR:
- **Stop Loss** = Entry ± (ATR × stopLossDistance)
- **Take Profit** = Entry ± (ATR × takeProfitDistance)
- **Trailing Stop** = Follows price at ATR × trailingStop distance
- **Break-Even** = Moves SL to entry after ATR × breakEvenTrigger profit

### Position Sizing

Lot size is calculated based on:
- Risk percentage of account equity
- Stop loss distance in points
- Symbol tick value and size

### Learning Engine

After every trade closes, the EA analyzes:

- Was entry timing optimal? (based on MFE/MAE)
- Was exit timing optimal? (did we leave profit on the table?)
- Was stop loss too tight or too wide?
- Was take profit realistic?
- Did spread/slippage reduce profitability?
- Did volatility affect the outcome?
- Which indicators agreed or conflicted?
- What lesson can be learned?

Each lesson is stored in the journal and used to generate optimization proposals.

### Optimization

The optimization engine runs every 2 hours (configurable) and:

1. Updates all profile scores
2. Analyzes SL/TP tightness across recent trades
3. Proposes parameter adjustments
4. Requires statistical evidence (minimum trade count)
5. Never increases position size automatically
6. Saves all changes for audit trail

### Approval Workflow

When `Auto-Approve Changes` is OFF (default):
1. The EA proposes changes and logs them
2. You review proposed changes in the Experts log
3. Approve or reject via EA input or code modification
4. Approved changes are applied on the next optimization cycle

When `Auto-Approve Changes` is ON:
- Changes are applied automatically after meeting the evidence threshold
- Use with caution — only after thorough backtesting

### Strategy Evolution

The EA maintains multiple parameter profiles:

- **Default Profile**: The initial strategy configuration
- **Evolved Profiles**: Created during optimization with adjusted parameters
- **Backup Profiles**: Previous active profiles kept for rollback
- **Retired Profiles**: Poor performers that are no longer used

The EA automatically promotes better-performing profiles when they score significantly higher than the active profile.

### Dashboard

The on-chart dashboard shows:
- Account equity and balance
- Current drawdown
- Daily P&L
- Total trades, win rate, profit factor
- Expectancy and average risk:reward
- Active profile name and score
- Trading status (ACTIVE/HALTED)

## File Locations

All EA data is stored in `MQL5/Files/AIEA_Trader/`:
- `journal.csv` — Complete trade journal
- `profiles.csv` — Strategy parameter profiles
- `changes.csv` — Proposed and applied changes
- `reports.csv` — Generated reports

## Backtesting

1. Open Strategy Tester (Ctrl+R)
2. Select AIEA_Trader as the Expert
3. Choose symbol and timeframe
4. Set the testing period
5. Configure input parameters
6. Run the test

The custom optimization criterion combines profit factor, trade count, and win rate for meaningful comparison.

## Safety Features

- **Never increases risk automatically** — position size only decreases for poor performance
- **Daily loss limit** — trading halts if daily loss exceeds threshold
- **Max drawdown** — trading halts if drawdown exceeds threshold
- **Max positions** — limits simultaneous open trades
- **Spread filter** — skips trades when spread is too wide
- **Volatility filter** — skips trades in extreme volatility
- **Trading hours** — only trades within configured hours
- **Rollback capability** — can revert to any previous profile

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Failed to initialize indicators" | Check symbol name and timeframe |
| "Order failed: 10013" | Enable AutoTrading and check permissions |
| "Daily loss limit reached" | Wait for next day or increase limit |
| "Max drawdown reached" | Review strategy performance |
| No trades being taken | Lower minConfidence or check trading hours |
| Dashboard not showing | Set Enable Dashboard = true |

## Tips

- Start with **0.1% risk** for the first few weeks
- Use **Auto-Approve = false** until you trust the optimization
- Monitor the Experts tab for proposed changes
- Run backtests with at least 6 months of data
- Check the journal CSV periodically for insights
- Don't increase risk beyond 2% per trade
