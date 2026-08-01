//+------------------------------------------------------------------+
//| StrategyEvolution.mqh — Multiple Profiles, Promotion & Rollback   |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_STRATEGY_EVOLUTION_MQH
#define AIEA_STRATEGY_EVOLUTION_MQH

#include "Config.mqh"
#include "LearningEngine.mqh"
#include "TradingJournal.mqh"

#define MAX_PROFILES 10

//==================================================================
//  STRATEGY EVOLUTION CLASS
//==================================================================

class CStrategyEvolution
{
private:
   ParameterSet      m_profiles[MAX_PROFILES];
   int               m_profileCount;
   int               m_activeProfileId;
   CLearningEngine  *m_learningEngine;
   CTradingJournal  *m_journal;

   int    FindProfileIndex(int profileId);
   double CalculateProfileScore(const ParameterSet &ps);
   void   UpdateProfileMetrics(ParameterSet &ps);

public:
   CStrategyEvolution();
   ~CStrategyEvolution();

   bool   Init(CLearningEngine &learningEngine, CTradingJournal &journal);
   int    CreateProfile(string name, const ParameterSet &baseParams);
   bool   DeleteProfile(int profileId);
   bool   PromoteProfile(int profileId);
   bool   RetireProfile(int profileId);
   bool   RevertToProfile(int profileId);
   int    GetActiveProfileId() { return m_activeProfileId; }
   bool   SetActiveProfile(int profileId);
   bool   SetProfileParam(int profileId, string paramName, double value);
   int    GetProfileCount() { return m_profileCount; }
   int    GetProfileByIndex(int index, ParameterSet &ps);
   bool   GetProfileById(int profileId, ParameterSet &ps);
   bool   UpdateAllProfileScores();
   int    GetBestProfileId();
   int    GetWorstProfileId();
   string GetProfileSummary();
   bool   SaveProfiles();
   bool   LoadProfiles();
};

//--- Constructor
CStrategyEvolution::CStrategyEvolution()
{
   m_profileCount = 0;
   m_activeProfileId = 1;
   m_learningEngine = NULL;
   m_journal = NULL;

   for(int i = 0; i < MAX_PROFILES; i++)
   {
      CreateDefaultParameterSet(m_profiles[i], 0);
      m_profiles[i].status = PROFILE_BACKUP;
   }
}

//--- Destructor
CStrategyEvolution::~CStrategyEvolution()
{
}

//--- Initialize
bool CStrategyEvolution::Init(CLearningEngine &learningEngine, CTradingJournal &journal)
{
   m_learningEngine = GetPointer(learningEngine);
   m_journal = GetPointer(journal);

   // Create default profile if none exists
   if(m_profileCount == 0)
   {
      CreateDefaultParameterSet(m_profiles[0], 1);
      m_profileCount = 1;
      m_activeProfileId = 1;
   }

   return true;
}

//--- Find the array index for a given profile ID
int CStrategyEvolution::FindProfileIndex(int profileId)
{
   for(int i = 0; i < m_profileCount; i++)
   {
      if(m_profiles[i].id == profileId)
         return i;
   }
   return -1;
}

//--- Calculate a profile score (0-100)
double CStrategyEvolution::CalculateProfileScore(const ParameterSet &ps)
{
   if(ps.totalTrades < 5)
      return 50.0; // Not enough data — neutral score

   double score = 50.0;

   // Win rate component (up to 20 points)
   double winRate = 0.0;
   if(ps.totalTrades > 0)
      winRate = (double)ps.wins / (double)ps.totalTrades * 100.0;
   score += (winRate - 50.0) * 0.4; // +/- 20 points

   // Profit factor component (up to 15 points)
   if(ps.profitFactor > 0.0)
   {
      if(ps.profitFactor > 2.0)
         score += 15.0;
      else
         score += (ps.profitFactor - 1.0) * 15.0;
   }

   // Expectancy component (up to 15 points)
   if(ps.totalTrades > 0)
   {
      double expectancy = ps.totalProfit / (double)ps.totalTrades;
      score += MathMin(MathAbs(expectancy) * 10.0, 15.0);
      if(expectancy < 0.0) score -= MathMin(MathAbs(expectancy) * 10.0, 15.0);
   }

   // Clamp to 0-100
   if(score < 0.0)   score = 0.0;
   if(score > 100.0) score = 100.0;

   return score;
}

