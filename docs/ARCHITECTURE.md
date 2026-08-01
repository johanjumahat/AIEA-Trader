# AIEA Trader — Architecture

## System Overview

AIEA Trader is a self-improving MQL5 Expert Advisor for MetaTrader 5. It trades autonomously, maintains a detailed journal of every trade, analyzes performance patterns, and continuously optimizes its strategy parameters based on statistical evidence.

## Module Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AIEA_Trader.mq5                        │
│                   (Main EA Entry Point)                   │
├──────────┬──────────┬──────────┬──────────┬─────────────┤
│  Config  │ Indicator │   Risk   │ Trading  │  Learning   │
│  .mqh    │ Engine    │ Manager  │ Journal  │  Engine     │
│          │ .mqh     │ .mqh     │ .mqh     │ .mqh        │
├──────────┼──────────┴──────────┴──────────┼─────────────┤
│  Pattern  │       Strategy Evolution       │ Optimization │
│ Recognition│       .mqh                     │ Engine .mqh  │
│ .mqh      │                                │              │
├───────────┴────────────────────────────────┴──────────────┤
│         Report Generator .mqh    │   Dashboard .mqh      │
└───────────────────────────────────┴───────────────────────┘
```

## File Structure

```
AIEA-Trader/
├── MQL5/
│   ├── Experts/
│   │   └── AIEA_Trader.mq5        # Main EA file
│   └── Include/
│       └── AIEA/
│           ├── Config.mqh          # Enums, structs, parameter sets
│           ├── IndicatorEngine.mqh  # Technical indicator management
│           ├── RiskManager.mqh      # Position sizing, safety controls
│           ├── TradingJournal.mqh   # File-based trade journal database
│           ├── LearningEngine.mqh   # Post-trade analysis & lessons
│           ├── PatternRecognition.mqh # Pattern detection & ranking
│           ├── StrategyEvolution.mqh  # Multi-profile management
│           ├── OptimizationEngine.mqh # Adaptive parameter optimization
│           ├── ReportGenerator.mqh   # Daily/weekly/monthly reports
│           └── Dashboard.mqh        # On-chart performance display
├── Tests/
│   └── AIEA_TestSuite.mq5         # Unit tests
└── docs/
    ├── ARCHITECTURE.md            # This file
    └── USER_GUIDE.md              # User guide
```

## Data Flow

### 1. Trade Execution Flow
```
OnTick → IsNewBar → EvaluateSignal → CheckRisk → OpenTrade → RecordPending
```

### 2. Trade Analysis Flow
```
OnTradeTransaction → ProcessClosedTrade → LearningEngine.AnalyzeTrade
  → AssessEntryTiming → AssessExitTiming → AssessStopLoss → AssessTakeProfit
  → GenerateLesson → CalculatePerformanceImpact → WriteToJournal
```

### 3. Optimization Flow
```
RunOptimizationCycle (every N minutes) → UpdateAllProfileScores
  → OptimizationEngine.RunOptimization → ProposeChanges
  → [Auto-approve or Manual Approve] → ApplyApprovedChanges → SaveProfiles
```

### 4. Strategy Evolution Flow
```
ProfileScoreUpdate → CompareProfiles → PromoteBestProfile
  → RetirePoorProfiles → [Revert if performance degrades]
```

## Key Design Decisions

### File-Based Storage
The journal and profile data use MQL5 file I/O (CSV format) stored in the `MQL5/Files/AIEA_Trader/` directory. This persists across terminal restarts and is human-readable.

### Statistical Significance
Parameter changes are only proposed after a configurable minimum number of trades (`InpMinEvidenceTrades`, default 10). Single wins/losses never trigger changes.

### Safety First
- Position size is **never** increased automatically — only decreased for poorly performing profiles
- Daily loss and drawdown limits halt all trading
- User can review and approve/reject every proposed parameter change
- Previous parameter profiles are retained for rollback

### Indicator Suite
The EA uses 6 indicators in combination:
- RSI (Relative Strength Index)
- Fast EMA & Slow EMA (Moving Average crossover)
- Bollinger Bands (volatility + mean reversion)
- MACD (momentum)
- Stochastic (overbought/oversold)
- ATR (volatility for SL/TP placement)

### Market Regime Detection
Based on ATR%, Bollinger Band width, and MA separation:
- **Trending**: Significant MA separation
- **Ranging**: MAs close together, moderate BB width
- **Volatile**: High ATR% and wide BB width
- **Unknown**: Insufficient data

### Confidence Scoring
Entry confidence (0-100) is calculated by summing indicator agreements:
- RSI alignment: up to 20 points
- MA crossover alignment: up to 15 points
- MACD alignment: up to 15 points
- Stochastic alignment: up to 10 points
- Bollinger Band position: up to 10 points
- Regime bonus: up to 10 points

A trade is only entered if confidence exceeds `minConfidence` (default 60).

### Profile Management
- Up to 10 concurrent parameter profiles
- Each profile has its own performance score
- The active profile can be switched manually or auto-promoted
- Poor profiles can be retired
- Full rollback history maintained

## Installation

1. Copy `AIEA_Trader.mq5` to `MQL5/Experts/` in your MT5 data folder
2. Copy the entire `AIEA/` folder to `MQL5/Include/`
3. Compile in MetaEditor (F7)
4. Attach to a chart and configure input parameters
5. The EA will create `MQL5/Files/AIEA_Trader/` for journal and profile data

## Testing

1. Copy `AIEA_TestSuite.mq5` to `MQL5/Scripts/`
2. Compile and run in MetaEditor
3. Results are printed to the Experts tab

## Backtesting

The EA supports MT5 Strategy Tester with a custom optimization criterion that combines profit factor, trade count, and win rate.
