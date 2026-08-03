//+------------------------------------------------------------------+
//| IndicatorEngine.mqh — Technical Indicator Management              |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_INDICATOR_ENGINE_MQH
#define AIEA_INDICATOR_ENGINE_MQH

#include "Config.mqh"
#include <Trade\Trade.mqh>

//==================================================================
//  Indicator snapshot — all indicator values at a point in time
//==================================================================

struct IndicatorSnapshot
{
   double   rsi;
   double   rsiPrev;
   double   maFast;
   double   maSlow;
   double   bbUpper;
   double   bbMiddle;
   double   bbLower;
   double   macdMain;
   double   macdSignal;
   double   macdHist;
   double   stochMain;
   double   stochSignal;
   double   atr;
   double   closePrice;
   double   openPrice;
   double   highPrice;
   double   lowPrice;
   double   prevClose;
   ENUM_MARKET_REGIME regime;
   double   volatilityPercent;
};

void InitIndicatorSnapshot(IndicatorSnapshot &snap)
{
   snap.rsi              = 0.0;
   snap.rsiPrev          = 0.0;
   snap.maFast           = 0.0;
   snap.maSlow           = 0.0;
   snap.bbUpper          = 0.0;
   snap.bbMiddle         = 0.0;
   snap.bbLower          = 0.0;
   snap.macdMain         = 0.0;
   snap.macdSignal       = 0.0;
   snap.macdHist         = 0.0;
   snap.stochMain        = 0.0;
   snap.stochSignal      = 0.0;
   snap.atr               = 0.0;
   snap.closePrice       = 0.0;
   snap.openPrice       = 0.0;
   snap.highPrice       = 0.0;
   snap.lowPrice        = 0.0;
   snap.prevClose       = 0.0;
   snap.regime           = REGIME_UNKNOWN;
   snap.volatilityPercent = 0.0;
}

//==================================================================
//  INDICATOR ENGINE CLASS
//==================================================================

class CIndicatorEngine
{
private:
   int      m_rsiHandle;
   int      m_maFastHandle;
   int      m_maSlowHandle;
   int      m_bbHandle;
   int      m_macdHandle;
   int      m_stochHandle;
   int      m_atrHandle;
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   string   m_lastFailReason;

public:
   CIndicatorEngine();
   ~CIndicatorEngine();

   bool   Init(const string symbol, ENUM_TIMEFRAMES timeframe, const ParameterSet &params);
   void   Deinit();
   bool   GetSnapshot(IndicatorSnapshot &snap);
   ENUM_MARKET_REGIME DetectRegime(double atrValue, double closePrice,
                                   double maFast, double maSlow,
                                   double bbUpper, double bbLower);
   double CalculateConfidence(const IndicatorSnapshot &snap, int orderType);
   string GetSessionName(int hour);
   bool   IsWithinTradingHours(int currentHour, int startHour, int endHour);
   string GetLastFailReason() { return m_lastFailReason; }
   bool   IsHistoryReady();
};

//--- Constructor
CIndicatorEngine::CIndicatorEngine()
{
   m_rsiHandle    = INVALID_HANDLE;
   m_maFastHandle  = INVALID_HANDLE;
   m_maSlowHandle  = INVALID_HANDLE;
   m_bbHandle      = INVALID_HANDLE;
   m_macdHandle    = INVALID_HANDLE;
   m_stochHandle   = INVALID_HANDLE;
   m_atrHandle     = INVALID_HANDLE;
   m_symbol        = "";
   m_timeframe     = PERIOD_H1;
}

//--- Destructor
CIndicatorEngine::~CIndicatorEngine()
{
   Deinit();
}

