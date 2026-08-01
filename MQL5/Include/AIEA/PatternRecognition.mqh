//+------------------------------------------------------------------+
//| PatternRecognition.mqh — Identify & Rank Trading Patterns        |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_PATTERN_RECOGNITION_MQH
#define AIEA_PATTERN_RECOGNITION_MQH

#include "Config.mqh"
#include "TradingJournal.mqh"

//==================================================================
//  PATTERN RECOGNITION CLASS
//==================================================================

class CPatternRecognition
{
private:
   CTradingJournal  *m_journal;
   int               m_maxPatterns;

   void  AddOrUpdatePattern(PatternStat &patterns[], int &count,
                            string category, string condition,
                            double profit, bool isWin);
   void  SortPatternsByScore(PatternStat &patterns[], int count);
   void  SortPatternsByProfit(PatternStat &patterns[], int count);
   int   FindPattern(PatternStat &patterns[], int count,
                     string category, string condition);

public:
   CPatternRecognition();
   ~CPatternRecognition();

   bool   Init(CTradingJournal &journal, int maxPatterns = 100);

   // Pattern analysis
   bool   AnalyzeAllPatterns(PatternStat &bestPatterns, int &bestCount,
                            PatternStat &worstPatterns, int &worstCount);
   bool   AnalyzeBySymbol(PatternStat &patterns, int &count);
   bool   AnalyzeBySession(PatternStat &patterns, int &count);
   bool   AnalyzeByWeekday(PatternStat &patterns, int &count);
   bool   AnalyzeByRegime(PatternStat &patterns, int &count);
   bool   AnalyzeByIndicatorCombo(PatternStat &patterns, int &count);

   // Convenience queries
   string GetBestSymbol();
   string GetWorstSymbol();
   string GetBestSession();
   string GetWorstSession();
   string GetBestRegime();
   string GetWorstRegime();
   string GetMostProfitableSetup();
   string GetMostCommonLosingSetup();
   string GetHighestRiskScenario();
};

//--- Constructor
CPatternRecognition::CPatternRecognition()
{
   m_journal = NULL;
   m_maxPatterns = 100;
}

//--- Destructor
CPatternRecognition::~CPatternRecognition()
{
}

//--- Initialize
bool CPatternRecognition::Init(CTradingJournal &journal, int maxPatterns)
{
   m_journal = GetPointer(journal);
   m_maxPatterns = maxPatterns;
   return true;
}

//--- Find a pattern in the array
int CPatternRecognition::FindPattern(PatternStat &patterns[], int count,
                                     string category, string condition)
{
   for(int i = 0; i < count; i++)
   {
      if(patterns[i].category == category && patterns[i].condition == condition)
         return i;
   }
   return -1;
}

//--- Add or update a pattern
void CPatternRecognition::AddOrUpdatePattern(PatternStat &patterns[], int &count,
                                             string category, string condition,
                                             double profit, bool isWin)
{
   int idx = FindPattern(patterns, count, category, condition);

   if(idx >= 0)
   {
      patterns[idx].trades++;
      patterns[idx].totalProfit += profit;
      if(isWin) patterns[idx].wins++;
      else if(profit < 0.0) patterns[idx].losses++;
   }
   else
   {
      ArrayResize(patterns, count + 1);
      InitPatternStat(patterns[count]);
      patterns[count].category      = category;
      patterns[count].condition     = condition;
      patterns[count].trades        = 1;
      patterns[count].totalProfit   = profit;
      if(isWin) patterns[count].wins = 1;
      else if(profit < 0.0) patterns[count].losses = 1;
      count++;
   }
}

//--- Sort patterns by score descending
void CPatternRecognition::SortPatternsByScore(PatternStat &patterns[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(patterns[j].score > patterns[i].score)
         {
            PatternStat temp = patterns[i];
            patterns[i] = patterns[j];
            patterns[j] = temp;
         }
      }
   }
}

//--- Sort patterns by profit descending
void CPatternRecognition::SortPatternsByProfit(PatternStat &patterns[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(patterns[j].totalProfit > patterns[i].totalProfit)
         {
            PatternStat temp = patterns[i];
            patterns[i] = patterns[j];
            patterns[j] = temp;
         }
      }
   }
}