//--- Update metrics for a profile from journal data
void CStrategyEvolution::UpdateProfileMetrics(ParameterSet &ps)
{
   if(m_learningEngine == NULL) return;

   ps.totalTrades = m_learningEngine.GetTradeCount(ps.id);

   JournalEntry entries[];
   int count = 0;
   if(m_journal != NULL)
      m_journal.ReadEntriesByProfile(ps.id, entries, count);

   ps.wins = 0;
   ps.losses = 0;
   ps.totalProfit = 0.0;
   double grossProfit = 0.0;
   double grossLoss = 0.0;
   double totalRR = 0.0;
   int rrCount = 0;

   for(int i = 0; i < count; i++)
   {
      if(entries[i].outcome == OUTCOME_WIN) ps.wins++;
      else if(entries[i].outcome == OUTCOME_LOSS) ps.losses++;

      ps.totalProfit += entries[i].profit;
      if(entries[i].profit > 0.0) grossProfit += entries[i].profit;
      else grossLoss += MathAbs(entries[i].profit);

      if(entries[i].riskRewardRatio > 0.0)
      {
         totalRR += entries[i].riskRewardRatio;
         rrCount++;
      }
   }

   if(grossLoss > 0.0)
      ps.profitFactor = grossProfit / grossLoss;
   else
      ps.profitFactor = (grossProfit > 0.0) ? 99.0 : 0.0;

   if(rrCount > 0)
      ps.avgRiskReward = totalRR / (double)rrCount;
   else
      ps.avgRiskReward = 0.0;

   ps.score = CalculateProfileScore(ps);
   ps.lastUpdated = TimeCurrent();
}

//--- Create a new profile
int CStrategyEvolution::CreateProfile(string name, const ParameterSet &baseParams)
{
   if(m_profileCount >= MAX_PROFILES)
      return -1;

   // Find the next available ID
   int newId = 1;
   for(int i = 0; i < m_profileCount; i++)
   {
      if(m_profiles[i].id >= newId)
         newId = m_profiles[i].id + 1;
   }

   CloneParameterSet(baseParams, m_profiles[m_profileCount], newId, name);
   m_profileCount++;

   Print("[Evolution] Created profile '", name, "' with ID ", newId);
   return newId;
}

//--- Delete a profile (only if not active)
bool CStrategyEvolution::DeleteProfile(int profileId)
{
   if(profileId == m_activeProfileId)
   {
      Print("[Evolution] Cannot delete the active profile.");
      return false;
   }

   int idx = FindProfileIndex(profileId);
   if(idx < 0) return false;

   // Shift remaining profiles
   for(int i = idx; i < m_profileCount - 1; i++)
   {
      m_profiles[i] = m_profiles[i + 1];
   }
   m_profileCount--;

   Print("[Evolution] Deleted profile ID ", profileId);
   return true;
}

//--- Promote a profile to active status
bool CStrategyEvolution::PromoteProfile(int profileId)
{
   int idx = FindProfileIndex(profileId);
   if(idx < 0) return false;

   // Mark current active as backup
   int currentIdx = FindProfileIndex(m_activeProfileId);
   if(currentIdx >= 0)
   {
      m_profiles[currentIdx].status = PROFILE_BACKUP;
   }

   m_profiles[idx].status = PROFILE_PROMOTED;
   m_activeProfileId = profileId;

   Print("[Evolution] Promoted profile '", m_profiles[idx].name, "' (ID: ", profileId, ") to active.");
   return true;
}

//--- Retire a profile (stop using it)
bool CStrategyEvolution::RetireProfile(int profileId)
{
   int idx = FindProfileIndex(profileId);
   if(idx < 0) return false;

   if(profileId == m_activeProfileId)
   {
      Print("[Evolution] Cannot retire the active profile. Switch first.");
      return false;
   }

   m_profiles[idx].status = PROFILE_RETIRED;
   Print("[Evolution] Retired profile '", m_profiles[idx].name, "' (ID: ", profileId, ").");
   return true;
}

