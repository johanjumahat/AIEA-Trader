# AIEA Trader

AI-powered self-improving trading Expert Advisor for MetaTrader 5.

## Overview

AIEA Trader is an autonomous MQL5 Expert Advisor that trades automatically and continuously improves its performance by learning from every completed trade. It maintains a detailed decision journal, analyzes trade outcomes, detects successful and unsuccessful patterns, and optimizes strategy parameters based on statistical evidence.

## Features

- **Autonomous Trading**: Executes trades based on multi-indicator confidence scoring
- **Self-Learning Engine**: Analyzes every completed trade for entry/exit quality, SL/TP appropriateness, and market conditions
- **Adaptive Optimization**: Automatically adjusts parameters after statistically meaningful evidence
- **Pattern Recognition**: Identifies best/worst market conditions, symbols, sessions, and indicator combinations
- **Strategy Evolution**: Maintains multiple parameter profiles with promotion/retirement and rollback
- **Trading Journal**: Complete trade database with 40+ data points per trade
- **Reporting**: Daily, weekly, and monthly performance reports
- **Safety Controls**: Never increases risk automatically, respects all loss/drawdown limits
- **On-Chart Dashboard**: Real-time performance display

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full system architecture.

## Installation

1. Copy `MQL5/Experts/AIEA_Trader.mq5` to your MT5 `MQL5/Experts/` folder
2. Copy the entire `MQL5/Include/AIEA/` folder to `MQL5/Include/`
3. Compile in MetaEditor (F7)
4. Attach to a chart and configure parameters

See [docs/USER_GUIDE.md](docs/USER_GUIDE.md) for the complete user guide.

## Indicators Used

- RSI (Relative Strength Index)
- EMA Fast & Slow (Moving Average crossover)
- Bollinger Bands
- MACD
- Stochastic Oscillator
- ATR (Average True Range)

## License

Proprietary — All rights reserved.
