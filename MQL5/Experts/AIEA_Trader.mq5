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

input group "=== Diagnostics ==="
input bool   InpVerbose           = true;           // Verbose logging to Experts tab
input int    InpHeartbeatSeconds  = 30;             // Heartbeat interval (seconds)
input double InpMinConfidenceOverride = 0.0;        // Override min confidence (0=use profile)

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

//--- Manage open positions (trailing stop, break-even)
void ManageOpenPositions(const ParameterSet &params)
{
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double atr = 0.0;

   // Get current ATR for trailing
   double atrBuf[1];
   int atrHandle = iATR(g_symbol, InpTimeframe, params.atrPeriod);
   if(atrHandle != INVALID_HANDLE)
   {
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
         atr = atrBuf[0];
      IndicatorRelease(atrHandle);
   }

   if(atr <= 0.0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!positionInfo.SelectByTicket(ticket))
         continue;

      if(positionInfo.Magic() != InpMagicNumber)
         continue;

      if(positionInfo.Symbol() != g_symbol)
         continue;

      double openPrice = positionInfo.PriceOpen();
      double currentSL = positionInfo.StopLoss();
      double currentTP = positionInfo.TakeProfit();
      long   posType = positionInfo.PositionType();
      double currentPrice = (posType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(g_symbol, SYMBOL_BID) :
                            SymbolInfoDouble(g_symbol, SYMBOL_ASK);

      double trailingDist = atr * params.trailingStop;
      double beTrigger = atr * params.breakEvenTrigger;

      // Break-even logic
      if(posType == POSITION_TYPE_BUY)
      {
         if(currentPrice - openPrice >= beTrigger && currentSL < openPrice)
         {
            double newSL = NormalizeDouble(openPrice + point * 5, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS));
            trade.PositionModify(ticket, newSL, currentTP);
         }

         // Trailing stop
         if(trailingDist > 0.0)
         {
            double newSL = currentPrice - trailingDist;
            newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS));
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
            double newSL = NormalizeDouble(openPrice - point * 5, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS));
            trade.PositionModify(ticket, newSL, currentTP);
         }

         // Trailing stop
         if(trailingDist > 0.0)
         {
            double newSL = currentPrice + trailingDist;
            newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS));
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
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
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

   // Reinitialize indicators with loaded parameters
   ParameterSet activePs;
   if(GetActiveParameters(activePs))
   {
      indicatorEngine.Deinit();
      indicatorEngine.Init(g_symbol, InpTimeframe, activePs);
   }

   // Create dashboard
   if(InpEnableDashboard)
   {
      dashboard.Init(journal, learningEngine, strategyEvolution, riskManager);
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

   Print("[AIEA] Heartbeat — ", status,
         (haltReason != "" ? " (" + haltReason + ")" : ""),
         " | Equity: ", DoubleToString(equity, 2),
         " | Positions: ", positions, "/", ps.maxOpenPositions,
         " | Spread: ", spread, "/", (int)ps.maxSpreadPoints,
         " | Hour: ", dt.hour, " (", (inHours ? "IN HOURS" : "OUTSIDE HOURS"), ")",
         " | Profile: #", ps.id, " (", ps.name, ")",
         " | MinConf: ", DoubleToString(ps.minConfidence, 0),
         " | Symbol: ", g_symbol,
         " | TF: ", EnumToString(InpTimeframe));

   // Show status on chart
   Comment(StringFormat(
      "AIEA Trader v1.000\n"
      "Status: %s%s\n"
      "Equity: %.2f | Balance: %.2f\n"
      "Positions: %d/%d | Spread: %d/%d\n"
      "Hour: %d (%s) | Profile: #%d (%s)\n"
      "MinConfidence: %.0f | Symbol: %s | TF: %s\n"
      "──────────────────────────\n"
      "Waiting for new bar on %s...",
      status, (haltReason != "" ? " — " + haltReason : ""),
      equity, balance,
      positions, ps.maxOpenPositions, spread, (int)ps.maxSpreadPoints,
      dt.hour, (inHours ? "IN HOURS" : "OUTSIDE HOURS"),
      ps.id, ps.name,
      ps.minConfidence, g_symbol, EnumToString(InpTimeframe),
      EnumToString(InpTimeframe)));
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

   // Periodic heartbeat — shows EA is alive and what it's doing
   static datetime lastHeartbeat = 0;
   if(TimeCurrent() - lastHeartbeat >= InpHeartbeatSeconds)
   {
      lastHeartbeat = TimeCurrent();
      PrintHeartbeat();
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
   if(!indicatorEngine.IsWithinTradingHours(currentTime.hour,
       ps.tradingStartHour, ps.tradingEndHour))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Outside trading hours — current=", currentTime.hour,
               ", allowed=", ps.tradingStartHour, "-", ps.tradingEndHour);
      return;
   }

   // Check if we can open new positions
   if(!riskManager.CanOpenPosition(ps))
   {
      if(InpVerbose)
         Print("[AIEA] SKIP: Max positions reached (", riskManager.GetOpenPositions(),
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