//--- Revert to a previous profile (rollback)
bool CStrategyEvolution::RevertToProfile(int profileId)
{
   int idx = FindProfileIndex(profileId);
   if(idx < 0)
   {
      Print("[Evolution] Profile ID ", profileId, " not found for rollback.");
      return false;
   }

   // Current profile becomes backup
   int currentIdx = FindProfileIndex(m_activeProfileId);
   if(currentIdx >= 0)
   {
      m_profiles[currentIdx].status = PROFILE_BACKUP;
   }

   m_profiles[idx].status = PROFILE_ACTIVE;
   m_activeProfileId = profileId;

   Print("[Evolution] Reverted to profile '", m_profiles[idx].name, "' (ID: ", profileId, ").");
   return true;
}

//--- Set active profile directly
bool CStrategyEvolution::SetActiveProfile(int profileId)
{
   int idx = FindProfileIndex(profileId);
   if(idx < 0) return false;

   // Mark current as backup
   int currentIdx = FindProfileIndex(m_activeProfileId);
   if(currentIdx >= 0)
      m_profiles[currentIdx].status = PROFILE_BACKUP;

   m_profiles[idx].status = PROFILE_ACTIVE;
   m_activeProfileId = profileId;
   return true;
}

//--- Get a profile by array index
int CStrategyEvolution::GetProfileByIndex(int index, ParameterSet &ps)
{
   if(index < 0 || index >= m_profileCount)
      return -1;
   ps = m_profiles[index];
   return m_profiles[index].id;
}

//--- Get a profile by ID
bool CStrategyEvolution::GetProfileById(int profileId, ParameterSet &ps)
{
   int idx = FindProfileIndex(profileId);
   if(idx < 0) return false;
   ps = m_profiles[idx];
   return true;
}

//--- Update all profile scores
bool CStrategyEvolution::UpdateAllProfileScores()
{
   for(int i = 0; i < m_profileCount; i++)
   {
      UpdateProfileMetrics(m_profiles[i]);
   }
   return true;
}

//--- Get best performing profile ID
int CStrategyEvolution::GetBestProfileId()
{
   int bestId = m_activeProfileId;
   double bestScore = -1.0;

   for(int i = 0; i < m_profileCount; i++)
   {
      if(m_profiles[i].totalTrades >= 5 && m_profiles[i].score > bestScore)
      {
         bestScore = m_profiles[i].score;
         bestId = m_profiles[i].id;
      }
   }

   return bestId;
}

//--- Get worst performing profile ID
int CStrategyEvolution::GetWorstProfileId()
{
   int worstId = -1;
   double worstScore = 101.0;

   for(int i = 0; i < m_profileCount; i++)
   {
      if(m_profiles[i].totalTrades >= 5 && m_profiles[i].score < worstScore)
      {
         worstScore = m_profiles[i].score;
         worstId = m_profiles[i].id;
      }
   }

   return worstId;
}

//--- Get a summary of all profiles
string CStrategyEvolution::GetProfileSummary()
{
   string summary = "=== Strategy Profiles ===\n";

   for(int i = 0; i < m_profileCount; i++)
   {
      string statusStr;
      switch(m_profiles[i].status)
      {
         case PROFILE_ACTIVE:   statusStr = "ACTIVE";   break;
         case PROFILE_PROMOTED: statusStr = "PROMOTED"; break;
         case PROFILE_RETIRED:   statusStr = "RETIRED";  break;
         case PROFILE_BACKUP:   statusStr = "BACKUP";   break;
         default:               statusStr = "UNKNOWN";  break;
      }

      string active = (m_profiles[i].id == m_activeProfileId) ? " <== ACTIVE" : "";

      summary += StringFormat("ID:%d  %-20s  Score:%.1f  Trades:%d  WinRate:%.1f%%  PF:%.2f  [%s]%s\n",
         m_profiles[i].id, m_profiles[i].name, m_profiles[i].score,
         m_profiles[i].totalTrades,
         (m_profiles[i].totalTrades > 0 ? (double)m_profiles[i].wins / (double)m_profiles[i].totalTrades * 100.0 : 0.0),
         m_profiles[i].profitFactor, statusStr, active);
   }

   return summary;
}

