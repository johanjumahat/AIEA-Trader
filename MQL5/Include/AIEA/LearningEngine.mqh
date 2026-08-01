//+------------------------------------------------------------------+
//| LearningEngine.mqh — Post-Trade Analysis & Lesson Extraction     |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_LEARNING_ENGINE_MQH
#define AIEA_LEARNING_ENGINE_MQH

#include "Config.mqh"
#include "TradingJournal.mqh"
#include "IndicatorEngine.mqh"

//==================================================================
//  LEARNING ENGINE CLASS
//==================================================================

class CLearningEngine
{
private:
   CTradingJournal  *m_journal;
   int               m_minTradesForAnalysis;

   string  RegimeString(ENUM_MARKET_REGIME r);
   string  OutcomeString(ENUM_TRADE_OUTCOME o);

public:
   CLearningEngine();
   ~CLearningEngine();

   bool   Init(CTradingJournal &journal, int minTrades = 5);
   void   AnalyzeTrade(JournalEntry &je, const ParameterSet &params);
   ENUM_ENTRY_QUALITY  AssessEntryTiming(const JournalEntry &je);
   ENUM_EXIT_QUALITY   AssessExitTiming(const JournalEntry &je);
   ENUM_SL_ASSESSMENT  AssessStopLoss(const JournalEntry &je);
   ENUM_TP_ASSESSMENT   AssessTakeProfit(const JournalEntry &je);
   string GenerateLesson(const JournalEntry &je);
   double CalculatePerformanceImpact(const JournalEntry &je);
   int    GetMinTrades() { return m_minTradesForAnalysis; }

   // Aggregate analysis
   double GetWinRate(int profileId);
   double GetProfitFactor(int profileId);
   double GetExpectancy(int profileId);
   double GetAvgRiskReward(int profileId);
   int    GetTradeCount(int profileId);
};

//--- Constructor
CLearningEngine::CLearningEngine()
{
   m_journal = NULL;
   m_minTradesForAnalysis = 5;
}

//--- Destructor
CLearningEngine::~CLearningEngine()
{
}

//--- Initialize
bool CLearningEngine::Init(CTradingJournal &journal, int minTrades)
{
   m_journal = GetPointer(journal);
   m_minTradesForAnalysis = minTrades;
   return true;
}

//--- Regime string helper
string CLearningEngine::RegimeString(ENUM_MARKET_REGIME r)
{
   switch(r)
   {
      case REGIME_TRENDING: return "trending";
      case REGIME_RANGING:  return "ranging";
      case REGIME_VOLATILE: return "volatile";
      default:             return "unknown";
   }
}

//--- Outcome string helper
string CLearningEngine::OutcomeString(ENUM_TRADE_OUTCOME o)
{
   switch(o)
   {
      case OUTCOME_WIN:       return "win";
      case OUTCOME_LOSS:      return "loss";
      case OUTCOME_BREAKEVEN: return "breakeven";
      default:                return "pending";
   }
}

//--- Full trade analysis — fills all assessment fields in the journal entry
void CLearningEngine::AnalyzeTrade(JournalEntry &je, const ParameterSet &params)
{
   if(je.outcome == OUTCOME_PENDING)
      return;

   // Assess entry timing
   je.entryQuality = AssessEntryTiming(je);

   // Assess exit timing
   je.exitQuality = AssessExitTiming(je);

   // Assess stop loss
   je.slAssessment = AssessStopLoss(je);

   // Assess take profit
   je.tpAssessment = AssessTakeProfit(je);

   // Calculate performance impact on profile score
   je.performanceImpact = CalculatePerformanceImpact(je);

   // Generate lesson learned
   je.lessonLearned = GenerateLesson(je);
}

//--- Assess entry timing quality
ENUM_ENTRY_QUALITY CLearningEngine::AssessEntryTiming(const JournalEntry &je)
{
   // If trade was profitable with good MFE, entry was likely good
   // If trade hit SL quickly, entry was likely poor

   double mfePoints = je.mfe;
   double maePoints = je.mae;

   // Quick loss = poor entry
   if(je.outcome == OUTCOME_LOSS && maePoints > mfePoints * 2.0)
      return ENTRY_POOR;

   // Good profit with limited initial adverse movement = optimal
   if(je.outcome == OUTCOME_WIN && maePoints < mfePoints * 0.3)
      return ENTRY_OPTIMAL;

   // Moderate success
   if(je.outcome == OUTCOME_WIN)
      return ENTRY_AVERAGE;

   // Loss but with some favorable movement first
   if(je.outcome == OUTCOME_LOSS && mfePoints > 0.0)
      return ENTRY_AVERAGE;

   return ENTRY_POOR;
}

