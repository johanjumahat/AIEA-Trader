//+------------------------------------------------------------------+
//| OptimizationEngine.mqh — Adaptive Parameter Optimization         |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_OPTIMIZATION_ENGINE_MQH
#define AIEA_OPTIMIZATION_ENGINE_MQH

#include "Config.mqh"
#include "StrategyEvolution.mqh"
#include "LearningEngine.mqh"
#include "PatternRecognition.mqh"
#include "TradingJournal.mqh"

#define MAX_PROPOSED_CHANGES 50

//==================================================================
//  OPTIMIZATION ENGINE CLASS
//==================================================================

class COptimizationEngine
{
private:
   ProposedChange      m_changes[MAX_PROPOSED_CHANGES];
   int                 m_changeCount;
   int                 m_nextChangeId;
   CStrategyEvolution  *m_evolution;
   CLearningEngine     *m_learningEngine;
   CPatternRecognition *m_patternRecognition;
   CTradingJournal     *m_journal;
   int                 m_minEvidenceTrades;
   bool                m_autoApply;

   void   ProposeChange(int profileId, string parameter, double oldValue,
                        double newValue, string rationale, double expectedImprovement,
                        int evidenceTrades);
   double ClampDouble(double value, double minVal, double maxVal);
   int    ClampInt(int value, int minVal, int maxVal);

public:
   COptimizationEngine();
   ~COptimizationEngine();

   bool   Init(CStrategyEvolution &evolution, CLearningEngine &learningEngine,
               CPatternRecognition &patternRecognition, CTradingJournal &journal,
               int minEvidenceTrades = 10);
   bool   RunOptimization(int profileId);
   int    GetPendingChanges(ProposedChange &pending[], int &count);
   bool   ApproveChange(int changeId);
   bool   RejectChange(int changeId, string note);
   bool   ApplyApprovedChanges();
   int    GetChangeCount() { return m_changeCount; }
   bool   SetAutoApply(bool autoApply) { m_autoApply = autoApply; return true; }
   bool   GetAutoApply() { return m_autoApply; }
   bool   SaveChanges();
   bool   LoadChanges();
   string GetChangesSummary();
};

//--- Constructor
COptimizationEngine::COptimizationEngine()
{
   m_changeCount = 0;
   m_nextChangeId = 1;
   m_evolution = NULL;
   m_learningEngine = NULL;
   m_patternRecognition = NULL;
   m_journal = NULL;
   m_minEvidenceTrades = 10;
   m_autoApply = false;

   for(int i = 0; i < MAX_PROPOSED_CHANGES; i++)
      InitProposedChange(m_changes[i]);
}

//--- Destructor
COptimizationEngine::~COptimizationEngine()
{
}

//--- Initialize
bool COptimizationEngine::Init(CStrategyEvolution &evolution,
                                CLearningEngine &learningEngine,
                                CPatternRecognition &patternRecognition,
                                CTradingJournal &journal,
                                int minEvidenceTrades)
{
   m_evolution = GetPointer(evolution);
   m_learningEngine = GetPointer(learningEngine);
   m_patternRecognition = GetPointer(patternRecognition);
   m_journal = GetPointer(journal);
   m_minEvidenceTrades = minEvidenceTrades;
   return true;
}