//--- Save profiles to file
bool CStrategyEvolution::SaveProfiles()
{
   string fileName = "AIEA_Trader\\profiles.csv";
   int handle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');

   if(handle == INVALID_HANDLE)
   {
      Print("[Evolution] Failed to save profiles: ", GetLastError());
      return false;
   }

   for(int i = 0; i < m_profileCount; i++)
   {
      FileWrite(handle,
         (string)m_profiles[i].id,
         m_profiles[i].name,
         (string)m_profiles[i].rsiPeriod,
         (string)m_profiles[i].maFastPeriod,
         (string)m_profiles[i].maSlowPeriod,
         (string)m_profiles[i].bbPeriod,
         DoubleToString(m_profiles[i].bbDeviation, 2),
         (string)m_profiles[i].macdFast,
         (string)m_profiles[i].macdSlow,
         (string)m_profiles[i].macdSignal,
         (string)m_profiles[i].stochK,
         (string)m_profiles[i].stochD,
         (string)m_profiles[i].stochSlow,
         DoubleToString(m_profiles[i].atrMultiplier, 2),
         (string)m_profiles[i].atrPeriod,
         DoubleToString(m_profiles[i].stopLossDistance, 2),
         DoubleToString(m_profiles[i].takeProfitDistance, 2),
         DoubleToString(m_profiles[i].trailingStop, 2),
         DoubleToString(m_profiles[i].breakEvenTrigger, 2),
         DoubleToString(m_profiles[i].positionSizePercent, 2),
         (string)m_profiles[i].tradingStartHour,
         (string)m_profiles[i].tradingEndHour,
         (m_profiles[i].newsFilter ? "1" : "0"),
         (m_profiles[i].volatilityFilter ? "1" : "0"),
         DoubleToString(m_profiles[i].maxSpreadPoints, 1),
         DoubleToString(m_profiles[i].minConfidence, 1),
         DoubleToString(m_profiles[i].maxDailyLossPercent, 1),
         (string)m_profiles[i].maxOpenPositions,
         DoubleToString(m_profiles[i].maxDrawdownPercent, 1),
         (string)m_profiles[i].totalTrades,
         (string)m_profiles[i].wins,
         (string)m_profiles[i].losses,
         DoubleToString(m_profiles[i].totalProfit, 2),
         DoubleToString(m_profiles[i].profitFactor, 2),
         DoubleToString(m_profiles[i].avgRiskReward, 2),
         DoubleToString(m_profiles[i].score, 1),
         (string)m_profiles[i].status,
         (string)m_profiles[i].created,
         (string)m_profiles[i].lastUpdated
      );
   }

   FileClose(handle);
   Print("[Evolution] Saved ", m_profileCount, " profiles.");
   return true;
}

