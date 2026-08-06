//+------------------------------------------------------------------+
//| AIEA_Trader.mq5 — Main Expert Advisor                            |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//| Copyright 2026, AIEA Trader Project                               |
//+------------------------------------------------------------------+
#property copyright "2026, AIEA Trader"
#property version   "1.000"
#property strict
#property description "Self-Improving MT5 AI Trading EA"
#property description "Trades autonomously and learns from every trade."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "AIEA\Config.mqh"
#include "AIEA\IndicatorEngine.mqh"
#include "AIEA\RiskManager.mqh"
#include "AIEA\TradingJournal.mqh"
#include "AIEA\LearningEngine.mqh"
#include "AIEA\PatternRecognition.mqh"
#include "AIEA\StrategyEvolution.mqh"
#include "AIEA\OptimizationEngine.mqh"
#include "AIEA\ReportGenerator.mqh"
#include "AIEA\Dashboard.mqh"
#include "AIEA\NewsManager.mqh"

//==================================================================
//  INPUT PARAMETERS
//==================================================================

input group "=== General ==="
input ENUM_TIMEFRAMES InpTimeframe     = PERIOD_H1;     // Trading timeframe
input string          InpSymbol        = "";             // Symbol (empty = chart symbol)
input int             InpMagicNumber   = 20260802;       // Magic number
input int             InpSlippage      = 10;             // Max slippage in points

input group "=== Risk Management ==="
input double          InpRiskPercent   = 1.0;            // Risk per trade (%)
input double          InpMaxDailyLoss  = 5.0;            // Max daily loss (%)
input double          InpMaxDrawdown   = 20.0;           // Max drawdown (%)
input int             InpMaxPositions   = 3;             // Max open positions

input group "=== Learning & Optimization ==="
input int             InpMinEvidenceTrades = 10;          // Min trades for optimization
input bool            InpAutoApproveChanges = false;     // Auto-approve parameter changes
input bool            InpEnableLearning = true;           // Enable learning engine
input bool            InpEnableOptimization = true;       // Enable optimization engine

input group "=== Reporting ==="
input bool            InpEnableReports  = true;           // Generate reports
input bool            InpEnableDashboard = true;          // Enable on-chart dashboard

input group "=== Timing ==="
input int             InpReportIntervalMinutes = 60;      // Report update interval
input int             InpOptimizeIntervalMinutes = 120;  // Optimization interval

input group "=== Trading Hours ==="
input bool            InpTradeAllHours     = true;          // Trade 24 hours (ignore hour filter)

input group "=== Diagnostics ==="
input bool   InpVerbose           = true;           // Verbose logging to Experts tab
input int    InpHeartbeatSeconds  = 30;             // Heartbeat interval (seconds)
input double InpMinConfidenceOverride = 0.0;        // Override min confidence (0=use profile)
input double InpMaxSpreadOverride   = 0.0;          // Max spread in points (0=use profile, -1=AUTO detect per symbol)

input group "=== News Filter ==="
input bool   InpEnableNewsFilter  = true;           // Enable economic news filter
input int    InpNewsWarningHours  = 2;               // Hours before high-impact news to warn
input int    InpNewsBlockMinutes  = 15;              // Block trades N min before/after high-impact news
input int    InpNewsRefreshMinutes = 30;             // How often to refresh news calendar (minutes)
input ENUM_NEWS_IMPORTANCE_FILTER InpNewsImportance = NEWS_IMPORTANCE_MEDIUM_UP; // Which impact levels to show/track
input string InpNewsCountryFilter = "ALL";           // Country/currency filter: ALL or e.g. "US,EU,GB"

input group "=== Profit Lock ==="
input bool   InpEnableProfitLock  = true;            // Enable profit-lock SL (move SL to lock $ profit)
input double InpProfitLockTrigger = 2.0;            // Trigger: when net profit (incl. swap) exceeds this ($)
input double InpProfitLockTarget  = 1.0;            // Lock: move SL to secure this much net profit ($)
input int    InpProfitLockStopLevel = 0;            // Min stop level in points (0 = auto from broker)

input group "=== News Trade Protection ==="
input bool   InpNewsProtectTrades = true;            // Protect open trades before high-impact news
input int    InpNewsProtectMinutes = 60;             // Start protecting N min before news
input int    InpNewsReleaseMinutes = 60;             // Release protection N min after news
input int    InpNewsSLBufferPoints = 10;             // SL buffer in points above/below breakeven

//==================================================================
//  GLOBAL OBJECTS
//==================================================================

CTrade             trade;
CPositionInfo      positionInfo;
CSymbolInfo        symbolInfo;
CAccountInfo       accountInfo;

CIndicatorEngine    indicatorEngine;
CRiskManager        riskManager;
CTradingJournal      journal;
CLearningEngine      learningEngine;
CPatternRecognition  patternRecognition;
CStrategyEvolution   strategyEvolution;
COptimizationEngine  optimizationEngine;
CReportGenerator     reportGenerator;
CDashboard           dashboard;
CNewsManager          newsManager;

// Internal tracking
string             g_symbol;
int                g_lastBarTime = 0;
datetime           g_lastReportTime = 0;
datetime           g_lastOptimizeTime = 0;

// Pending trade info for journal
struct PendingTrade
{
   int      ticket;
   double   openPrice;
   double   stopLoss;
   double   takeProfit;
   double   volume;
   int      type;
   datetime openTime;
   double   confidence;
   string   entryRationale;
   int      profileId;
   double   rsiAtEntry;
   double   maFastAtEntry;
   double   maSlowAtEntry;
   double   bbUpperAtEntry;
   double   bbLowerAtEntry;
   double   macdMainAtEntry;
   double   macdSignalAtEntry;
   double   stochMainAtEntry;
   double   atrAtEntry;
   ENUM_MARKET_REGIME regime;
   double   spreadAtEntry;
   double   volatilityPercent;
   int      weekday;
   int      hour;
   string   session;
};

PendingTrade g_pendingTrades[];

//==================================================================
//  HELPER FUNCTIONS
//==================================================================

//--- Find index in pending trades array by ticket
int FindPendingTrade(int ticket)
{
   for(int i = 0; i < ArraySize(g_pendingTrades); i++)
   {
      if(g_pendingTrades[i].ticket == ticket)
         return i;
   }
   return -1;
}

//--- Add a pending trade
void AddPendingTrade(const IndicatorSnapshot &snap, int ticket, int orderType,
                     double confidence, string rationale, int profileId,
                     double sl, double tp, double volume)
{
   PendingTrade pt;
   pt.ticket          = ticket;
   pt.openPrice       = (orderType == ORDER_TYPE_BUY) ?
                        SymbolInfoDouble(g_symbol, SYMBOL_ASK) :
                        SymbolInfoDouble(g_symbol, SYMBOL_BID);
   pt.stopLoss        = sl;
   pt.takeProfit      = tp;
   pt.volume          = volume;
   pt.type            = orderType;
   pt.openTime        = TimeCurrent();
   pt.confidence      = confidence;
   pt.entryRationale  = rationale;
   pt.profileId       = profileId;
   pt.rsiAtEntry      = snap.rsi;
   pt.maFastAtEntry   = snap.maFast;
   pt.maSlowAtEntry   = snap.maSlow;
   pt.bbUpperAtEntry  = snap.bbUpper;
   pt.bbLowerAtEntry  = snap.bbLower;
   pt.macdMainAtEntry = snap.macdMain;
   pt.macdSignalAtEntry = snap.macdSignal;
   pt.stochMainAtEntry = snap.stochMain;
   pt.atrAtEntry      = snap.atr;
   pt.regime          = snap.regime;
   pt.spreadAtEntry   = (double)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   pt.volatilityPercent = snap.volatilityPercent;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   pt.weekday = dt.day_of_week;
   pt.hour    = dt.hour;
   pt.session = indicatorEngine.GetSessionName(dt.hour);

   ArrayResize(g_pendingTrades, ArraySize(g_pendingTrades) + 1);
   g_pendingTrades[ArraySize(g_pendingTrades) - 1] = pt;
}