//--- Assess exit timing quality
ENUM_EXIT_QUALITY CLearningEngine::AssessExitTiming(const JournalEntry &je)
{
   // If MFE >> actual profit, we exited too early (suboptimal)
   // If trade hit TP, exit was optimal
   // If trade hit SL, exit was forced (poor)

   if(je.outcome == OUTCOME_WIN)
   {
      // Check if we left too much on the table
      if(je.mfe > MathAbs(je.profit) * 3.0 && MathAbs(je.profit) > 0.0)
         return EXIT_AVERAGE; // Exited with profit but could have been better
      return EXIT_OPTIMAL;
   }

   if(je.outcome == OUTCOME_LOSS)
   {
      // If there was significant favorable excursion before the loss, exit was poor
      if(je.mfe > 0.0 && je.mfe > je.mae)
         return EXIT_POOR;
      return EXIT_AVERAGE;
   }

   return EXIT_UNKNOWN;
}

//--- Assess stop loss placement
ENUM_SL_ASSESSMENT CLearningEngine::AssessStopLoss(const JournalEntry &je)
{
   if(je.mae <= 0.0)
      return SL_APPROPRIATE;

   double slDistance = MathAbs(je.openPrice - je.stopLoss);

   if(slDistance <= 0.0)
      return SL_UNKNOWN;

   // If MAE exceeded 80% of SL distance, SL was too tight
   if(je.mae >= slDistance * 0.8 && je.outcome == OUTCOME_LOSS)
      return SL_TOO_TIGHT;

   // If trade won comfortably and MAE was small, SL was too wide
   if(je.outcome == OUTCOME_WIN && je.mae < slDistance * 0.3)
      return SL_TOO_WIDE;

   return SL_APPROPRIATE;
}

//--- Assess take profit placement
ENUM_TP_ASSESSMENT CLearningEngine::AssessTakeProfit(const JournalEntry &je)
{
   double tpDistance = MathAbs(je.takeProfit - je.openPrice);

   if(tpDistance <= 0.0)
      return TP_UNKNOWN;

   // If MFE >> TP distance, TP was too close (left profit on table)
   if(je.mfe > tpDistance * 1.5)
      return TP_TOO_CLOSE;

   // If trade hit SL before getting close to TP, TP may be too far
   if(je.outcome == OUTCOME_LOSS && je.mfe < tpDistance * 0.3)
      return TP_TOO_FAR;

   return TP_APPROPRIATE;
}

//--- Generate a human-readable lesson from the trade
string CLearningEngine::GenerateLesson(const JournalEntry &je)
{
   string lesson = "";

   // Outcome summary
   lesson += StringFormat("%s on %s (%s market, %s session, hour %d). ",
      OutcomeString(je.outcome), je.symbol, RegimeString(je.regime),
      je.session, je.hour);

   // Entry quality lesson
   switch(je.entryQuality)
   {
      case ENTRY_OPTIMAL:
         lesson += "Entry timing was optimal. ";
         break;
      case ENTRY_AVERAGE:
         lesson += "Entry timing was average — consider refining entry trigger. ";
         break;
      case ENTRY_POOR:
         lesson += "Entry timing was poor — review entry conditions. ";
         break;
      default: break;
   }

   // Exit quality lesson
   switch(je.exitQuality)
   {
      case EXIT_OPTIMAL:
         lesson += "Exit was well-timed. ";
         break;
      case EXIT_AVERAGE:
         lesson += "Exit was suboptimal — some profit left on table. ";
         break;
      case EXIT_POOR:
         lesson += "Exit was poorly timed — favorable move reversed. ";
         break;
      default: break;
   }

   // SL lesson
   switch(je.slAssessment)
   {
      case SL_TOO_TIGHT:
         lesson += "Stop loss was too tight — consider widening. ";
         break;
      case SL_TOO_WIDE:
         lesson += "Stop loss was too wide — consider tightening. ";
         break;
      default: break;
   }

   // TP lesson
   switch(je.tpAssessment)
   {
      case TP_TOO_CLOSE:
         lesson += "Take profit was too close — potential profit missed. ";
         break;
      case TP_TOO_FAR:
         lesson += "Take profit was too far — target rarely reached. ";
         break;
      default: break;
   }

   // Spread/slippage impact
   if(je.spreadAtEntry > 20.0)
      lesson += "High spread at entry reduced profitability. ";
   if(je.slippage > 5.0)
      lesson += "Significant slippage detected. ";

   // Volatility impact
   if(je.volatilityPercent > 1.5)
      lesson += "High volatility may have affected outcome. ";

   // Confidence calibration
   if(je.outcome == OUTCOME_LOSS && je.confidence > 70.0)
      lesson += "Confidence was high but trade failed — recalibrate confidence model. ";
   if(je.outcome == OUTCOME_WIN && je.confidence < 40.0)
      lesson += "Low confidence but trade won — may need to lower confidence threshold. ";

   // R:R lesson
   if(je.outcome == OUTCOME_LOSS && je.riskRewardRatio < 1.0)
      lesson += "Risk:reward was unfavorable. ";
   if(je.outcome == OUTCOME_WIN && je.riskRewardRatio >= 2.0)
      lesson += "Excellent risk:reward achieved. ";

   return lesson;
}