//--- Load profiles from file
bool CStrategyEvolution::LoadProfiles()
{
   string fileName = "AIEA_Trader\\profiles.csv";

   if(!FileIsExist(fileName, 0))
   {
      Print("[Evolution] No saved profiles found. Using default.");
      return false;
   }

   int handle = FileOpen(fileName, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   m_profileCount = 0;

   while(!FileIsEnding(handle) && m_profileCount < MAX_PROFILES)
   {
      string idStr = FileReadString(handle);
      if(idStr == "") break;

      m_profiles[m_profileCount].id                  = (int)StringToInteger(idStr);
      m_profiles[m_profileCount].name                = FileReadString(handle);
      m_profiles[m_profileCount].rsiPeriod           = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].maFastPeriod        = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].maSlowPeriod        = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].bbPeriod            = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].bbDeviation         = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].macdFast            = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].macdSlow            = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].macdSignal          = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].stochK              = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].stochD              = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].stochSlow           = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].atrMultiplier       = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].atrPeriod           = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].stopLossDistance    = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].takeProfitDistance  = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].trailingStop       = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].breakEvenTrigger   = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].positionSizePercent = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].tradingStartHour    = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].tradingEndHour      = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].newsFilter          = (FileReadString(handle) == "1");
      m_profiles[m_profileCount].volatilityFilter    = (FileReadString(handle) == "1");
      m_profiles[m_profileCount].maxSpreadPoints      = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].minConfidence       = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].maxDailyLossPercent = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].maxOpenPositions   = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].maxDrawdownPercent  = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].totalTrades         = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].wins                = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].losses              = (int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].totalProfit         = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].profitFactor        = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].avgRiskReward       = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].score               = StringToDouble(FileReadString(handle));
      m_profiles[m_profileCount].status              = (ENUM_PROFILE_STATUS)(int)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].created              = (datetime)StringToInteger(FileReadString(handle));
      m_profiles[m_profileCount].lastUpdated          = (datetime)StringToInteger(FileReadString(handle));

      m_profileCount++;
   }

   FileClose(handle);

   // Set active profile to the first active/promoted profile
   for(int i = 0; i < m_profileCount; i++)
   {
      if(m_profiles[i].status == PROFILE_ACTIVE || m_profiles[i].status == PROFILE_PROMOTED)
      {
         m_activeProfileId = m_profiles[i].id;
         break;
      }
   }

   if(m_profileCount > 0)
   {
      Print("[Evolution] Loaded ", m_profileCount, " profiles. Active: ", m_activeProfileId);
      return true;
   }

   return false;
}

//--- Set a single parameter in a profile by name
bool CStrategyEvolution::SetProfileParam(int profileId, string paramName, double value)
{
   int idx = FindProfileIndex(profileId);
   if(idx < 0) return false;

   if(paramName == "rsiPeriod")              m_profiles[idx].rsiPeriod = (int)value;
   else if(paramName == "maFastPeriod")       m_profiles[idx].maFastPeriod = (int)value;
   else if(paramName == "maSlowPeriod")       m_profiles[idx].maSlowPeriod = (int)value;
   else if(paramName == "bbPeriod")           m_profiles[idx].bbPeriod = (int)value;
   else if(paramName == "bbDeviation")        m_profiles[idx].bbDeviation = value;
   else if(paramName == "macdFast")           m_profiles[idx].macdFast = (int)value;
   else if(paramName == "macdSlow")           m_profiles[idx].macdSlow = (int)value;
   else if(paramName == "macdSignal")         m_profiles[idx].macdSignal = (int)value;
   else if(paramName == "stochK")             m_profiles[idx].stochK = (int)value;
   else if(paramName == "stochD")             m_profiles[idx].stochD = (int)value;
   else if(paramName == "stochSlow")          m_profiles[idx].stochSlow = (int)value;
   else if(paramName == "atrMultiplier")      m_profiles[idx].atrMultiplier = value;
   else if(paramName == "atrPeriod")          m_profiles[idx].atrPeriod = (int)value;
   else if(paramName == "stopLossDistance")   m_profiles[idx].stopLossDistance = value;
   else if(paramName == "takeProfitDistance") m_profiles[idx].takeProfitDistance = value;
   else if(paramName == "trailingStop")       m_profiles[idx].trailingStop = value;
   else if(paramName == "breakEvenTrigger")   m_profiles[idx].breakEvenTrigger = value;
   else if(paramName == "positionSizePercent") m_profiles[idx].positionSizePercent = value;
   else if(paramName == "tradingStartHour")   m_profiles[idx].tradingStartHour = (int)value;
   else if(paramName == "tradingEndHour")     m_profiles[idx].tradingEndHour = (int)value;
   else if(paramName == "maxSpreadPoints")    m_profiles[idx].maxSpreadPoints = value;
   else if(paramName == "minConfidence")      m_profiles[idx].minConfidence = value;
   else if(paramName == "maxDailyLossPercent") m_profiles[idx].maxDailyLossPercent = value;
   else if(paramName == "maxOpenPositions")   m_profiles[idx].maxOpenPositions = (int)value;
   else if(paramName == "maxDrawdownPercent") m_profiles[idx].maxDrawdownPercent = value;
   else return false;

   m_profiles[idx].lastUpdated = TimeCurrent();
   return true;
}

#endif // AIEA_STRATEGY_EVOLUTION_MQH
//+------------------------------------------------------------------+