//--- Remove a pending trade
void RemovePendingTrade(int index)
{
   int size = ArraySize(g_pendingTrades);
   for(int i = index; i < size - 1; i++)
      g_pendingTrades[i] = g_pendingTrades[i + 1];
   ArrayResize(g_pendingTrades, size - 1);
}

//--- Calculate MFE (Maximum Favorable Excursion) in points
double CalculateMFE(int ticket, int orderType, double openPrice, double closePrice)
{
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(point <= 0.0) return 0.0;

   double mfe = 0.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      // MFE = highest high during the trade - open price
      double highest = openPrice;
      if(HistorySelectByPosition(ticket))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
            {
               double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
               if(dealPrice > highest) highest = dealPrice;
            }
         }
      }
      mfe = (highest - openPrice) / point;
   }
   else
   {
      // MFE = open price - lowest low during the trade
      double lowest = openPrice;
      if(HistorySelectByPosition(ticket))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
            {
               double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
               if(dealPrice < lowest) lowest = dealPrice;
            }
         }
      }
      mfe = (openPrice - lowest) / point;
   }

   if(mfe < 0.0) mfe = 0.0;
   return mfe;
}

//--- Calculate MAE (Maximum Adverse Excursion) in points
double CalculateMAE(int ticket, int orderType, double openPrice, double closePrice)
{
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(point <= 0.0) return 0.0;

   double mae = 0.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      // MAE = open price - lowest low during the trade
      double lowest = openPrice;
      if(HistorySelectByPosition(ticket))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
            {
               double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
               if(dealPrice < lowest) lowest = dealPrice;
            }
         }
      }
      mae = (openPrice - lowest) / point;
   }
   else
   {
      // MAE = highest high during the trade - open price
      double highest = openPrice;
      if(HistorySelectByPosition(ticket))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
            {
               double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
               if(dealPrice > highest) highest = dealPrice;
            }
         }
      }
      mae = (highest - openPrice) / point;
   }

   if(mae < 0.0) mae = 0.0;
   return mae;
}

//--- Get the active parameter set
bool GetActiveParameters(ParameterSet &ps)
{
   int activeId = strategyEvolution.GetActiveProfileId();
   return strategyEvolution.GetProfileById(activeId, ps);
}

//--- Check if a new bar has formed
bool IsNewBar()
{
   datetime currentTime = iTime(g_symbol, InpTimeframe, 0);
   if(currentTime != g_lastBarTime)
   {
      g_lastBarTime = (int)currentTime;
      return true;
   }
   return false;
}

//--- Calculate entry rationale string
string GetEntryRationale(const IndicatorSnapshot &snap, int orderType)
{
   string rationale = "";

   if(orderType == ORDER_TYPE_BUY)
   {
      rationale += "Buy signal: ";
      if(snap.rsi < 30.0) rationale += "RSI oversold ";
      if(snap.maFast > snap.maSlow) rationale += "MA bullish crossover ";
      if(snap.macdMain > snap.macdSignal) rationale += "MACD bullish ";
      if(snap.stochMain < 20.0) rationale += "Stoch oversold ";
      if(snap.closePrice <= snap.bbLower) rationale += "Price at lower BB ";
   }
   else
   {
      rationale += "Sell signal: ";
      if(snap.rsi > 70.0) rationale += "RSI overbought ";
      if(snap.maFast < snap.maSlow) rationale += "MA bearish crossover ";
      if(snap.macdMain < snap.macdSignal) rationale += "MACD bearish ";
      if(snap.stochMain > 80.0) rationale += "Stoch overbought ";
      if(snap.closePrice >= snap.bbUpper) rationale += "Price at upper BB ";
   }

   switch(snap.regime)
   {
      case REGIME_TRENDING: rationale += "[Trending market]"; break;
      case REGIME_RANGING:  rationale += "[Ranging market]"; break;
      case REGIME_VOLATILE: rationale += "[Volatile market]"; break;
      default: rationale += "[Unknown regime]"; break;
   }

   return rationale;
}

//--- Check if spread is acceptable
bool IsSpreadAcceptable(const ParameterSet &params)
{
   long spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   return ((double)spread <= params.maxSpreadPoints);
}

//--- Check volatility filter
bool IsVolatilityAcceptable(const ParameterSet &params, double volatilityPercent)
{
   if(!params.volatilityFilter)
      return true;

   // Reject if volatility is too extreme
   if(volatilityPercent > 3.0)
      return false;

   return true;
}

//--- Open a trade
bool OpenTrade(int orderType, const IndicatorSnapshot &snap, const ParameterSet &params)
{
   double atr = snap.atr;
   if(atr <= 0.0) return false;

   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double askPrice = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   double slDistance = atr * params.stopLossDistance;
   double tpDistance = atr * params.takeProfitDistance;

   double sl, tp, price;
   if(orderType == ORDER_TYPE_BUY)
   {
      price = askPrice;
      sl = price - slDistance;
      tp = price + tpDistance;
   }
   else
   {
      price = bidPrice;
      sl = price + slDistance;
      tp = price - tpDistance;
   }

   // Normalize prices
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   price = NormalizeDouble(price, digits);

   // Calculate lot size
   double slPoints = MathAbs(price - sl) / point;
   double lotSize = riskManager.CalculateLotSize(params.positionSizePercent,
                                                  slPoints, g_symbol, atr);

   if(lotSize <= 0.0) return false;

   // Set trade parameters
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(g_symbol);

   // Send order
   bool success = false;
   if(orderType == ORDER_TYPE_BUY)
      success = trade.Buy(lotSize, g_symbol, price, sl, tp, "AIEA_Buy");
   else
      success = trade.Sell(lotSize, g_symbol, price, sl, tp, "AIEA_Sell");

   if(success)
   {
      int ticket = (int)trade.ResultOrder();
      double confidence = indicatorEngine.CalculateConfidence(snap, orderType);
      string rationale = GetEntryRationale(snap, orderType);

      AddPendingTrade(snap, ticket, orderType, confidence, rationale,
                      params.id, sl, tp, lotSize);

      riskManager.IncrementPositions();

      Print("[AIEA] Opened ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " ticket:", ticket, " lots:", DoubleToString(lotSize, 2),
            " price:", DoubleToString(price, digits),
            " SL:", DoubleToString(sl, digits),
            " TP:", DoubleToString(tp, digits),
            " confidence:", DoubleToString(confidence, 1));
   }
   else
   {
      Print("[AIEA] Order failed: ", trade.ResultRetcode(), " - ", trade.ResultComment());
   }

   return success;
}