//--- Analyze all patterns and rank best/worst
bool CPatternRecognition::AnalyzeAllPatterns(PatternStat &bestPatterns, int &bestCount,
                                             PatternStat &worstPatterns, int &worstCount)
{
   PatternStat allPatterns[];
   int totalCount = 0;

   // Combine all category analyses
   PatternStat symPatterns[];
   int symCount = 0;
   AnalyzeBySymbol(symPatterns, symCount);
   for(int i = 0; i < symCount; i++)
   {
      ArrayResize(allPatterns, totalCount + 1);
      allPatterns[totalCount] = symPatterns[i];
      totalCount++;
   }

   PatternStat sessPatterns[];
   int sessCount = 0;
   AnalyzeBySession(sessPatterns, sessCount);
   for(int i = 0; i < sessCount; i++)
   {
      ArrayResize(allPatterns, totalCount + 1);
      allPatterns[totalCount] = sessPatterns[i];
      totalCount++;
   }

   PatternStat dayPatterns[];
   int dayCount = 0;
   AnalyzeByWeekday(dayPatterns, dayCount);
   for(int i = 0; i < dayCount; i++)
   {
      ArrayResize(allPatterns, totalCount + 1);
      allPatterns[totalCount] = dayPatterns[i];
      totalCount++;
   }

   PatternStat regPatterns[];
   int regCount = 0;
   AnalyzeByRegime(regPatterns, regCount);
   for(int i = 0; i < regCount; i++)
   {
      ArrayResize(allPatterns, totalCount + 1);
      allPatterns[totalCount] = regPatterns[i];
      totalCount++;
   }

   // Calculate scores and win rates
   for(int i = 0; i < totalCount; i++)
   {
      if(allPatterns[i].trades > 0)
      {
         allPatterns[i].winRate = (double)allPatterns[i].wins / (double)allPatterns[i].trades * 100.0;
         allPatterns[i].avgProfit = allPatterns[i].totalProfit / (double)allPatterns[i].trades;

         // Score: weighted combination of win rate and profitability
         allPatterns[i].score = allPatterns[i].winRate * 0.5 +
                                (allPatterns[i].avgProfit > 0 ? 25.0 : 0.0) +
                                MathMin(MathAbs(allPatterns[i].avgProfit) * 10.0, 25.0);
      }
   }

   // Sort by score
   SortPatternsByScore(allPatterns, totalCount);

   // Top half = best, bottom half = worst
   bestCount = 0;
   worstCount = 0;
   int halfCount = totalCount / 2;
   if(halfCount < 1) halfCount = 1;

   for(int i = 0; i < halfCount && i < totalCount; i++)
   {
      ArrayResize(bestPatterns, bestCount + 1);
      bestPatterns[bestCount] = allPatterns[i];
      bestCount++;
   }

   for(int i = totalCount - 1; i >= totalCount - halfCount && i >= 0; i--)
   {
      ArrayResize(worstPatterns, worstCount + 1);
      worstPatterns[worstCount] = allPatterns[i];
      worstCount++;
   }

   return true;
}

//--- Analyze performance by symbol
bool CPatternRecognition::AnalyzeBySymbol(PatternStat &patterns, int &count)
{
   count = 0;
   JournalEntry entries[];
   int entryCount = 0;

   if(m_journal == NULL) return false;
   m_journal.ReadAllEntries(entries, entryCount);

   for(int i = 0; i < entryCount; i++)
   {
      bool isWin = (entries[i].outcome == OUTCOME_WIN);
      AddOrUpdatePattern(patterns, count, "symbol", entries[i].symbol,
                         entries[i].profit, isWin);
   }

   // Finalize scores
   for(int i = 0; i < count; i++)
   {
      if(patterns[i].trades > 0)
      {
         patterns[i].winRate = (double)patterns[i].wins / (double)patterns[i].trades * 100.0;
         patterns[i].avgProfit = patterns[i].totalProfit / (double)patterns[i].trades;
         patterns[i].score = patterns[i].winRate * 0.5 +
                              (patterns[i].avgProfit > 0 ? 25.0 : 0.0) +
                              MathMin(MathAbs(patterns[i].avgProfit) * 10.0, 25.0);
      }
   }

   SortPatternsByScore(patterns, count);
   return true;
}

//--- Analyze performance by session
bool CPatternRecognition::AnalyzeBySession(PatternStat &patterns, int &count)
{
   count = 0;
   JournalEntry entries[];
   int entryCount = 0;

   if(m_journal == NULL) return false;
   m_journal.ReadAllEntries(entries, entryCount);

   for(int i = 0; i < entryCount; i++)
   {
      bool isWin = (entries[i].outcome == OUTCOME_WIN);
      AddOrUpdatePattern(patterns, count, "session", entries[i].session,
                         entries[i].profit, isWin);
   }

   for(int i = 0; i < count; i++)
   {
      if(patterns[i].trades > 0)
      {
         patterns[i].winRate = (double)patterns[i].wins / (double)patterns[i].trades * 100.0;
         patterns[i].avgProfit = patterns[i].totalProfit / (double)patterns[i].trades;
         patterns[i].score = patterns[i].winRate * 0.5 +
                              (patterns[i].avgProfit > 0 ? 25.0 : 0.0) +
                              MathMin(MathAbs(patterns[i].avgProfit) * 10.0, 25.0);
      }
   }

   SortPatternsByScore(patterns, count);
   return true;
}