//--- Initialize all indicator handles
bool CIndicatorEngine::Init(const string symbol, ENUM_TIMEFRAMES timeframe,
                             const ParameterSet &params)
{
   m_symbol    = symbol;
   m_timeframe = timeframe;

   m_rsiHandle = iRSI(symbol, timeframe, params.rsiPeriod, PRICE_CLOSE);
   m_maFastHandle = iMA(symbol, timeframe, params.maFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_maSlowHandle = iMA(symbol, timeframe, params.maSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_bbHandle = iBands(symbol, timeframe, params.bbPeriod, 0, params.bbDeviation, PRICE_CLOSE);
   m_macdHandle = iMACD(symbol, timeframe, params.macdFast, params.macdSlow, params.macdSignal, PRICE_CLOSE);
   m_stochHandle = iStochastic(symbol, timeframe, params.stochK, params.stochD,
                               params.stochSlow, MODE_SMA, STO_LOWHIGH);
   m_atrHandle = iATR(symbol, timeframe, params.atrPeriod);

   if(m_rsiHandle == INVALID_HANDLE || m_maFastHandle == INVALID_HANDLE ||
      m_maSlowHandle == INVALID_HANDLE || m_bbHandle == INVALID_HANDLE ||
      m_macdHandle == INVALID_HANDLE || m_stochHandle == INVALID_HANDLE ||
      m_atrHandle == INVALID_HANDLE)
      return false;

   return true;
}

//--- Release indicator handles
void CIndicatorEngine::Deinit()
{
   if(m_rsiHandle != INVALID_HANDLE)    IndicatorRelease(m_rsiHandle);
   if(m_maFastHandle != INVALID_HANDLE) IndicatorRelease(m_maFastHandle);
   if(m_maSlowHandle != INVALID_HANDLE) IndicatorRelease(m_maSlowHandle);
   if(m_bbHandle != INVALID_HANDLE)    IndicatorRelease(m_bbHandle);
   if(m_macdHandle != INVALID_HANDLE)   IndicatorRelease(m_macdHandle);
   if(m_stochHandle != INVALID_HANDLE)  IndicatorRelease(m_stochHandle);
   if(m_atrHandle != INVALID_HANDLE)    IndicatorRelease(m_atrHandle);

   m_rsiHandle = m_maFastHandle = m_maSlowHandle = INVALID_HANDLE;
   m_bbHandle = m_macdHandle = m_stochHandle = m_atrHandle = INVALID_HANDLE;
}

//--- Get a complete indicator snapshot
bool CIndicatorEngine::IsHistoryReady()
{
   // Check if the terminal has finished syncing historical data for this symbol/timeframe
   bool synced = (bool)SeriesInfoInteger(m_symbol, m_timeframe, SERIES_SYNCHRONIZED);
   int  bars   = Bars(m_symbol, m_timeframe);
   return synced && bars >= 50;
}

bool CIndicatorEngine::GetSnapshot(IndicatorSnapshot &snap)
{
   InitIndicatorSnapshot(snap);
   m_lastFailReason = "";

   double rsiBuf[2], maFastBuf[2], maSlowBuf[2];
   double bbUpper[2], bbLower[2], bbMiddle[2];
   double macdMain[2], macdSignal[2];
   double stochMain[2], stochSignal[2];
   double atrBuf[1];

   // Diagnostic pre-check: is history even synced for this symbol/timeframe?
   int availableBars = Bars(m_symbol, m_timeframe);
   bool synced = (bool)SeriesInfoInteger(m_symbol, m_timeframe, SERIES_SYNCHRONIZED);
   if(!synced || availableBars < 5)
   {
      m_lastFailReason = StringFormat(
         "History not ready for %s %s — synced=%s, bars=%d (need history download)",
         m_symbol, EnumToString(m_timeframe), (synced ? "yes" : "NO"), availableBars);
      return false;
   }

   int copied;
   copied = CopyBuffer(m_rsiHandle, 0, 0, 2, rsiBuf);
   if(copied < 2) { m_lastFailReason = StringFormat("RSI buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_maFastHandle, 0, 0, 2, maFastBuf);
   if(copied < 2) { m_lastFailReason = StringFormat("MA Fast buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_maSlowHandle, 0, 0, 2, maSlowBuf);
   if(copied < 2) { m_lastFailReason = StringFormat("MA Slow buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_bbHandle, 1, 0, 2, bbUpper);
   if(copied < 2) { m_lastFailReason = StringFormat("Bollinger Upper buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_bbHandle, 2, 0, 2, bbLower);
   if(copied < 2) { m_lastFailReason = StringFormat("Bollinger Lower buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_bbHandle, 0, 0, 2, bbMiddle);
   if(copied < 2) { m_lastFailReason = StringFormat("Bollinger Middle buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_macdHandle, 0, 0, 2, macdMain);
   if(copied < 2) { m_lastFailReason = StringFormat("MACD Main buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_macdHandle, 1, 0, 2, macdSignal);
   if(copied < 2) { m_lastFailReason = StringFormat("MACD Signal buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_stochHandle, 0, 0, 2, stochMain);
   if(copied < 2) { m_lastFailReason = StringFormat("Stochastic Main buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_stochHandle, 1, 0, 2, stochSignal);
   if(copied < 2) { m_lastFailReason = StringFormat("Stochastic Signal buffer not ready (got %d/2 bars, err=%d)", copied, GetLastError()); return false; }

   copied = CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf);
   if(copied < 1) { m_lastFailReason = StringFormat("ATR buffer not ready (got %d/1 bars, err=%d)", copied, GetLastError()); return false; }

   MqlRates rates[3];
   int ratesCopied = CopyRates(m_symbol, m_timeframe, 0, 3, rates);
   if(ratesCopied < 3)
   {
      m_lastFailReason = StringFormat("Price history not ready (got %d/3 bars, err=%d)", ratesCopied, GetLastError());
      return false;
   }

   // CopyBuffer returns arrays in reverse chronological order (index 0 = oldest)
   snap.rsi         = rsiBuf[1];
   snap.rsiPrev     = rsiBuf[0];
   snap.maFast      = maFastBuf[1];
   snap.maSlow      = maSlowBuf[1];
   snap.bbUpper     = bbUpper[1];
   snap.bbLower     = bbLower[1];
   snap.bbMiddle    = bbMiddle[1];
   snap.macdMain    = macdMain[1];
   snap.macdSignal  = macdSignal[1];
   snap.macdHist    = macdMain[1] - macdSignal[1];
   snap.stochMain   = stochMain[1];
   snap.stochSignal = stochSignal[1];
   snap.atr         = atrBuf[0];

   // Rates array: index 0 = oldest, 2 = newest
   snap.closePrice  = rates[2].close;
   snap.openPrice   = rates[2].open;
   snap.highPrice   = rates[2].high;
   snap.lowPrice    = rates[2].low;
   snap.prevClose   = rates[1].close;

   // Volatility as % of price
   if(snap.closePrice > 0.0)
      snap.volatilityPercent = (snap.atr / snap.closePrice) * 100.0;
   else
      snap.volatilityPercent = 0.0;

   // Detect market regime
   snap.regime = DetectRegime(snap.atr, snap.closePrice, snap.maFast, snap.maSlow,
                               snap.bbUpper, snap.bbLower);

   return true;
}

//--- Detect market regime: trending, ranging, or volatile
ENUM_MARKET_REGIME CIndicatorEngine::DetectRegime(double atrValue, double closePrice,
                                                   double maFast, double maSlow,
                                                   double bbUpper, double bbLower)
{
   if(closePrice <= 0.0 || bbLower >= bbUpper)
      return REGIME_UNKNOWN;

   double bbWidth = (bbUpper - bbLower) / closePrice * 100.0;
   double maDiff  = MathAbs(maFast - maSlow) / closePrice * 100.0;
   double volPct  = (atrValue / closePrice) * 100.0;

   // Highly volatile if ATR% > 1.5% and BB width > 3%
   if(volPct > 1.5 && bbWidth > 3.0)
      return REGIME_VOLATILE;

   // Trending if MA separation is significant
   if(maDiff > 0.15)
      return REGIME_TRENDING;

   // Ranging if MAs are close and BB width is moderate
   if(maDiff <= 0.15 && bbWidth <= 3.0)
      return REGIME_RANGING;

   return REGIME_UNKNOWN;
}

//--- Calculate entry confidence score (0-100)
double CIndicatorEngine::CalculateConfidence(const IndicatorSnapshot &snap, int orderType)
{
   double confidence = 0.0;
   int    agreements = 0;
   int    totalChecks = 0;

   // RSI check
   totalChecks++;
   if(orderType == ORDER_TYPE_BUY)
   {
      if(snap.rsi < 30.0) { confidence += 20.0; agreements++; }
      else if(snap.rsi < 50.0) { confidence += 10.0; agreements++; }
      else if(snap.rsi > 70.0) { confidence -= 10.0; }
   }
   else
   {
      if(snap.rsi > 70.0) { confidence += 20.0; agreements++; }
      else if(snap.rsi > 50.0) { confidence += 10.0; agreements++; }
      else if(snap.rsi < 30.0) { confidence -= 10.0; }
   }

   // MA crossover check
   totalChecks++;
   if(orderType == ORDER_TYPE_BUY)
   {
      if(snap.maFast > snap.maSlow) { confidence += 15.0; agreements++; }
      else { confidence -= 5.0; }
   }
   else
   {
      if(snap.maFast < snap.maSlow) { confidence += 15.0; agreements++; }
      else { confidence -= 5.0; }
   }

   // MACD check
   totalChecks++;
   if(orderType == ORDER_TYPE_BUY)
   {
      if(snap.macdMain > snap.macdSignal && snap.macdHist > 0) { confidence += 15.0; agreements++; }
      else if(snap.macdMain < snap.macdSignal) { confidence -= 5.0; }
   }
   else
   {
      if(snap.macdMain < snap.macdSignal && snap.macdHist < 0) { confidence += 15.0; agreements++; }
      else if(snap.macdMain > snap.macdSignal) { confidence -= 5.0; }
   }

   // Stochastic check
   totalChecks++;
   if(orderType == ORDER_TYPE_BUY)
   {
      if(snap.stochMain < 20.0) { confidence += 10.0; agreements++; }
      else if(snap.stochMain > 80.0) { confidence -= 5.0; }
   }
   else
   {
      if(snap.stochMain > 80.0) { confidence += 10.0; agreements++; }
      else if(snap.stochMain < 20.0) { confidence -= 5.0; }
   }

   // Bollinger Bands check
   totalChecks++;
   if(orderType == ORDER_TYPE_BUY)
   {
      if(snap.closePrice <= snap.bbLower) { confidence += 10.0; agreements++; }
      else if(snap.closePrice >= snap.bbUpper) { confidence -= 5.0; }
   }
   else
   {
      if(snap.closePrice >= snap.bbUpper) { confidence += 10.0; agreements++; }
      else if(snap.closePrice <= snap.bbLower) { confidence -= 5.0; }
   }

   // Regime bonus
   totalChecks++;
   if(snap.regime == REGIME_TRENDING)
   {
      if((orderType == ORDER_TYPE_BUY && snap.maFast > snap.maSlow) ||
         (orderType == ORDER_TYPE_SELL && snap.maFast < snap.maSlow))
      { confidence += 10.0; agreements++; }
   }
   else if(snap.regime == REGIME_RANGING)
   {
      // Mean reversion favorable in ranging market
      confidence += 5.0;
      agreements++;
   }
   else if(snap.regime == REGIME_VOLATILE)
   {
      confidence -= 10.0;
   }

   // Clamp to 0-100
   if(confidence < 0.0)   confidence = 0.0;
   if(confidence > 100.0) confidence = 100.0;

   return confidence;
}

//--- Get session name from hour
string CIndicatorEngine::GetSessionName(int hour)
{
   if(hour >= 7 && hour < 16)
      return "London";
   else if(hour >= 13 && hour < 22)
      return "New York";
   else if(hour >= 0 && hour < 9)
      return "Tokyo";
   else if(hour >= 22 || hour < 1)
      return "Sydney";
   return "Off-Session";
}

//--- Check if within trading hours
bool CIndicatorEngine::IsWithinTradingHours(int currentHour, int startHour, int endHour)
{
   if(startHour <= endHour)
      return (currentHour >= startHour && currentHour < endHour);
   else
      return (currentHour >= startHour || currentHour < endHour);
}

#endif // AIEA_INDICATOR_ENGINE_MQH
//+------------------------------------------------------------------+