//--- Manage open positions (trailing stop, break-even, profit lock)
void ManageOpenPositions(const ParameterSet &params)
{
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   double atr = 0.0;

   // Get current ATR using the indicator engine's persistent handle.
   // NEVER create a separate ad-hoc iATR() handle here — MT5 shares handles
   // by (symbol,timeframe,params), and repeatedly creating/releasing one every
   // tick races against the engine's own handle and can invalidate it (error 4807).
   if(!indicatorEngine.GetATRValue(atr) || atr <= 0.0)
      return;

   // Broker minimum stop level (in price units). If InpProfitLockStopLevel>0
   // we use that override instead.
   long brokerStopLevelPts = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = (InpProfitLockStopLevel > 0)
                        ? (point * InpProfitLockStopLevel)
                        : (point * (int)brokerStopLevelPts);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!positionInfo.SelectByTicket(ticket))
         continue;

      if(positionInfo.Magic() != InpMagicNumber)
         continue;

      if(positionInfo.Symbol() != g_symbol)
         continue;

      double openPrice  = positionInfo.PriceOpen();
      double currentSL  = positionInfo.StopLoss();
      double currentTP  = positionInfo.TakeProfit();
      long   posType    = positionInfo.PositionType();
      double volume     = positionInfo.Volume();
      double currentPrice = (posType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(g_symbol, SYMBOL_BID) :
                            SymbolInfoDouble(g_symbol, SYMBOL_ASK);

      double trailingDist = atr * params.trailingStop;
      double beTrigger = atr * params.breakEvenTrigger;

      //--- Profit Lock ---
      // When net profit (floating P/L + accumulated swap) exceeds the trigger
      // threshold, move the SL to a price that locks in InpProfitLockTarget $
      // of net profit.  "Net" = profit + swap + commission, matching what the
      // broker actually realises on close.
      bool profitLockApplied = false;
      if(InpEnableProfitLock)
      {
         // Current floating P/L from the position (already includes swap in MT5)
         double floatingPL = positionInfo.Profit() + positionInfo.Swap();
         // Commission is per-deal; approximate from the deal history if available
         double commission = 0.0;
         if(HistorySelectByPosition(ticket))
         {
            int deals = HistoryDealsTotal();
            for(int d = 0; d < deals; d++)
            {
               ulong dTicket = HistoryDealGetTicket(d);
               commission += HistoryDealGetDouble(dTicket, DEAL_COMMISSION);
            }
         }
         double netProfit = floatingPL + commission;

         if(netProfit >= InpProfitLockTrigger)
         {
            // Calculate the price at which net profit == InpProfitLockTarget
            // For BUY:  profit = (slPrice - openPrice) * volume * tickValue/tickSize + swap + commission
            //          slPrice = openPrice + (target - swap - commission) / (volume * tickValue/tickSize)
            double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
            double valuePerPriceUnit = 0.0;
            if(tickSize > 0.0 && tickValue > 0.0)
               valuePerPriceUnit = (tickValue / tickSize) * volume;

            double swapAndComm = positionInfo.Swap() + commission;

            double lockSL = 0.0;
            if(posType == POSITION_TYPE_BUY && valuePerPriceUnit > 0.0)
            {
               // profit at SL = (lockSL - openPrice) * valuePerPriceUnit + swapAndComm
               // we want profit = InpProfitLockTarget
               // lockSL = openPrice + (InpProfitLockTarget - swapAndComm) / valuePerPriceUnit
               lockSL = openPrice + (InpProfitLockTarget - swapAndComm) / valuePerPriceUnit;
               // Ensure SL is below current price and respects broker stop level
               lockSL = MathMin(lockSL, currentPrice - minStopDist);
               lockSL = NormalizeDouble(lockSL, digits);

               // Only move SL up (never loosen), and only if it's an improvement
               if(lockSL > currentSL && lockSL < currentPrice)
               {
                  if(trade.PositionModify(ticket, lockSL, currentTP))
                  {
                     profitLockApplied = true;
                     if(InpVerbose)
                        Print("[AIEA] Profit Lock — BUY #", ticket,
                              " netProfit=$", DoubleToString(netProfit, 2),
                              " swap+comm=$", DoubleToString(swapAndComm, 2),
                              " SL moved to ", DoubleToString(lockSL, digits),
                              " (target $", DoubleToString(InpProfitLockTarget, 2), ")");
                  }
                  else if(InpVerbose)
                     Print("[AIEA] Profit Lock — PositionModify failed for #", ticket,
                           " err=", GetLastError());
               }
            }
            else if(posType == POSITION_TYPE_SELL && valuePerPriceUnit > 0.0)
            {
               // For SELL: profit at SL = (openPrice - lockSL) * valuePerPriceUnit + swapAndComm
               //          lockSL = openPrice - (InpProfitLockTarget - swapAndComm) / valuePerPriceUnit
               lockSL = openPrice - (InpProfitLockTarget - swapAndComm) / valuePerPriceUnit;
               // Ensure SL is above current price and respects broker stop level
               lockSL = MathMax(lockSL, currentPrice + minStopDist);
               lockSL = NormalizeDouble(lockSL, digits);

               // Only move SL down (never loosen), and only if it's an improvement
               if((currentSL == 0.0 || lockSL < currentSL) && lockSL > currentPrice)
               {
                  if(trade.PositionModify(ticket, lockSL, currentTP))
                  {
                     profitLockApplied = true;
                     if(InpVerbose)
                        Print("[AIEA] Profit Lock — SELL #", ticket,
                              " netProfit=$", DoubleToString(netProfit, 2),
                              " swap+comm=$", DoubleToString(swapAndComm, 2),
                              " SL moved to ", DoubleToString(lockSL, digits),
                              " (target $", DoubleToString(InpProfitLockTarget, 2), ")");
                  }
                  else if(InpVerbose)
                     Print("[AIEA] Profit Lock — PositionModify failed for #", ticket,
                           " err=", GetLastError());
               }
            }
         }
      }

      // If profit lock was just applied, skip the ATR-based break-even/trailing
      // this tick — they would undo our precise $-based SL.  On subsequent ticks
      // the trailing stop can continue to tighten from the locked level.
      if(profitLockApplied)
         continue;

      // Break-even logic
      if(posType == POSITION_TYPE_BUY)
      {
         if(currentPrice - openPrice >= beTrigger && currentSL < openPrice)
         {
            double newSL = NormalizeDouble(openPrice + point * 5, digits);
            trade.PositionModify(ticket, newSL, currentTP);
         }

         // Trailing stop
         if(trailingDist > 0.0)
         {
            double newSL = currentPrice - trailingDist;
            newSL = NormalizeDouble(newSL, digits);
            if(newSL > currentSL && newSL > openPrice)
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
      else // SELL
      {
         if(openPrice - currentPrice >= beTrigger && currentSL > openPrice)
         {
            double newSL = NormalizeDouble(openPrice - point * 5, digits);
            trade.PositionModify(ticket, newSL, currentTP);
         }

         // Trailing stop
         if(trailingDist > 0.0)
         {
            double newSL = currentPrice + trailingDist;
            newSL = NormalizeDouble(newSL, digits);
            if(currentSL == 0.0 || (newSL < currentSL && newSL < openPrice))
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//--- Process a closed trade and record in journal
void ProcessClosedTrade()
{
   if(!HistorySelect(0, TimeCurrent()))
      return;

   int dealsTotal = HistoryDealsTotal();

   for(int i = dealsTotal - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

      // Only look at exit deals (DEAL_ENTRY_OUT or DEAL_ENTRY_INOUT)
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT)
         continue;

      if(dealMagic != InpMagicNumber)
         continue;

      long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      // Find this trade in our pending array
      int pendingIdx = -1;
      for(int j = 0; j < ArraySize(g_pendingTrades); j++)
      {
         // Match by position ID (approximate match by checking recent trades)
         if(g_pendingTrades[j].ticket == (int)positionId ||
            g_pendingTrades[j].openTime <= HistoryDealGetInteger(dealTicket, DEAL_TIME))
         {
            pendingIdx = j;
            break;
         }
      }

      if(pendingIdx < 0) continue;

      PendingTrade pt = g_pendingTrades[pendingIdx];

      // Build journal entry
      JournalEntry je;
      InitJournalEntry(je);

      je.ticket         = (int)positionId;
      je.symbol         = g_symbol;
      je.openTime       = pt.openTime;
      je.closeTime      = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      je.type           = pt.type;
      je.openPrice      = pt.openPrice;
      je.closePrice      = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      je.stopLoss       = pt.stopLoss;
      je.takeProfit     = pt.takeProfit;
      je.volume          = pt.volume;
      je.profit          = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                          HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                          HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      je.spreadAtEntry   = pt.spreadAtEntry;
      je.confidence      = pt.confidence;
      je.entryRationale  = pt.entryRationale;
      je.profileId       = pt.profileId;
      je.rsiAtEntry      = pt.rsiAtEntry;
      je.maFastAtEntry   = pt.maFastAtEntry;
      je.maSlowAtEntry   = pt.maSlowAtEntry;
      je.bbUpperAtEntry  = pt.bbUpperAtEntry;
      je.bbLowerAtEntry  = pt.bbLowerAtEntry;
      je.macdMainAtEntry = pt.macdMainAtEntry;
      je.macdSignalAtEntry = pt.macdSignalAtEntry;
      je.stochMainAtEntry  = pt.stochMainAtEntry;
      je.atrAtEntry      = pt.atrAtEntry;
      je.regime          = pt.regime;
      je.volatilityPercent = pt.volatilityPercent;
      je.weekday         = pt.weekday;
      je.hour            = pt.hour;
      je.session         = pt.session;

      // Determine outcome
      if(je.profit > 0.0)       je.outcome = OUTCOME_WIN;
      else if(je.profit < 0.0)  je.outcome = OUTCOME_LOSS;
      else                      je.outcome = OUTCOME_BREAKEVEN;

      // Calculate MFE and MAE
      je.mfe = CalculateMFE((int)positionId, pt.type, pt.openPrice, je.closePrice);
      je.mae = CalculateMAE((int)positionId, pt.type, pt.openPrice, je.closePrice);

      // Calculate slippage
      double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
      if(pt.type == ORDER_TYPE_BUY)
         je.slippage = MathAbs(pt.openPrice - je.openPrice) / point;
      else
         je.slippage = MathAbs(pt.openPrice - je.openPrice) / point;

      // Calculate risk:reward ratio
      double slDist = MathAbs(pt.openPrice - pt.stopLoss);
      double tpDist = MathAbs(pt.takeProfit - pt.openPrice);
      if(slDist > 0.0)
         je.riskRewardRatio = tpDist / slDist;
      else
         je.riskRewardRatio = 0.0;

      // Exit rationale
      if(je.outcome == OUTCOME_WIN)
         je.exitRationale = "Trade hit take profit or closed with profit";
      else if(je.outcome == OUTCOME_LOSS)
         je.exitRationale = "Trade hit stop loss or closed with loss";
      else
         je.exitRationale = "Trade closed at breakeven";

      // Analyze the trade with the learning engine
      if(InpEnableLearning)
      {
         ParameterSet ps;
         if(GetActiveParameters(ps))
         {
            learningEngine.AnalyzeTrade(je, ps);
         }
      }

      // Record profit in risk manager
      riskManager.RecordProfit(je.profit);

      // Write to journal
      journal.WriteEntry(je);

      Print("[AIEA] Trade closed - Ticket:", je.ticket,
            " P&L:", DoubleToString(je.profit, 2),
            " Outcome:", (je.outcome == OUTCOME_WIN ? "WIN" :
                         (je.outcome == OUTCOME_LOSS ? "LOSS" : "BE")),
            " MFE:", DoubleToString(je.mfe, 1),
            " MAE:", DoubleToString(je.mae, 1),
            " Lesson: ", je.lessonLearned);

      // Remove from pending
      RemovePendingTrade(pendingIdx);
   }
}

//--- Evaluate trading signal
int EvaluateSignal(const IndicatorSnapshot &snap, const ParameterSet &params)
{
   double buyConfidence = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_BUY);
   double sellConfidence = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_SELL);

   // Choose the direction with higher confidence
   if(buyConfidence >= params.minConfidence && buyConfidence > sellConfidence)
      return ORDER_TYPE_BUY;

   if(sellConfidence >= params.minConfidence && sellConfidence > buyConfidence)
      return ORDER_TYPE_SELL;

   return -1; // No signal
}

//--- Run periodic optimization
void RunOptimizationCycle()
{
   if(!InpEnableOptimization) return;

   datetime now = TimeCurrent();
   if(now - g_lastOptimizeTime < InpOptimizeIntervalMinutes * 60)
      return;

   g_lastOptimizeTime = now;

   // Update all profile scores
   strategyEvolution.UpdateAllProfileScores();

   // Run optimization for active profile
   int activeId = strategyEvolution.GetActiveProfileId();
   optimizationEngine.RunOptimization(activeId);

   // Check if we should promote a better profile
   int bestId = strategyEvolution.GetBestProfileId();
   if(bestId != activeId && bestId > 0)
   {
      ParameterSet activePs, bestPs;
      if(strategyEvolution.GetProfileById(activeId, activePs) &&
         strategyEvolution.GetProfileById(bestId, bestPs))
      {
         // Only promote if the best is significantly better
         if(bestPs.score > activePs.score + 15.0 && bestPs.totalTrades >= InpMinEvidenceTrades)
         {
            Print("[AIEA] Auto-promoting profile ", bestId, " (score: ",
                  DoubleToString(bestPs.score, 1), ") over ", activeId, " (score: ",
                  DoubleToString(activePs.score, 1), ")");
            strategyEvolution.PromoteProfile(bestId);
         }
      }
   }

   // Reinitialize indicators with new parameters if they changed
   ParameterSet ps;
   if(GetActiveParameters(ps))
   {
      indicatorEngine.Deinit();
      indicatorEngine.Init(g_symbol, InpTimeframe, ps);
   }

   strategyEvolution.SaveProfiles();
   optimizationEngine.SaveChanges();
}

//--- Generate periodic reports
void RunReportCycle()
{
   if(!InpEnableReports) return;

   datetime now = TimeCurrent();
   if(now - g_lastReportTime < InpReportIntervalMinutes * 60)
      return;

   g_lastReportTime = now;

   reportGenerator.GenerateDailyReport();
}

//==================================================================
//  EXPERT ADVISOR EVENT FUNCTIONS
//==================================================================

//+------------------------------------------------------------------+
//| Auto-detect a reasonable max spread for the current symbol.         |
//| Samples the live spread over ~1 second at startup, then sets      |
//| max spread = sampled average × 3 (with a minimum floor).           |
//| This avoids hardcoding spread values per symbol — BTCUSD naturally |
//| has 2000+ point spreads, XAUUSD ~20-40, EURUSD ~5-15, etc.        |
//+------------------------------------------------------------------+
double AutoDetectMaxSpread()
{
   string sym = (InpSymbol == "") ? _Symbol : InpSymbol;

   int validSamples = 0;
   long sum = 0;

   for(int i = 0; i < 10; i++)
   {
      long sp = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      if(sp > 0)
      {
         sum += sp;
         validSamples++;
      }
      Sleep(100);
   }

   if(validSamples == 0)
   {
      Print("[AIEA] AutoDetect: could not sample spread for ", sym, " — using fallback 500");
      return 500.0;
   }

   double avgSpread = (double)sum / validSamples;
   double maxSpread = avgSpread * 3.0;

   // Floor: at least 10 points so we don't set absurdly tight limits
   if(maxSpread < 10.0) maxSpread = 10.0;

   maxSpread = MathCeil(maxSpread);

   Print("[AIEA] AutoDetect spread for ", sym,
         ": avg=", (int)avgSpread, " pts (", validSamples, " samples)",
         " -> max=", (int)maxSpread, " pts (3x avg)");

   return maxSpread;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Defensive cleanup: remove any stray default-named chart objects
   // (e.g. a leftover "Label" object from manual chart edits or an old
   // debug build) that aren't part of our AIEA_/AIEA_SP_ prefixed set —
   // these can visually collide with our dashboard panels.
   if(ObjectFind(0, "Label") >= 0)
      ObjectDelete(0, "Label");

   // Determine symbol
   g_symbol = (InpSymbol == "") ? _Symbol : InpSymbol;

   // Set trade parameters
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);

   // Get active parameter set
   ParameterSet ps;
   CreateDefaultParameterSet(ps, 1);

   // Apply input overrides
   ps.positionSizePercent = InpRiskPercent;
   ps.maxDailyLossPercent = InpMaxDailyLoss;
   ps.maxDrawdownPercent = InpMaxDrawdown;
   ps.maxOpenPositions   = InpMaxPositions;

   // Initialize modules
   if(!journal.Init("AIEA_Trader"))
   {
      Print("[AIEA] Failed to initialize journal.");
      return INIT_FAILED;
   }

   if(!indicatorEngine.Init(g_symbol, InpTimeframe, ps))
   {
      Print("[AIEA] Failed to initialize indicators.");
      return INIT_FAILED;
   }

   riskManager.Init();

   learningEngine.Init(journal, InpMinEvidenceTrades);
   patternRecognition.Init(journal);
   strategyEvolution.Init(learningEngine, journal);
   optimizationEngine.Init(strategyEvolution, learningEngine, patternRecognition,
                            journal, InpMinEvidenceTrades);
   optimizationEngine.SetAutoApply(InpAutoApproveChanges);
   reportGenerator.Init(journal, learningEngine, strategyEvolution,
                         patternRecognition, optimizationEngine);

   // Load saved state
   strategyEvolution.LoadProfiles();
   optimizationEngine.LoadChanges();

   // Apply input overrides to active profile
   int activeId = strategyEvolution.GetActiveProfileId();
   strategyEvolution.SetProfileParam(activeId, "positionSizePercent", InpRiskPercent);
   strategyEvolution.SetProfileParam(activeId, "maxDailyLossPercent", InpMaxDailyLoss);
   strategyEvolution.SetProfileParam(activeId, "maxDrawdownPercent", InpMaxDrawdown);
   strategyEvolution.SetProfileParam(activeId, "maxOpenPositions", (double)InpMaxPositions);

   // Override confidence threshold if specified
   if(InpMinConfidenceOverride > 0.0)
      strategyEvolution.SetProfileParam(activeId, "minConfidence", InpMinConfidenceOverride);

   // Max spread handling:
   //   InpMaxSpreadOverride > 0  → manual override (e.g. 3000 for BTCUSD)
   //   InpMaxSpreadOverride = -1 → AUTO: sample live spread and set 3x average
   //   InpMaxSpreadOverride = 0  → use profile default (30)
   if(InpMaxSpreadOverride == -1.0)
   {
      double autoSpread = AutoDetectMaxSpread();
      strategyEvolution.SetProfileParam(activeId, "maxSpreadPoints", autoSpread);
      Print("[AIEA] Using AUTO-detected max spread: ", (int)autoSpread, " points");
   }
   else if(InpMaxSpreadOverride > 0.0)
   {
      strategyEvolution.SetProfileParam(activeId, "maxSpreadPoints", InpMaxSpreadOverride);
      Print("[AIEA] Using manual max spread override: ", (int)InpMaxSpreadOverride, " points");
   }

   // Reinitialize indicators with loaded parameters
   ParameterSet activePs;
   if(GetActiveParameters(activePs))
   {
      indicatorEngine.Deinit();
      indicatorEngine.Init(g_symbol, InpTimeframe, activePs);
   }

   // Initialize news manager
   if(InpEnableNewsFilter)
   {
      newsManager.SetWarningHours(InpNewsWarningHours);
      newsManager.SetBlockMinutes(InpNewsBlockMinutes);
      newsManager.SetProtectMinutes(InpNewsProtectMinutes);
      newsManager.SetReleaseMinutes(InpNewsReleaseMinutes);
      newsManager.SetProtectMode(InpNewsProtectTrades ? 1 : 0);
      newsManager.SetImportanceFilter(InpNewsImportance);
      newsManager.SetCountryFilter(InpNewsCountryFilter);
      Print("[AIEA] Fetching today's economic calendar (importance=", EnumToString(InpNewsImportance),
            ", countries=", InpNewsCountryFilter, ")...");
      newsManager.FetchTodaysNews();
   }

   // Create dashboard
   if(InpEnableDashboard)
   {
      dashboard.Init(journal, learningEngine, strategyEvolution, riskManager, newsManager);
      dashboard.Create();
   }

   g_lastReportTime = TimeCurrent();
   g_lastOptimizeTime = TimeCurrent();

   Print("[AIEA] Initialization complete. Symbol: ", g_symbol,
         " Profile: ", strategyEvolution.GetActiveProfileId(),
         " Magic: ", InpMagicNumber);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DestroyStatusPanel();
   Comment("");
   indicatorEngine.Deinit();

   // Save state
   strategyEvolution.SaveProfiles();
   optimizationEngine.SaveChanges();

   // Generate final report
   if(InpEnableReports)
      reportGenerator.GenerateDailyReport();

   // Destroy dashboard
   if(InpEnableDashboard)
      dashboard.Destroy();

   Print("[AIEA] Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Status Panel — chart objects for trend + waiting reason            |
//+------------------------------------------------------------------+
#define SP_PREFIX "AIEA_SP_"

void SP_CreateLabel(string name, string text, int x, int y,
                     color clr = clrWhite, int fontSize = 10)
{
   string objName = SP_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetString(0, objName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

void SP_CreateRect(string name, int x, int y, int w, int h, color bgClr)
{
   string objName = SP_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

void SP_UpdateLabel(string name, string text, color clr)
{
   string objName = SP_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
   {
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   }
}

//--- Update a two-line wrapped label pair (baseName+"1", baseName+"2").
//--- Splits fullText near maxLineLen at the nearest space so long
//--- indicator/status strings never overflow the panel's edge.
void SP_UpdateWrappedLabel(string baseName, string fullText, color clr, int maxLineLen = 46)
{
   if(StringLen(fullText) > maxLineLen)
   {
      int splitPos = maxLineLen;
      for(int i = maxLineLen; i > (int)(maxLineLen * 0.6); i--)
      {
         if(StringGetCharacter(fullText, i) == ' ')
         {
            splitPos = i;
            break;
         }
      }
      SP_UpdateLabel(baseName + "1", StringSubstr(fullText, 0, splitPos), clr);
      SP_UpdateLabel(baseName + "2", StringSubstr(fullText, splitPos), clr);
   }
   else
   {
      SP_UpdateLabel(baseName + "1", fullText, clr);
      SP_UpdateLabel(baseName + "2", "", clr);
   }
}

bool g_statusPanelCreated = false;
int  g_indicatorFailStreak = 0;

void CreateStatusPanel()
{
   if(g_statusPanelCreated) return;

   // Background panel — below the dashboard (widened + heightened to fit
   // the two-line indicators row without overflowing into the chart)
   SP_CreateRect("bg", 10, 350, 460, 236, C'20,20,30');

   // Title
   SP_CreateLabel("title", "AIEA — Market Status", 20, 360, clrGold, 12);

   // Separator
   SP_CreateLabel("sep1", "──────────────────────────────", 20, 380, clrDimGray);

   // Trend section
   SP_CreateLabel("trend_lbl", "TREND:", 20, 395, clrGray);
   SP_CreateLabel("trend_val", "Loading...", 130, 395, clrWhite, 11);

   // Confidence section
   SP_CreateLabel("conf_lbl", "CONFIDENCE:", 20, 415, clrGray);
   SP_CreateLabel("conf_val", "Buy: -- | Sell: -- | Need: --", 130, 415, clrWhite);

   // Indicators — wrapped across two lines so long strings never overflow
   SP_CreateLabel("ind_lbl", "INDICATORS:", 20, 435, clrGray);
   SP_CreateLabel("ind_val1", "Loading...", 130, 435, clrSilver, 9);
   SP_CreateLabel("ind_val2", "", 130, 450, clrSilver, 9);

   // Separator
   SP_CreateLabel("sep2", "──────────────────────────────", 20, 470, clrDimGray);

   // Waiting for section
   SP_CreateLabel("wait_lbl", "WAITING FOR:", 20, 485, clrGray, 11);
   SP_CreateLabel("wait_val1", "Initializing...", 20, 505, clrYellow);
   SP_CreateLabel("wait_val2", "", 20, 523, clrYellow);

   // Separator
   SP_CreateLabel("sep3", "──────────────────────────────", 20, 543, clrDimGray);

   // Server time / hours
   SP_CreateLabel("time_lbl", "SERVER TIME:", 20, 558, clrGray);
   SP_CreateLabel("time_val", "--:-- (hours: --)", 130, 558, clrSilver);

   g_statusPanelCreated = true;
}

void UpdateStatusPanel(const ParameterSet &ps, const IndicatorSnapshot &snap,
                        const string &trendStr, const string &waitingReason)
{
   if(!g_statusPanelCreated) CreateStatusPanel();

   // Trend with color
   color trendClr = clrSilver;
   if(StringFind(trendStr, "STRONG BULLISH") >= 0) trendClr = clrLime;
   else if(StringFind(trendStr, "BULLISH") >= 0) trendClr = clrMediumSeaGreen;
   else if(StringFind(trendStr, "STRONG BEARISH") >= 0) trendClr = clrRed;
   else if(StringFind(trendStr, "BEARISH") >= 0) trendClr = clrTomato;
   else if(StringFind(trendStr, "RANGING") >= 0) trendClr = clrGoldenrod;
   SP_UpdateLabel("trend_val", trendStr, trendClr);

   // Confidence
   double buyConf = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_BUY);
   double sellConf = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_SELL);
   double bestConf = MathMax(buyConf, sellConf);
   color confClr = (bestConf >= ps.minConfidence ? clrLime : (bestConf >= ps.minConfidence * 0.7 ? clrYellow : clrSilver));
   SP_UpdateLabel("conf_val",
      StringFormat("Buy: %.1f | Sell: %.1f | Need: %.0f", buyConf, sellConf, ps.minConfidence),
      confClr);

   // Indicators summary
   string regimeStr;
   switch(snap.regime)
   {
      case REGIME_TRENDING:  regimeStr = "Trend"; break;
      case REGIME_RANGING:   regimeStr = "Range"; break;
      case REGIME_VOLATILE:  regimeStr = "Volat"; break;
      default:               regimeStr = "?";     break;
   }
   SP_UpdateWrappedLabel("ind_val",
      StringFormat("RSI %.1f | MA %s | MACD %s | Stoch %.1f | Vol %.2f%% | %s",
         snap.rsi,
         (snap.maFast > snap.maSlow ? "↑" : "↓"),
         (snap.macdMain > snap.macdSignal ? "↑" : "↓"),
         snap.stochMain, snap.volatilityPercent, regimeStr),
      clrSilver, 40);

   // Waiting reason — split into 2 lines if long
   SP_UpdateWrappedLabel("wait_val", waitingReason, clrYellow, 50);

   // Server time + hours
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string hoursStr;
   if(InpTradeAllHours)
      hoursStr = "24h mode";
   else
      hoursStr = StringFormat("hours %d-%d", ps.tradingStartHour, ps.tradingEndHour);
   SP_UpdateLabel("time_val",
      StringFormat("%02d:%02d (%s)", dt.hour, dt.min, hoursStr),
      clrSilver);

   ChartRedraw(0);
}

void DestroyStatusPanel()
{
   if(!g_statusPanelCreated) return;
   string names[] = {"bg","title","sep1","sep2","sep3",
      "trend_lbl","trend_val","conf_lbl","conf_val",
      "ind_lbl","ind_val1","ind_val2","wait_lbl","wait_val1","wait_val2",
      "time_lbl","time_val"};
   for(int i = 0; i < ArraySize(names); i++)
   {
      string objName = SP_PREFIX + names[i];
      if(ObjectFind(0, objName) >= 0)
         ObjectDelete(0, objName);
   }
   g_statusPanelCreated = false;
}

//+------------------------------------------------------------------+
//| Determine current trend from indicator snapshot                   |
//+------------------------------------------------------------------+
string GetTrendString(const IndicatorSnapshot &snap)
{
   int bullScore = 0;
   int bearScore = 0;

   // MA direction
   if(snap.maFast > snap.maSlow) bullScore++;
   else bearScore++;

   // MACD direction
   if(snap.macdMain > snap.macdSignal && snap.macdHist > 0) bullScore++;
   else if(snap.macdMain < snap.macdSignal && snap.macdHist < 0) bearScore++;

   // RSI direction
   if(snap.rsi > 50.0) bullScore++;
   else if(snap.rsi < 50.0) bearScore++;

   // Price vs BB middle
   if(snap.closePrice > snap.bbMiddle) bullScore++;
   else if(snap.closePrice < snap.bbMiddle) bearScore++;

   // Price vs prev close
   if(snap.closePrice > snap.prevClose) bullScore++;
   else if(snap.closePrice < snap.prevClose) bearScore++;

   if(bullScore >= 4) return "STRONG BULLISH";
   if(bullScore == 3) return "BULLISH";
   if(bearScore >= 4) return "STRONG BEARISH";
   if(bearScore == 3) return "BEARISH";
   return "RANGING / NEUTRAL";
}

//+------------------------------------------------------------------+
//| Determine what the EA is waiting for before opening a trade        |
//+------------------------------------------------------------------+
string GetWaitingReason(const ParameterSet &ps, const IndicatorSnapshot &snap)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool inHours = InpTradeAllHours || (dt.hour >= ps.tradingStartHour && dt.hour < ps.tradingEndHour);

   // Check each blocker in order of priority
   if(riskManager.IsHalted())
      return "Risk halt: " + riskManager.GetHaltReason();

   if(!inHours)
      return StringFormat("Trading hours (waiting for %d:00, server hour %d:00)",
                           ps.tradingStartHour, dt.hour);

   int positions = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(positionInfo.SelectByTicket(ticket) && positionInfo.Magic() == InpMagicNumber)
         positions++;
   }
   if(positions >= ps.maxOpenPositions)
      return StringFormat("Max positions open (%d/%d) — waiting for a close",
                           positions, ps.maxOpenPositions);

   long spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   if((double)spread > ps.maxSpreadPoints)
      return StringFormat("Spread too wide (current %d, max %d) — waiting for tighter spread",
                           (int)spread, (int)ps.maxSpreadPoints);

   if(ps.volatilityFilter && snap.volatilityPercent > 3.0)
      return StringFormat("Volatility too high (%.2f%%, max 3.0%%) — waiting to settle",
                           snap.volatilityPercent);

   // Confidence gap analysis
   double buyConf = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_BUY);
   double sellConf = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_SELL);
   double bestConf = MathMax(buyConf, sellConf);
   string bestDir = (buyConf > sellConf) ? "BUY" : "SELL";

   if(bestConf < ps.minConfidence)
   {
      // Build breakdown of what's needed
      string breakdown = "";
      if(bestDir == "BUY")
      {
         if(snap.rsi >= 50.0 && snap.rsi > 30.0)
            breakdown += StringFormat("RSI=%.1f (need <30 for strong buy) ", snap.rsi);
         if(snap.maFast <= snap.maSlow)
            breakdown += "MA bearish (need fast>slow) ";
         if(snap.macdMain <= snap.macdSignal)
            breakdown += "MACD bearish (need main>signal) ";
         if(snap.stochMain >= 20.0)
            breakdown += StringFormat("Stoch=%.1f (need <20) ", snap.stochMain);
         if(snap.closePrice > snap.bbLower)
            breakdown += "Price above BB lower ";
      }
      else
      {
         if(snap.rsi <= 50.0 && snap.rsi < 70.0)
            breakdown += StringFormat("RSI=%.1f (need >70 for strong sell) ", snap.rsi);
         if(snap.maFast >= snap.maSlow)
            breakdown += "MA bullish (need fast<slow) ";
         if(snap.macdMain >= snap.macdSignal)
            breakdown += "MACD bullish (need main<signal) ";
         if(snap.stochMain <= 80.0)
            breakdown += StringFormat("Stoch=%.1f (need >80) ", snap.stochMain);
         if(snap.closePrice < snap.bbUpper)
            breakdown += "Price below BB upper ";
      }

      if(breakdown == "")
         breakdown = "Indicators partially aligned but confidence too low";

      return StringFormat("Confidence gap: %s at %.1f (need %.1f) — %s",
                           bestDir, bestConf, ps.minConfidence, breakdown);
   }

   return "Signal ready — waiting for new bar to execute";
}

