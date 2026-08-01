# Changelog

All notable changes to AIEA Trader will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2026-08-02

### Added
- Complete MQL5 Expert Advisor source code (AIEA_Trader.mq5)
- Configuration module with enums, parameter sets, and journal entries (Config.mqh)
- Indicator engine managing RSI, EMA, Bollinger Bands, MACD, Stochastic, ATR
- Market regime detection (trending, ranging, volatile)
- Confidence-based entry scoring (0-100)
- Risk manager with position sizing, daily loss limits, and drawdown protection
- File-based trading journal with 40+ fields per trade
- Learning engine with entry/exit timing, SL/TP, and pattern analysis
- Lesson generation for every completed trade
- Pattern recognition by symbol, session, weekday, regime, and indicator combination
- Strategy evolution with multiple profiles, promotion, retirement, and rollback
- Optimization engine with statistical significance requirements
- Proposed change approval workflow (manual or auto)
- Report generator for daily, weekly, and monthly reports
- On-chart performance dashboard
- Unit test suite covering all modules
- Architecture documentation
- User guide

### Security
- Position size never increases automatically
- All parameter changes require statistical evidence
- User can approve or reject learned parameter changes
- Rollback history maintained for all optimizations