//--- Calculate performance impact on profile score
double CLearningEngine::CalculatePerformanceImpact(const JournalEntry &je)
{
   double impact = 0.0;

   // Base impact from outcome
   if(je.outcome == OUTCOME_WIN)
      impact += 2.0;
   else if(je.outcome == OUTCOME_LOSS)
      impact -= 2.0;
   else
      impact += 0.0;

   // Adjust for entry quality
   switch(je.entryQuality)
   {
      case ENTRY_OPTIMAL: impact += 1.0; break;
      case ENTRY_AVERAGE: impact += 0.0; break;
      case ENTRY_POOR:    impact -= 1.0; break;
      default: break;
   }

   // Adjust for exit quality
   switch(je.exitQuality)
   {
      case EXIT_OPTIMAL: impact += 0.5; break;
      case EXIT_AVERAGE: impact += 0.0; break;
      case EXIT_POOR:    impact -= 0.5; break;
      default: break;
   }

   // Adjust for R:R
   if(je.riskRewardRatio >= 2.0) impact += 0.5;
   if(je.riskRewardRatio < 1.0 && je.outcome == OUTCOME_LOSS) impact -= 0.5;

   // Clamp
   if(impact > 5.0)  impact = 5.0;
   if(impact < -5.0) impact = -5.0;

   return impact;
}

//--- Get win rate for a profile
double CLearningEngine::GetWinRate(int profileId)
{
   JournalEntry entries[];
   int count = 0;

   if(m_journal == NULL)
      return 0.0;

   m_journal.ReadEntriesByProfile(profileId, entries, count);

   if(count == 0)
      return 0.0;

   int wins = 0;
   for(int i = 0; i < count; i++)
   {
      if(entries[i].outcome == OUTCOME_WIN)
         wins++;
   }

   return (double)wins / (double)count * 100.0;
}

//--- Get profit factor for a profile
double CLearningEngine::GetProfitFactor(int profileId)
{
   JournalEntry entries[];
   int count = 0;

   if(m_journal == NULL)
      return 0.0;

   m_journal.ReadEntriesByProfile(profileId, entries, count);

   double grossProfit = 0.0;
   double grossLoss   = 0.0;

   for(int i = 0; i < count; i++)
   {
      if(entries[i].profit > 0.0)
         grossProfit += entries[i].profit;
      else
         grossLoss += MathAbs(entries[i].profit);
   }

   if(grossLoss <= 0.0)
      return (grossProfit > 0.0) ? 99.0 : 0.0;

   return grossProfit / grossLoss;
}

//--- Get expectancy for a profile
double CLearningEngine::GetExpectancy(int profileId)
{
   JournalEntry entries[];
   int count = 0;

   if(m_journal == NULL)
      return 0.0;

   m_journal.ReadEntriesByProfile(profileId, entries, count);

   if(count == 0)
      return 0.0;

   double totalProfit = 0.0;
   for(int i = 0; i < count; i++)
   {
      totalProfit += entries[i].profit;
   }

   return totalProfit / (double)count;
}

//--- Get average risk:reward for a profile
double CLearningEngine::GetAvgRiskReward(int profileId)
{
   JournalEntry entries[];
   int count = 0;

   if(m_journal == NULL)
      return 0.0;

   m_journal.ReadEntriesByProfile(profileId, entries, count);

   if(count == 0)
      return 0.0;

   double totalRR = 0.0;
   int validCount = 0;
   for(int i = 0; i < count; i++)
   {
      if(entries[i].riskRewardRatio > 0.0)
      {
         totalRR += entries[i].riskRewardRatio;
         validCount++;
      }
   }

   if(validCount == 0)
      return 0.0;

   return totalRR / (double)validCount;
}

//--- Get trade count for a profile
int CLearningEngine::GetTradeCount(int profileId)
{
   JournalEntry entries[];
   int count = 0;

   if(m_journal == NULL)
      return 0;

   m_journal.ReadEntriesByProfile(profileId, entries, count);
   return count;
}

#endif // AIEA_LEARNING_ENGINE_MQH
//+------------------------------------------------------------------+