//--- Analyze performance by weekday
bool CPatternRecognition::AnalyzeByWeekday(PatternStat &patterns, int &count)
{
   count = 0;
   JournalEntry entries[];
   int entryCount = 0;

   if(m_journal == NULL) return false;
   m_journal.ReadAllEntries(entries, entryCount);

   string dayNames[] = {"Sunday", "Monday", "Tuesday", "Wednesday",
                        "Thursday", "Friday", "Saturday"};

   for(int i = 0; i < entryCount; i++)
   {
      bool isWin = (entries[i].outcome == OUTCOME_WIN);
      string dayName = "Unknown";
      if(entries[i].weekday >= 0 && entries[i].weekday <= 6)
         dayName = dayNames[entries[i].weekday];
      AddOrUpdatePattern(patterns, count, "weekday", dayName,
                         entries[i].profit, isWin);
   }

   for(int i = 0; i < count; i++)
   {
      if(patterns[i].trades > 0)
      {
         patterns[i].winRate = (double)patterns[i].wins / (double)patterns[i].trades * 100.0;
         patterns[i].avgProfit = patterns[i].totalProfit / (double)patterns[i].trades;
         patterns[i].score = patterns[i].winRate * 0.5 +
                              (patterns[i].avgProfit > 0 ? 25.0 : 0.0) +
                              MathMin(MathAbs(patterns[i].avgProfit) * 10.0, 25.0);
      }
   }

   SortPatternsByScore(patterns, count);
   return true;
}

//--- Analyze performance by market regime
bool CPatternRecognition::AnalyzeByRegime(PatternStat &patterns, int &count)
{
   count = 0;
   JournalEntry entries[];
   int entryCount = 0;

   if(m_journal == NULL) return false;
   m_journal.ReadAllEntries(entries, entryCount);

   for(int i = 0; i < entryCount; i++)
   {
      bool isWin = (entries[i].outcome == OUTCOME_WIN);
      string regimeName = "Unknown";
      switch(entries[i].regime)
      {
         case REGIME_TRENDING: regimeName = "Trending"; break;
         case REGIME_RANGING:  regimeName = "Ranging";  break;
         case REGIME_VOLATILE: regimeName = "Volatile"; break;
         default: regimeName = "Unknown"; break;
      }
      AddOrUpdatePattern(patterns, count, "regime", regimeName,
                         entries[i].profit, isWin);
   }

   for(int i = 0; i < count; i++)
   {
      if(patterns[i].trades > 0)
      {
         patterns[i].winRate = (double)patterns[i].wins / (double)patterns[i].trades * 100.0;
         patterns[i].avgProfit = patterns[i].totalProfit / (double)patterns[i].trades;
         patterns[i].score = patterns[i].winRate * 0.5 +
                              (patterns[i].avgProfit > 0 ? 25.0 : 0.0) +
                              MathMin(MathAbs(patterns[i].avgProfit) * 10.0, 25.0);
      }
   }

   SortPatternsByScore(patterns, count);
   return true;
}

//--- Analyze performance by indicator combination
bool CPatternRecognition::AnalyzeByIndicatorCombo(PatternStat &patterns, int &count)
{
   count = 0;
   JournalEntry entries[];
   int entryCount = 0;

   if(m_journal == NULL) return false;
   m_journal.ReadAllEntries(entries, entryCount);

   for(int i = 0; i < entryCount; i++)
   {
      bool isWin = (entries[i].outcome == OUTCOME_WIN);

      // Create indicator combo signature
      string combo = "";
      // RSI zone
      if(entries[i].rsiAtEntry < 30.0) combo += "RSI_Oversold";
      else if(entries[i].rsiAtEntry > 70.0) combo += "RSI_Overbought";
      else combo += "RSI_Neutral";

      // MA alignment
      if(entries[i].maFastAtEntry > entries[i].maSlowAtEntry) combo += "+MA_Bull";
      else combo += "+MA_Bear";

      // MACD
      if(entries[i].macdMainAtEntry > entries[i].macdSignalAtEntry) combo += "+MACD_Bull";
      else combo += "+MACD_Bear";

      // Stochastic
      if(entries[i].stochMainAtEntry < 20.0) combo += "+Stoch_OS";
      else if(entries[i].stochMainAtEntry > 80.0) combo += "+Stoch_OB";
      else combo += "+Stoch_Neutral";

      AddOrUpdatePattern(patterns, count, "indicator_combo", combo,
                         entries[i].profit, isWin);
   }

   for(int i = 0; i < count; i++)
   {
      if(patterns[i].trades > 0)
      {
         patterns[i].winRate = (double)patterns[i].wins / (double)patterns[i].trades * 100.0;
         patterns[i].avgProfit = patterns[i].totalProfit / (double)patterns[i].trades;
         patterns[i].score = patterns[i].winRate * 0.5 +
                              (patterns[i].avgProfit > 0 ? 25.0 : 0.0) +
                              MathMin(MathAbs(patterns[i].avgProfit) * 10.0, 25.0);
      }
   }

   SortPatternsByScore(patterns, count);
   return true;
}

