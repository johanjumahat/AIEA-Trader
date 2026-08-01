//+------------------------------------------------------------------+
//| RiskManager.mqh — Safety Controls and Position Sizing            |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_RISK_MANAGER_MQH
#define AIEA_RISK_MANAGER_MQH

#include "Config.mqh"
#include <Trade\Trade.mqh>

//==================================================================
//  RISK MANAGER CLASS
//==================================================================

class CRiskManager
{
private:
   double   m_startOfDayEquity;
   double   m_peakEquity;
   datetime m_lastResetDay;
   int      m_positionsOpenedToday;
   double   m_dailyProfit;
   bool     m_tradingHalted;
   string   m_haltReason;

public:
   CRiskManager();
   ~CRiskManager();

   bool   Init();
   void   ResetDaily();
   double CalculateLotSize(double riskPercent, double stopLossPoints,
                           string symbol, double atrValue);
   bool   CanOpenPosition(const ParameterSet &params);
   bool   CheckDailyLossLimit(const ParameterSet &params);
   bool   CheckDrawdownLimit(const ParameterSet &params);
   double GetDailyProfit()   { return m_dailyProfit; }
   double GetStartOfDayEquity() { return m_startOfDayEquity; }
   double GetPeakEquity()     { return m_peakEquity; }
   bool   IsHalted()          { return m_tradingHalted; }
   string GetHaltReason()    { return m_haltReason; }
   void   HaltTrading(string reason);
   void   ResumeTrading();
   void   RecordProfit(double profit);
   int    GetPositionsToday() { return m_positionsOpenedToday; }
   void   IncrementPositions() { m_positionsOpenedToday++; }
};

//--- Constructor
CRiskManager::CRiskManager()
{
   m_startOfDayEquity    = 0.0;
   m_peakEquity          = 0.0;
   m_lastResetDay        = 0;
   m_positionsOpenedToday = 0;
   m_dailyProfit         = 0.0;
   m_tradingHalted       = false;
   m_haltReason          = "";
}

//--- Destructor
CRiskManager::~CRiskManager()
{
}

//--- Initialize
bool CRiskManager::Init()
{
   m_startOfDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_peakEquity       = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   m_lastResetDay = StructToTime(dt);
   m_positionsOpenedToday = 0;
   m_dailyProfit = 0.0;
   m_tradingHalted = false;
   m_haltReason = "";
   return true;
}

//--- Reset daily counters (called at the start of each trading day)
void CRiskManager::ResetDaily()
{
   m_startOfDayEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   m_positionsOpenedToday = 0;
   m_dailyProfit          = 0.0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   m_lastResetDay = StructToTime(dt);
}

//--- Calculate lot size based on risk percentage and SL distance
double CRiskManager::CalculateLotSize(double riskPercent, double stopLossPoints,
                                       string symbol, double atrValue)
{
   if(riskPercent <= 0.0 || stopLossPoints <= 0.0)
      return 0.01;

   double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount   = equity * (riskPercent / 100.0);
   double tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point        = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
      return 0.01;

   double valuePerPoint = tickValue * (point / tickSize);
   double lossPerLot    = stopLossPoints * valuePerPoint;

   if(lossPerLot <= 0.0)
      return 0.01;

   double lotSize = riskAmount / lossPerLot;

   // Normalize to broker constraints
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0.0)
      lotSize = MathFloor(lotSize / lotStep) * lotStep;

   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;

   // Round to 2 decimal places
   lotSize = MathFloor(lotSize * 100.0) / 100.0;

   return lotSize;
}

//--- Check if a new position can be opened
bool CRiskManager::CanOpenPosition(const ParameterSet &params)
{
   if(m_tradingHalted)
      return false;

   // Check day reset
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);

   if(today != m_lastResetDay)
      ResetDaily();

   // Check max open positions
   int currentPositions = PositionsTotal();
   if(currentPositions >= params.maxOpenPositions)
      return false;

   // Check daily loss limit
   if(!CheckDailyLossLimit(params))
      return false;

   // Check drawdown limit
   if(!CheckDrawdownLimit(params))
      return false;

   return true;
}

//--- Check daily loss limit
bool CRiskManager::CheckDailyLossLimit(const ParameterSet &params)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = (m_startOfDayEquity - equity) / m_startOfDayEquity * 100.0;

   if(dailyLoss >= params.maxDailyLossPercent)
   {
      HaltTrading(StringFormat("Daily loss limit reached: %.2f%% (max: %.2f%%)",
                               dailyLoss, params.maxDailyLossPercent));
      return false;
   }
   return true;
}

//--- Check drawdown limit
bool CRiskManager::CheckDrawdownLimit(const ParameterSet &params)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > m_peakEquity)
      m_peakEquity = equity;

   if(m_peakEquity <= 0.0)
      return true;

   double drawdown = (m_peakEquity - equity) / m_peakEquity * 100.0;

   if(drawdown >= params.maxDrawdownPercent)
   {
      HaltTrading(StringFormat("Max drawdown reached: %.2f%% (max: %.2f%%)",
                               drawdown, params.maxDrawdownPercent));
      return false;
   }
   return true;
}

//--- Halt trading
void CRiskManager::HaltTrading(string reason)
{
   m_tradingHalted = true;
   m_haltReason    = reason;
   Print("[RiskManager] Trading halted: ", reason);
}

//--- Resume trading
void CRiskManager::ResumeTrading()
{
   m_tradingHalted = false;
   m_haltReason    = "";
   Print("[RiskManager] Trading resumed.");
}

//--- Record profit from a closed trade
void CRiskManager::RecordProfit(double profit)
{
   m_dailyProfit += profit;
}

#endif // AIEA_RISK_MANAGER_MQH
//+------------------------------------------------------------------+