//+------------------------------------------------------------------+
//| Print heartbeat status — periodic diagnostic output                |
//+------------------------------------------------------------------+
void PrintHeartbeat()
{
   ParameterSet ps;
   if(!GetActiveParameters(ps))
   {
      CreateDefaultParameterSet(ps, 1);
      ps.minConfidence = 45.0;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   int positions = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(positionInfo.SelectByTicket(ticket) && positionInfo.Magic() == InpMagicNumber)
         positions++;
   }

   long spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   string status = riskManager.IsHalted() ? "HALTED" : "ACTIVE";
   string haltReason = riskManager.IsHalted() ? riskManager.GetHaltReason() : "";

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool inHours = (dt.hour >= ps.tradingStartHour && dt.hour < ps.tradingEndHour);

   // Get indicator snapshot for trend analysis
   IndicatorSnapshot snap;
   bool hasSnapshot = indicatorEngine.GetSnapshot(snap);

   string trendStr = "Indicators loading...";
   string waitingReason = "Initializing...";
   string indicatorSummary = "";
   double buyConf = 0.0, sellConf = 0.0;

   if(hasSnapshot)
   {
      g_indicatorFailStreak = 0;
      trendStr = GetTrendString(snap);
      waitingReason = GetWaitingReason(ps, snap);
      buyConf = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_BUY);
      sellConf = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_SELL);

      string regimeStr;
      switch(snap.regime)
      {
         case REGIME_TRENDING:  regimeStr = "Trending";  break;
         case REGIME_RANGING:   regimeStr = "Ranging";   break;
         case REGIME_VOLATILE:  regimeStr = "Volatile";  break;
         default:               regimeStr = "Unknown";   break;
      }

      indicatorSummary = StringFormat(
         "RSI: %.1f | MA: %.5f/%.5f (%s) | MACD: %.5f/%.5f | Stoch: %.1f | ATR: %.5f | Vol: %.2f%% | Regime: %s",
         snap.rsi, snap.maFast, snap.maSlow,
         (snap.maFast > snap.maSlow ? "BULL" : "BEAR"),
         snap.macdMain, snap.macdSignal,
         snap.stochMain, snap.atr, snap.volatilityPercent, regimeStr);
   }
   else
   {
      g_indicatorFailStreak++;
      waitingReason = StringFormat("%s [check #%d]", indicatorEngine.GetLastFailReason(), g_indicatorFailStreak);

      // Only attempt recovery if history genuinely isn't ready yet — once bars/sync look fine,
      // repeatedly tearing down and rebuilding handles does more harm than good (MT5 shares
      // handles internally by symbol/timeframe/params, so re-init churn can itself cause
      // "wrong handle" errors). Cap retries and back off.
      if(!indicatorEngine.IsHistoryReady())
      {
         if(g_indicatorFailStreak > 0 && g_indicatorFailStreak % 10 == 0 && g_indicatorFailStreak <= 100)
         {
            Print("[AIEA] History still not ready after ", g_indicatorFailStreak,
                  " checks — attempting to re-initialize indicator handles...");
            indicatorEngine.Deinit();
            if(indicatorEngine.Init(g_symbol, InpTimeframe, ps))
               Print("[AIEA] Indicator handles re-created. Waiting for history/buffers to fill...");
            else
               Print("[AIEA] Re-init FAILED — check symbol '", g_symbol, "' and timeframe are valid and in Market Watch.");
         }
      }
      else if(g_indicatorFailStreak == 1 || g_indicatorFailStreak % 5 == 0)
      {
         // History is fine but a buffer call still failed — this is the real "wrong handle"
         // scenario (handle got invalidated). Re-init right away, and keep retrying every
         // few checks in case the first attempt doesn't take.
         Print("[AIEA] History is ready but an indicator buffer failed (handle likely invalidated, streak=",
               g_indicatorFailStreak, ") — re-initializing...");
         indicatorEngine.Deinit();
         if(indicatorEngine.Init(g_symbol, InpTimeframe, ps))
            Print("[AIEA] Indicator handles re-created successfully.");
         else
            Print("[AIEA] Re-init FAILED — check symbol '", g_symbol, "' and timeframe are valid and in Market Watch.");
      }
   }

   // News warning
   if(InpEnableNewsFilter)
   {
      string newsWarn = newsManager.GetWarningMessage();
      if(newsWarn != "")
      {
         Print("[AIEA] NEWS ALERT: ", newsWarn);
         waitingReason = "NEWS: " + newsWarn;
      }
      if(newsManager.IsInNewsBlackout())
      {
         if(waitingReason == "" || StringFind(waitingReason, "NEWS") < 0)
            waitingReason = "High-impact news blackout window — trading paused";
      }
      if(newsManager.IsProtecting())
      {
         string protStatus = newsManager.GetProtectionStatus();
         Print("[AIEA] ", protStatus);
         if(waitingReason == "")
            waitingReason = protStatus;
      }
   }

   // Print to Experts log
   Print("[AIEA] ═══ Heartbeat ═══");
   Print("[AIEA] Trend: ", trendStr);
   Print("[AIEA] Confidence — Buy: ", DoubleToString(buyConf, 1),
         " | Sell: ", DoubleToString(sellConf, 1),
         " | Threshold: ", DoubleToString(ps.minConfidence, 1));
   if(hasSnapshot)
      Print("[AIEA] Indicators — ", indicatorSummary);
   Print("[AIEA] Waiting for: ", waitingReason);
   string plStatus = InpEnableProfitLock
      ? StringFormat("ProfitLock: ON (trigger $%.1f -> lock $%.1f)",
                     InpProfitLockTrigger, InpProfitLockTarget)
      : "ProfitLock: OFF";

   Print("[AIEA] Status: ", status,
         (haltReason != "" ? " (" + haltReason + ")" : ""),
         " | Equity: ", DoubleToString(equity, 2),
         " | Pos: ", positions, "/", ps.maxOpenPositions,
         " | Spread: ", spread, "/", (int)ps.maxSpreadPoints,
         " | Hour: ", dt.hour, " (", (inHours ? "IN" : "OUT"), ")",
         " | Profile: #", ps.id, " (", ps.name, ")",
         " | ", plStatus);

   // Update chart status panel
   if(hasSnapshot)
   {
      UpdateStatusPanel(ps, snap, trendStr, waitingReason);
   }
   else
   {
      // Indicators not ready — show the REAL reason, not a generic message
      CreateStatusPanel();
      SP_UpdateLabel("trend_val", "Not ready", clrOrange);
      SP_UpdateLabel("conf_val", "Buy: -- | Sell: -- | Need: --", clrSilver);
      SP_UpdateWrappedLabel("ind_val", StringFormat("Bars available: %d | Synced: %s",
                        Bars(g_symbol, InpTimeframe),
                        (SeriesInfoInteger(g_symbol, InpTimeframe, SERIES_SYNCHRONIZED) ? "yes" : "NO")),
                    clrSilver, 40);

      string reason = waitingReason; // set above from indicatorEngine.GetLastFailReason()
      SP_UpdateWrappedLabel("wait_val", reason, clrYellow, 50);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Enhanced signal evaluation with confidence breakdown               |
//+------------------------------------------------------------------+
int EvaluateSignalVerbose(const IndicatorSnapshot &snap, const ParameterSet &params,
                           string &signalDetail)
{
   double buyConfidence = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_BUY);
   double sellConfidence = indicatorEngine.CalculateConfidence(snap, ORDER_TYPE_SELL);

   // Build detail string showing indicator values
   string regimeStr;
   switch(snap.regime)
   {
      case REGIME_TRENDING:  regimeStr = "Trending";  break;
      case REGIME_RANGING:   regimeStr = "Ranging";   break;
      case REGIME_VOLATILE:  regimeStr = "Volatile";  break;
      default:               regimeStr = "Unknown";   break;
   }

   signalDetail = StringFormat(
      "RSI=%.1f | MA Fast=%.5f Slow=%.5f (%s) | MACD Main=%.5f Signal=%.5f | "
      "Stoch=%.1f | BB Upper=%.5f Lower=%.5f Close=%.5f | ATR=%.5f | "
      "Regime=%s | Vol%%=%.2f",
      snap.rsi, snap.maFast, snap.maSlow,
      (snap.maFast > snap.maSlow ? "BULL" : "BEAR"),
      snap.macdMain, snap.macdSignal,
      snap.stochMain, snap.bbUpper, snap.bbLower, snap.closePrice,
      snap.atr, regimeStr, snap.volatilityPercent);

   if(InpVerbose)
   {
      Print("[AIEA] Indicators — ", signalDetail);
      Print("[AIEA] Confidence — Buy: ", DoubleToString(buyConfidence, 1),
            " | Sell: ", DoubleToString(sellConfidence, 1),
            " | Threshold: ", DoubleToString(params.minConfidence, 1));
   }

   // Choose the direction with higher confidence
   if(buyConfidence >= params.minConfidence && buyConfidence > sellConfidence)
   {
      if(InpVerbose)
         Print("[AIEA] SIGNAL: BUY (confidence ", DoubleToString(buyConfidence, 1), ")");
      return ORDER_TYPE_BUY;
   }

   if(sellConfidence >= params.minConfidence && sellConfidence > buyConfidence)
   {
      if(InpVerbose)
         Print("[AIEA] SIGNAL: SELL (confidence ", DoubleToString(sellConfidence, 1), ")");
      return ORDER_TYPE_SELL;
   }

   if(InpVerbose)
   {
      double maxConf = MathMax(buyConfidence, sellConfidence);
      double gap = params.minConfidence - maxConf;
      Print("[AIEA] NO SIGNAL — best confidence ", DoubleToString(maxConf, 1),
            " is ", DoubleToString(gap, 1), " below threshold ",
            DoubleToString(params.minConfidence, 1));
   }

   return -1; // No signal
}