//--- Get best performing symbol
string CPatternRecognition::GetBestSymbol()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeBySymbol(patterns, count);
   if(count > 0) return patterns[0].condition;
   return "N/A";
}

//--- Get worst performing symbol
string CPatternRecognition::GetWorstSymbol()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeBySymbol(patterns, count);
   if(count > 0) return patterns[count - 1].condition;
   return "N/A";
}

//--- Get best session
string CPatternRecognition::GetBestSession()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeBySession(patterns, count);
   if(count > 0) return patterns[0].condition;
   return "N/A";
}

//--- Get worst session
string CPatternRecognition::GetWorstSession()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeBySession(patterns, count);
   if(count > 0) return patterns[count - 1].condition;
   return "N/A";
}

//--- Get best regime
string CPatternRecognition::GetBestRegime()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeByRegime(patterns, count);
   if(count > 0) return patterns[0].condition;
   return "N/A";
}

//--- Get worst regime
string CPatternRecognition::GetWorstRegime()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeByRegime(patterns, count);
   if(count > 0) return patterns[count - 1].condition;
   return "N/A";
}

//--- Get most profitable setup description
string CPatternRecognition::GetMostProfitableSetup()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeByIndicatorCombo(patterns, count);
   if(count > 0)
   {
      return StringFormat("%s (trades: %d, win rate: %.1f%%, profit: %.2f)",
         patterns[0].condition, patterns[0].trades, patterns[0].winRate,
         patterns[0].totalProfit);
   }
   return "N/A";
}

//--- Get most common losing setup
string CPatternRecognition::GetMostCommonLosingSetup()
{
   PatternStat patterns[];
   int count = 0;
   AnalyzeByIndicatorCombo(patterns, count);

   // Find the one with the most losses
   int worstIdx = -1;
   int maxLosses = 0;
   for(int i = 0; i < count; i++)
   {
      if(patterns[i].losses > maxLosses)
      {
         maxLosses = patterns[i].losses;
         worstIdx = i;
      }
   }

   if(worstIdx >= 0)
   {
      return StringFormat("%s (losses: %d, win rate: %.1f%%, profit: %.2f)",
         patterns[worstIdx].condition, patterns[worstIdx].losses,
         patterns[worstIdx].winRate, patterns[worstIdx].totalProfit);
   }
   return "N/A";
}

//--- Get highest risk scenario
string CPatternRecognition::GetHighestRiskScenario()
{
   JournalEntry entries[];
   int entryCount = 0;

   if(m_journal == NULL) return "N/A";
   m_journal.ReadAllEntries(entries, entryCount);

   int worstIdx = -1;
   double worstMAE = 0.0;

   for(int i = 0; i < entryCount; i++)
   {
      if(entries[i].mae > worstMAE)
      {
         worstMAE = entries[i].mae;
         worstIdx = i;
      }
   }

   if(worstIdx >= 0)
   {
      string regimeStr = "Unknown";
      switch(entries[worstIdx].regime)
      {
         case REGIME_TRENDING: regimeStr = "Trending"; break;
         case REGIME_RANGING:  regimeStr = "Ranging";  break;
         case REGIME_VOLATILE: regimeStr = "Volatile"; break;
      }
      return StringFormat("%s %s session, MAE: %.1f pts, regime: %s",
         entries[worstIdx].symbol, entries[worstIdx].session,
         entries[worstIdx].mae, regimeStr);
   }
   return "N/A";
}

#endif // AIEA_PATTERN_RECOGNITION_MQH
//+------------------------------------------------------------------+