//--- Clamp helpers
double COptimizationEngine::ClampDouble(double value, double minVal, double maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

int COptimizationEngine::ClampInt(int value, int minVal, int maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

//--- Propose a parameter change
void COptimizationEngine::ProposeChange(int profileId, string parameter,
                                         double oldValue, double newValue,
                                         string rationale, double expectedImprovement,
                                         int evidenceTrades)
{
   if(m_changeCount >= MAX_PROPOSED_CHANGES)
   {
      // Shift array to make room
      for(int i = 0; i < MAX_PROPOSED_CHANGES - 1; i++)
         m_changes[i] = m_changes[i + 1];
      m_changeCount = MAX_PROPOSED_CHANGES - 1;
   }

   InitProposedChange(m_changes[m_changeCount]);
   m_changes[m_changeCount].changeId           = m_nextChangeId++;
   m_changes[m_changeCount].profileId          = profileId;
   m_changes[m_changeCount].parameter          = parameter;
   m_changes[m_changeCount].oldValue           = oldValue;
   m_changes[m_changeCount].newValue           = newValue;
   m_changes[m_changeCount].rationale          = rationale;
   m_changes[m_changeCount].expectedImprovement = expectedImprovement;
   m_changes[m_changeCount].evidenceTrades     = evidenceTrades;
   m_changes[m_changeCount].approval           = APPROVAL_PENDING;
   m_changes[m_changeCount].proposed           = TimeCurrent();

   m_changeCount++;

   Print("[Optimization] Proposed: ", parameter, " ", DoubleToString(oldValue, 2),
         " -> ", DoubleToString(newValue, 2), " for profile ", profileId,
         " (evidence: ", evidenceTrades, " trades)");

   if(m_autoApply)
   {
      ApproveChange(m_changes[m_changeCount - 1].changeId);
      ApplyApprovedChanges();
   }
}

//--- Run optimization analysis for a profile
bool COptimizationEngine::RunOptimization(int profileId)
{
   if(m_learningEngine == NULL || m_evolution == NULL) return false;

   ParameterSet ps;
   if(!m_evolution.GetProfileById(profileId, ps)) return false;

   int tradeCount = m_learningEngine.GetTradeCount(profileId);

   // Only optimize if we have enough evidence
   if(tradeCount < m_minEvidenceTrades)
   {
      Print("[Optimization] Profile ", profileId, " has only ", tradeCount,
            " trades. Need ", m_minEvidenceTrades, " for optimization.");
      return false;
   }

   double winRate   = m_learningEngine.GetWinRate(profileId);
   double profitFactor = m_learningEngine.GetProfitFactor(profileId);
   double expectancy = m_learningEngine.GetExpectancy(profileId);
   double avgRR     = m_learningEngine.GetAvgRiskReward(profileId);

   Print("[Optimization] Profile ", profileId, " — WinRate: ", DoubleToString(winRate, 1),
         "%  PF: ", DoubleToString(profitFactor, 2), "  Expectancy: ", DoubleToString(expectancy, 2),
         "  AvgRR: ", DoubleToString(avgRR, 2));

   // Read journal entries for detailed analysis
   JournalEntry entries[];
   int entryCount = 0;
   m_journal.ReadEntriesByProfile(profileId, entries, entryCount);

   // Analyze SL tightness across trades
   int slTooTight = 0, slTooWide = 0, slAppropriate = 0;
   int tpTooClose = 0, tpTooFar = 0, tpAppropriate = 0;
   double totalSpread = 0.0;
   double totalSlippage = 0.0;
   double totalMFE = 0.0;
   double totalMAE = 0.0;
   int winCount = 0, lossCount = 0;

   for(int i = 0; i < entryCount; i++)
   {
      switch(entries[i].slAssessment)
      {
         case SL_TOO_TIGHT:    slTooTight++;    break;
         case SL_TOO_WIDE:     slTooWide++;     break;
         case SL_APPROPRIATE:  slAppropriate++; break;
         default: break;
      }

      switch(entries[i].tpAssessment)
      {
         case TP_TOO_CLOSE:    tpTooClose++;    break;
         case TP_TOO_FAR:      tpTooFar++;      break;
         case TP_APPROPRIATE:  tpAppropriate++; break;
         default: break;
      }

      totalSpread += entries[i].spreadAtEntry;
      totalSlippage += entries[i].slippage;
      totalMFE += entries[i].mfe;
      totalMAE += entries[i].mae;

      if(entries[i].outcome == OUTCOME_WIN) winCount++;
      else if(entries[i].outcome == OUTCOME_LOSS) lossCount++;
   }

   // === SL OPTIMIZATION ===
   if(slTooTight > slAppropriate && slTooTight > m_minEvidenceTrades / 2)
   {
      double newSL = ClampDouble(ps.stopLossDistance * 1.2, 0.5, 5.0);
      if(newSL != ps.stopLossDistance)
      {
         ProposeChange(profileId, "stopLossDistance", ps.stopLossDistance, newSL,
            StringFormat("SL too tight in %d/%d trades — widening by 20%%", slTooTight, entryCount),
            5.0, slTooTight);
      }
   }

   if(slTooWide > slAppropriate && slTooWide > m_minEvidenceTrades / 2)
   {
      double newSL = ClampDouble(ps.stopLossDistance * 0.8, 0.5, 5.0);
      if(newSL != ps.stopLossDistance)
      {
         ProposeChange(profileId, "stopLossDistance", ps.stopLossDistance, newSL,
            StringFormat("SL too wide in %d/%d trades — tightening by 20%%", slTooWide, entryCount),
            3.0, slTooWide);
      }
   }

   // === TP OPTIMIZATION ===
   if(tpTooClose > tpAppropriate && tpTooClose > m_minEvidenceTrades / 2)
   {
      double newTP = ClampDouble(ps.takeProfitDistance * 1.15, 1.0, 10.0);
      if(newTP != ps.takeProfitDistance)
      {
         ProposeChange(profileId, "takeProfitDistance", ps.takeProfitDistance, newTP,
            StringFormat("TP too close in %d/%d trades — extending by 15%%", tpTooClose, entryCount),
            4.0, tpTooClose);
      }
   }

   if(tpTooFar > tpAppropriate && tpTooFar > m_minEvidenceTrades / 2)
   {
      double newTP = ClampDouble(ps.takeProfitDistance * 0.85, 1.0, 10.0);
      if(newTP != ps.takeProfitDistance)
      {
         ProposeChange(profileId, "takeProfitDistance", ps.takeProfitDistance, newTP,
            StringFormat("TP too far in %d/%d trades — reducing by 15%%", tpTooFar, entryCount),
            3.0, tpTooFar);
      }
   }

   // === CONFIDENCE THRESHOLD OPTIMIZATION ===
   // If win rate is high but few trades taken, lower confidence threshold
   if(winRate > 65.0 && entryCount < 30)
   {
      double newConf = ClampDouble(ps.minConfidence - 5.0, 30.0, 90.0);
      if(newConf != ps.minConfidence)
      {
         ProposeChange(profileId, "minConfidence", ps.minConfidence, newConf,
            StringFormat("Win rate %.1f%% but only %d trades — lowering confidence threshold", winRate, entryCount),
            2.0, entryCount);
      }
   }

   // If win rate is low, raise confidence threshold
   if(winRate < 35.0 && entryCount >= m_minEvidenceTrades)
   {
      double newConf = ClampDouble(ps.minConfidence + 5.0, 30.0, 90.0);
      if(newConf != ps.minConfidence)
      {
         ProposeChange(profileId, "minConfidence", ps.minConfidence, newConf,
            StringFormat("Win rate only %.1f%% — raising confidence threshold", winRate),
            3.0, entryCount);
      }
   }

   // === ATR MULTIPLIER OPTIMIZATION ===
   double avgMFE = totalMFE / (entryCount > 0 ? entryCount : 1);
   double avgMAE = totalMAE / (entryCount > 0 ? entryCount : 1);

   if(avgMAE > avgMFE * 1.5 && entryCount >= m_minEvidenceTrades)
   {
      double newATR = ClampDouble(ps.atrMultiplier * 1.1, 0.5, 5.0);
      if(newATR != ps.atrMultiplier)
      {
         ProposeChange(profileId, "atrMultiplier", ps.atrMultiplier, newATR,
            "Average adverse excursion exceeds favorable — increasing ATR multiplier",
            2.0, entryCount);
      }
   }

   // === SPREAD FILTER OPTIMIZATION ===
   double avgSpread = totalSpread / (entryCount > 0 ? entryCount : 1);
   if(avgSpread > ps.maxSpreadPoints * 0.8 && entryCount >= m_minEvidenceTrades)
   {
      double newSpread = ClampDouble(ps.maxSpreadPoints * 0.9, 5.0, 100.0);
      if(newSpread != ps.maxSpreadPoints)
      {
         ProposeChange(profileId, "maxSpreadPoints", ps.maxSpreadPoints, newSpread,
            StringFormat("Avg spread %.1f pts close to limit %.1f — tightening spread filter",
                         avgSpread, ps.maxSpreadPoints),
            1.5, entryCount);
      }
   }

   // === TRAILING STOP OPTIMIZATION ===
   // If many wins have MFE >> actual profit, trailing stop might be too tight
   double trailingTooTightCount = 0.0;
   for(int i = 0; i < entryCount; i++)
   {
      if(entries[i].outcome == OUTCOME_WIN && entries[i].mfe > MathAbs(entries[i].profit) * 3.0)
         trailingTooTightCount++;
   }

   if(trailingTooTightCount > m_minEvidenceTrades / 2)
   {
      double newTrail = ClampDouble(ps.trailingStop * 1.2, 0.3, 5.0);
      if(newTrail != ps.trailingStop)
      {
         ProposeChange(profileId, "trailingStop", ps.trailingStop, newTrail,
            StringFormat("%.0f wins had MFE >> profit — loosening trailing stop", trailingTooTightCount),
            2.5, (int)trailingTooTightCount);
      }
   }

   // === RSI PERIOD OPTIMIZATION ===
   // If performance is poor, try adjusting RSI period
   if(winRate < 40.0 && entryCount >= m_minEvidenceTrades * 2)
   {
      int newRSI = ClampInt(ps.rsiPeriod + 2, 5, 30);
      if(newRSI != ps.rsiPeriod)
      {
         ProposeChange(profileId, "rsiPeriod", (double)ps.rsiPeriod, (double)newRSI,
            StringFormat("Win rate %.1f%% — extending RSI period for smoother signals", winRate),
            1.5, entryCount);
      }
   }

   // === POSITION SIZE (never increase, only decrease if performing poorly) ===
   if(profitFactor < 1.0 && entryCount >= m_minEvidenceTrades * 2)
   {
      double newSize = ClampDouble(ps.positionSizePercent * 0.8, 0.1, 10.0);
      if(newSize != ps.positionSizePercent)
      {
         ProposeChange(profileId, "positionSizePercent", ps.positionSizePercent, newSize,
            StringFormat("Profit factor %.2f < 1.0 — reducing position size by 20%%", profitFactor),
            5.0, entryCount);
      }
   }

   Print("[Optimization] Analysis complete for profile ", profileId, ". ",
         m_changeCount, " total proposed changes.");

   return true;
}

//--- Get all pending (unreviewed) changes
int COptimizationEngine::GetPendingChanges(ProposedChange &pending[], int &count)
{
   count = 0;
   for(int i = 0; i < m_changeCount; i++)
   {
      if(m_changes[i].approval == APPROVAL_PENDING)
      {
         ArrayResize(pending, count + 1);
         pending[count] = m_changes[i];
         count++;
      }
   }
   return count;
}

//--- Approve a proposed change
bool COptimizationEngine::ApproveChange(int changeId)
{
   for(int i = 0; i < m_changeCount; i++)
   {
      if(m_changes[i].changeId == changeId)
      {
         m_changes[i].approval = APPROVAL_APPROVED;
         m_changes[i].reviewed = TimeCurrent();
         Print("[Optimization] Change #", changeId, " approved.");
         return true;
      }
   }
   return false;
}

//--- Reject a proposed change
bool COptimizationEngine::RejectChange(int changeId, string note)
{
   for(int i = 0; i < m_changeCount; i++)
   {
      if(m_changes[i].changeId == changeId)
      {
         m_changes[i].approval = APPROVAL_REJECTED;
         m_changes[i].reviewed = TimeCurrent();
         m_changes[i].reviewerNote = note;
         Print("[Optimization] Change #", changeId, " rejected: ", note);
         return true;
      }
   }
   return false;
}

//--- Apply all approved changes to profiles
bool COptimizationEngine::ApplyApprovedChanges()
{
   if(m_evolution == NULL) return false;

   int appliedCount = 0;

   for(int i = 0; i < m_changeCount; i++)
   {
      if(m_changes[i].approval != APPROVAL_APPROVED)
         continue;

      int profileId = m_changes[i].profileId;
      ParameterSet ps;
      if(!m_evolution.GetProfileById(profileId, ps)) continue;

      string param = m_changes[i].parameter;
      double newVal = m_changes[i].newValue;

      // Apply the change based on parameter name
      if(param == "rsiPeriod")           ps.rsiPeriod = (int)newVal;
      else if(param == "maFastPeriod")    ps.maFastPeriod = (int)newVal;
      else if(param == "maSlowPeriod")    ps.maSlowPeriod = (int)newVal;
      else if(param == "bbPeriod")        ps.bbPeriod = (int)newVal;
      else if(param == "bbDeviation")     ps.bbDeviation = newVal;
      else if(param == "macdFast")        ps.macdFast = (int)newVal;
      else if(param == "macdSlow")        ps.macdSlow = (int)newVal;
      else if(param == "macdSignal")      ps.macdSignal = (int)newVal;
      else if(param == "stochK")          ps.stochK = (int)newVal;
      else if(param == "stochD")          ps.stochD = (int)newVal;
      else if(param == "stochSlow")       ps.stochSlow = (int)newVal;
      else if(param == "atrMultiplier")   ps.atrMultiplier = newVal;
      else if(param == "atrPeriod")       ps.atrPeriod = (int)newVal;
      else if(param == "stopLossDistance") ps.stopLossDistance = newVal;
      else if(param == "takeProfitDistance") ps.takeProfitDistance = newVal;
      else if(param == "trailingStop")    ps.trailingStop = newVal;
      else if(param == "breakEvenTrigger") ps.breakEvenTrigger = newVal;
      else if(param == "positionSizePercent") ps.positionSizePercent = newVal;
      else if(param == "tradingStartHour") ps.tradingStartHour = (int)newVal;
      else if(param == "tradingEndHour")   ps.tradingEndHour = (int)newVal;
      else if(param == "maxSpreadPoints") ps.maxSpreadPoints = newVal;
      else if(param == "minConfidence")   ps.minConfidence = newVal;
      else if(param == "maxDailyLossPercent") ps.maxDailyLossPercent = newVal;
      else if(param == "maxOpenPositions") ps.maxOpenPositions = (int)newVal;
      else if(param == "maxDrawdownPercent") ps.maxDrawdownPercent = newVal;
      else
      {
         Print("[Optimization] Unknown parameter: ", param);
         continue;
      }

      // Mark as applied by setting approval to NONE (already applied)
      m_changes[i].approval = APPROVAL_NONE;
      appliedCount++;

      // Update the profile in the evolution engine
      // We need to find and update the profile
      m_evolution.SetProfileParam(profileId, param, newVal);

      Print("[Optimization] Applied: ", param, " = ", DoubleToString(newVal, 2),
            " to profile ", profileId);
   }

   if(appliedCount > 0)
   {
      m_evolution.SaveProfiles();
      Print("[Optimization] Applied ", appliedCount, " changes and saved profiles.");
   }

   return true;
}

//--- Save proposed changes to file
bool COptimizationEngine::SaveChanges()
{
   string fileName = "AIEA_Trader\\changes.csv";
   int handle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');

   if(handle == INVALID_HANDLE)
      return false;

   for(int i = 0; i < m_changeCount; i++)
   {
      FileWrite(handle,
         (string)m_changes[i].changeId,
         (string)m_changes[i].profileId,
         m_changes[i].parameter,
         DoubleToString(m_changes[i].oldValue, 5),
         DoubleToString(m_changes[i].newValue, 5),
         m_changes[i].rationale,
         DoubleToString(m_changes[i].expectedImprovement, 2),
         (string)m_changes[i].evidenceTrades,
         (string)m_changes[i].approval,
         (string)m_changes[i].proposed,
         (string)m_changes[i].reviewed,
         m_changes[i].reviewerNote
      );
   }

   FileClose(handle);
   return true;
}

//--- Load proposed changes from file
bool COptimizationEngine::LoadChanges()
{
   string fileName = "AIEA_Trader\\changes.csv";

   if(!FileIsExist(fileName, 0))
      return false;

   int handle = FileOpen(fileName, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   m_changeCount = 0;

   while(!FileIsEnding(handle) && m_changeCount < MAX_PROPOSED_CHANGES)
   {
      string idStr = FileReadString(handle);
      if(idStr == "") break;

      InitProposedChange(m_changes[m_changeCount]);
      m_changes[m_changeCount].changeId            = (int)StringToInteger(idStr);
      m_changes[m_changeCount].profileId           = (int)StringToInteger(FileReadString(handle));
      m_changes[m_changeCount].parameter           = FileReadString(handle);
      m_changes[m_changeCount].oldValue            = StringToDouble(FileReadString(handle));
      m_changes[m_changeCount].newValue            = StringToDouble(FileReadString(handle));
      m_changes[m_changeCount].rationale           = FileReadString(handle);
      m_changes[m_changeCount].expectedImprovement = StringToDouble(FileReadString(handle));
      m_changes[m_changeCount].evidenceTrades     = (int)StringToInteger(FileReadString(handle));
      m_changes[m_changeCount].approval           = (ENUM_APPROVAL_STATE)(int)StringToInteger(FileReadString(handle));
      m_changes[m_changeCount].proposed            = (datetime)StringToInteger(FileReadString(handle));
      m_changes[m_changeCount].reviewed            = (datetime)StringToInteger(FileReadString(handle));
      m_changes[m_changeCount].reviewerNote       = FileReadString(handle);

      if(m_changes[m_changeCount].changeId >= m_nextChangeId)
         m_nextChangeId = m_changes[m_changeCount].changeId + 1;

      m_changeCount++;
   }

   FileClose(handle);
   return true;
}

//--- Get summary of all changes
string COptimizationEngine::GetChangesSummary()
{
   string summary = "=== Proposed Changes ===\n";

   int pending = 0, approved = 0, rejected = 0;

   for(int i = 0; i < m_changeCount; i++)
   {
      string stateStr;
      switch(m_changes[i].approval)
      {
         case APPROVAL_PENDING:  stateStr = "PENDING";  pending++;  break;
         case APPROVAL_APPROVED: stateStr = "APPROVED"; approved++; break;
         case APPROVAL_REJECTED: stateStr = "REJECTED"; rejected++; break;
         default:                stateStr = "APPLIED";  break;
      }

      summary += StringFormat("#%d [%s] Profile %d: %s %.2f->%.2f | %s\n",
         m_changes[i].changeId, stateStr, m_changes[i].profileId,
         m_changes[i].parameter, m_changes[i].oldValue, m_changes[i].newValue,
         m_changes[i].rationale);
   }

   summary += StringFormat("\nTotal: %d | Pending: %d | Approved: %d | Rejected: %d\n",
      m_changeCount, pending, approved, rejected);

   return summary;
}

#endif // AIEA_OPTIMIZATION_ENGINE_MQH
//+------------------------------------------------------------------+