//+------------------------------------------------------------------+
//| Expert tick function — main trading loop                          |
//+------------------------------------------------------------------+
void OnTick()
{
   // Process closed trades first (learning happens on every close)
   ProcessClosedTrade();

   // Update dashboard
   if(InpEnableDashboard)
      dashboard.Update();

   // Manage open positions on every tick
   ParameterSet ps;
   if(GetActiveParameters(ps))
   {
      ManageOpenPositions(ps);
   }

   // News trade protection — check every tick
   if(InpEnableNewsFilter && InpNewsProtectTrades)
   {
      newsManager.CheckNewsProtection(g_symbol, InpMagicNumber, InpVerbose);
   }

   // Periodic heartbeat — shows EA is alive and what it's doing
   static datetime lastHeartbeat = 0;
   if(TimeCurrent() - lastHeartbeat >= InpHeartbeatSeconds)
   {
      lastHeartbeat = TimeCurrent();
      PrintHeartbeat();
   }

   // Periodic news calendar refresh
   static datetime lastNewsRefresh = 0;
   if(InpEnableNewsFilter && TimeCurrent() - lastNewsRefresh >= InpNewsRefreshMinutes * 60)
   {
      lastNewsRefresh = TimeCurrent();
      newsManager.FetchTodaysNews();
   }

   // Only evaluate new entries on new bar
   if(!IsNewBar())
   {
      RunReportCycle();
      return;
   }

   // === NEW BAR — EVALUATING SIGNAL ===
   if(InpVerbose)
      Print("[AIEA] ─── New bar — evaluating signal ───");

   // Check risk manager
   if(riskManager.IsHalted())
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Risk manager HALTED — ", riskManager.GetHaltReason());

      // Check if we can resume (equity recovered)
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double startEquity = riskManager.GetStartOfDayEquity();
      if(startEquity > 0 && equity > startEquity)
      {
         riskManager.ResumeTrading();
         Print("[AIEA] Trading resumed — equity recovered above start-of-day");
      }
      else
      {
         return;
      }
   }

   // Get active parameters
   if(!GetActiveParameters(ps))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: No active profile found");
      return;
   }

   // Check trading hours
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   if(!InpTradeAllHours && !indicatorEngine.IsWithinTradingHours(currentTime.hour,
       ps.tradingStartHour, ps.tradingEndHour))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Outside trading hours — server hour=", currentTime.hour,
               ", allowed=", ps.tradingStartHour, "-", ps.tradingEndHour);
      return;
   }

   // Check if we can open new positions
   if(!riskManager.CanOpenPosition(ps))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Max positions reached (", (PositionsTotal()),
               "/", ps.maxOpenPositions, ")");
      return;
   }

   // Get indicator snapshot
   IndicatorSnapshot snap;
   if(!indicatorEngine.GetSnapshot(snap))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Failed to get indicator snapshot (indicators not ready?)");
      return;
   }

   // Check spread
   long currentSpread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   if(!IsSpreadAcceptable(ps))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Spread too wide — current=", currentSpread,
               " points, max=", (int)ps.maxSpreadPoints, " points");
      return;
   }

   // Check volatility
   if(!IsVolatilityAcceptable(ps, snap.volatilityPercent))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Volatility too high — current=",
               DoubleToString(snap.volatilityPercent, 2), "%, max=3.0%");
      return;
   }

   // Evaluate signal with verbose output
   string signalDetail = "";
   int signal = EvaluateSignalVerbose(snap, ps, signalDetail);
   if(signal < 0)
      return;

   // Open trade
   OpenTrade(signal, snap, ps);

   // Run periodic optimization
   RunOptimizationCycle();

   // Run periodic reporting
   RunReportCycle();
}

//+------------------------------------------------------------------+
//| Trade transaction event — for tracking closed positions           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Process closed trades when a position closes
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ProcessClosedTrade();
   }
}

//+------------------------------------------------------------------+
//| Chart event handler — for dashboard interaction                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   // Handle dashboard clicks or other events
   if(id == CHARTEVENT_CUSTOM + 1)
   {
      // Generate report on demand
      reportGenerator.GenerateDailyReport();
   }
}

//+------------------------------------------------------------------+
//| Timer function — periodic tasks                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpEnableDashboard)
      dashboard.Update();
}

//+------------------------------------------------------------------+
//| Tester function — for backtesting                                 |
//+------------------------------------------------------------------+
double OnTester()
{
   // Return a custom optimization criterion
   int activeId = strategyEvolution.GetActiveProfileId();
   double pf = learningEngine.GetProfitFactor(activeId);
   double winRate = learningEngine.GetWinRate(activeId);
   int tradeCount = learningEngine.GetTradeCount(activeId);

   if(tradeCount < 10)
      return 0.0;

   // Custom criterion: profit factor * sqrt(trade count) * (winRate/100)
   double criterion = pf * MathSqrt((double)tradeCount) * (winRate / 100.0);

   return criterion;
}

//+------------------------------------------------------------------+
//| Tester init function                                              |
//+------------------------------------------------------------------+
int OnTesterInit()
{
   Print("[AIEA] Tester initialized.");
   return 0;
}

//+------------------------------------------------------------------+
//| Tester deinit function                                            |
//+------------------------------------------------------------------+
void OnTesterDeinit()
{
   Print("[AIEA] Tester deinitialized.");
}

//+------------------------------------------------------------------+
//| Tester tick function — for backtesting with custom logic          |
//+------------------------------------------------------------------+
void OnTesterTick()
{
   // The main OnTick handles everything
}

//+------------------------------------------------------------------+
