//+------------------------------------------------------------------+
//| ReportGenerator.mqh — Daily, Weekly & Monthly Reports            |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_REPORT_GENERATOR_MQH
#define AIEA_REPORT_GENERATOR_MQH

#include "Config.mqh"
#include "TradingJournal.mqh"
#include "LearningEngine.mqh"
#include "StrategyEvolution.mqh"
#include "PatternRecognition.mqh"
#include "OptimizationEngine.mqh"

//==================================================================
//  REPORT GENERATOR CLASS
//==================================================================

class CReportGenerator
{
private:
   CTradingJournal     *m_journal;
   CLearningEngine      *m_learningEngine;
   CStrategyEvolution   *m_evolution;
   CPatternRecognition  *m_patternRecognition;
   COptimizationEngine  *m_optimizationEngine;
   string               m_folder;

   bool   GenerateReport(ReportData &rd, datetime startTime, datetime endTime,
                         string periodType);
   bool   WriteReportToFile(const ReportData &rd);
   double CalculateMaxDrawdown(datetime startTime, datetime endTime);
   void   PopulateFromJournal(ReportData &rd, datetime startTime, datetime endTime);

public:
   CReportGenerator();
   ~CReportGenerator();

   bool   Init(CTradingJournal &journal, CLearningEngine &learningEngine,
               CStrategyEvolution &evolution, CPatternRecognition &patternRecognition,
               COptimizationEngine &optimizationEngine);
   bool   GenerateDailyReport();
   bool   GenerateWeeklyReport();
   bool   GenerateMonthlyReport();
   string GetDailyReportString();
   string GetWeeklyReportString();
   string GetMonthlyReportString();
   string FormatReport(const ReportData &rd);
};

//--- Constructor
CReportGenerator::CReportGenerator()
{
   m_journal = NULL;
   m_learningEngine = NULL;
   m_evolution = NULL;
   m_patternRecognition = NULL;
   m_optimizationEngine = NULL;
   m_folder = "AIEA_Trader";
}

//--- Destructor
CReportGenerator::~CReportGenerator()
{
}

//--- Initialize
bool CReportGenerator::Init(CTradingJournal &journal, CLearningEngine &learningEngine,
                             CStrategyEvolution &evolution,
                             CPatternRecognition &patternRecognition,
                             COptimizationEngine &optimizationEngine)
{
   m_journal = GetPointer(journal);
   m_learningEngine = GetPointer(learningEngine);
   m_evolution = GetPointer(evolution);
   m_patternRecognition = GetPointer(patternRecognition);
   m_optimizationEngine = GetPointer(optimizationEngine);
   return true;
}

//--- Generate a report for a time period
bool CReportGenerator::GenerateReport(ReportData &rd, datetime startTime,
                                        datetime endTime, string periodType)
{
   InitReportData(rd);
   rd.periodStart = startTime;
   rd.periodEnd   = endTime;
   rd.periodType  = periodType;

   PopulateFromJournal(rd, startTime, endTime);

   // Calculate metrics
   if(rd.totalTrades > 0)
   {
      rd.winRate = (double)rd.wins / (double)rd.totalTrades * 100.0;
      rd.expectancy = rd.netProfit / (double)rd.totalTrades;
   }

   if(rd.totalLoss > 0.0)
      rd.profitFactor = rd.totalProfit / rd.totalLoss;
   else
      rd.profitFactor = (rd.totalProfit > 0.0) ? 99.0 : 0.0;

   rd.maxDrawdown = CalculateMaxDrawdown(startTime, endTime);

   // Best/worst profiles
   if(m_evolution != NULL)
   {
      rd.bestProfileId = m_evolution.GetBestProfileId();
      rd.worstProfileId = m_evolution.GetWorstProfileId();
   }

   // Best/worst symbols
   if(m_patternRecognition != NULL)
   {
      rd.bestSymbol = m_patternRecognition.GetBestSymbol();
      rd.worstSymbol = m_patternRecognition.GetWorstSymbol();
   }

   // Parameter changes count
   if(m_optimizationEngine != NULL)
      rd.parameterChanges = m_optimizationEngine.GetChangeCount();

   // Learning summary
   rd.learningSummary = StringFormat(
      "%s report: %d trades, %.1f%% win rate, PF %.2f, expectancy %.2f, max DD %.1f%%",
      periodType, rd.totalTrades, rd.winRate, rd.profitFactor,
      rd.expectancy, rd.maxDrawdown);

   // Recommendations
   string recs = "";

   if(rd.winRate < 40.0)
      recs += "Consider raising confidence threshold. ";
   if(rd.profitFactor < 1.0)
      recs += "Strategy is not profitable — review entry conditions. ";
   if(rd.maxDrawdown > 15.0)
      recs += "High drawdown — consider reducing position size. ";
   if(rd.avgRiskReward < 1.0)
      recs += "Risk:reward is unfavorable — extend TP or tighten SL. ";
   if(recs == "")
      recs = "Performance is within acceptable parameters. Continue monitoring.";

   rd.recommendations = recs;

   return true;
}

//--- Populate report from journal entries within the time range
void CReportGenerator::PopulateFromJournal(ReportData &rd, datetime startTime, datetime endTime)
{
   if(m_journal == NULL) return;

   JournalEntry entries[];
   int count = 0;
   m_journal.ReadAllEntries(entries, count);

   double totalRR = 0.0;
   int rrCount = 0;

   for(int i = 0; i < count; i++)
   {
      if(entries[i].closeTime < startTime || entries[i].closeTime > endTime)
         continue;

      rd.totalTrades++;

      if(entries[i].outcome == OUTCOME_WIN) rd.wins++;
      else if(entries[i].outcome == OUTCOME_LOSS) rd.losses++;

      if(entries[i].profit > 0.0) rd.totalProfit += entries[i].profit;
      else rd.totalLoss += MathAbs(entries[i].profit);

      rd.netProfit += entries[i].profit;

      if(entries[i].riskRewardRatio > 0.0)
      {
         totalRR += entries[i].riskRewardRatio;
         rrCount++;
      }
   }

   if(rrCount > 0)
      rd.avgRiskReward = totalRR / (double)rrCount;
}

//--- Calculate max drawdown within a time period
double CReportGenerator::CalculateMaxDrawdown(datetime startTime, datetime endTime)
{
   if(m_journal == NULL) return 0.0;

   JournalEntry entries[];
   int count = 0;
   m_journal.ReadAllEntries(entries, count);

   double peak = 0.0;
   double maxDD = 0.0;
   double cumulative = 0.0;

   for(int i = 0; i < count; i++)
   {
      if(entries[i].closeTime < startTime || entries[i].closeTime > endTime)
         continue;

      cumulative += entries[i].profit;

      if(cumulative > peak)
         peak = cumulative;

      double dd = peak - cumulative;
      if(dd > maxDD)
         maxDD = dd;
   }

   return maxDD;
}

//--- Format report as string
string CReportGenerator::FormatReport(const ReportData &rd)
{
   string report = "";

   report += StringFormat("=== %s Report ===\n", rd.periodType);
   report += StringFormat("Period: %s to %s\n",
      TimeToString(rd.periodStart, TIME_DATE),
      TimeToString(rd.periodEnd, TIME_DATE));
   report += StringFormat("Total Trades: %d\n", rd.totalTrades);
   report += StringFormat("Wins: %d  |  Losses: %d\n", rd.wins, rd.losses);
   report += StringFormat("Win Rate: %.1f%%\n", rd.winRate);
   report += StringFormat("Profit Factor: %.2f\n", rd.profitFactor);
   report += StringFormat("Expectancy: %.2f\n", rd.expectancy);
   report += StringFormat("Avg Risk:Reward: %.2f\n", rd.avgRiskReward);
   report += StringFormat("Max Drawdown: %.1f\n", rd.maxDrawdown);
   report += StringFormat("Net Profit: %.2f\n", rd.netProfit);
   report += StringFormat("Total Profit: %.2f  |  Total Loss: %.2f\n", rd.totalProfit, rd.totalLoss);
   report += StringFormat("Best Symbol: %s  |  Worst Symbol: %s\n", rd.bestSymbol, rd.worstSymbol);
   report += StringFormat("Parameter Changes: %d\n", rd.parameterChanges);
   report += StringFormat("\nLearning Summary:\n%s\n", rd.learningSummary);
   report += StringFormat("\nRecommendations:\n%s\n", rd.recommendations);

   return report;
}

//--- Generate daily report
bool CReportGenerator::GenerateDailyReport()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime start = StructToTime(dt);
   datetime end = TimeCurrent();

   ReportData rd;
   GenerateReport(rd, start, end, "Daily");

   string report = FormatReport(rd);
   Print(report);

   WriteReportToFile(rd);
   return true;
}

//--- Generate weekly report
bool CReportGenerator::GenerateWeeklyReport()
{
   datetime end = TimeCurrent();
   datetime start = end - 7 * 24 * 60 * 60; // 7 days back

   ReportData rd;
   GenerateReport(rd, start, end, "Weekly");

   string report = FormatReport(rd);
   Print(report);

   WriteReportToFile(rd);
   return true;
}

//--- Generate monthly report
bool CReportGenerator::GenerateMonthlyReport()
{
   datetime end = TimeCurrent();
   datetime start = end - 30 * 24 * 60 * 60; // 30 days back

   ReportData rd;
   GenerateReport(rd, start, end, "Monthly");

   string report = FormatReport(rd);
   Print(report);

   WriteReportToFile(rd);
   return true;
}

//--- Get daily report as string
string CReportGenerator::GetDailyReportString()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime start = StructToTime(dt);
   datetime end = TimeCurrent();

   ReportData rd;
   GenerateReport(rd, start, end, "Daily");
   return FormatReport(rd);
}

//--- Get weekly report as string
string CReportGenerator::GetWeeklyReportString()
{
   datetime end = TimeCurrent();
   datetime start = end - 7 * 24 * 60 * 60;

   ReportData rd;
   GenerateReport(rd, start, end, "Weekly");
   return FormatReport(rd);
}

//--- Get monthly report as string
string CReportGenerator::GetMonthlyReportString()
{
   datetime end = TimeCurrent();
   datetime start = end - 30 * 24 * 60 * 60;

   ReportData rd;
   GenerateReport(rd, start, end, "Monthly");
   return FormatReport(rd);
}

//--- Write report to file
bool CReportGenerator::WriteReportToFile(const ReportData &rd)
{
   string fileName = StringFormat("%s\\reports.csv", m_folder);
   bool fileExists = FileIsExist(fileName, 0);

   int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      // Try creating the file
      handle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
         return false;
      fileExists = false;
   }

   FileSeek(handle, 0, SEEK_END);

   if(!fileExists)
   {
      FileWrite(handle, "PeriodType", "StartTime", "EndTime",
         "TotalTrades", "Wins", "Losses", "WinRate", "ProfitFactor",
         "Expectancy", "AvgRiskReward", "MaxDrawdown", "NetProfit",
         "TotalProfit", "TotalLoss", "BestSymbol", "WorstSymbol",
         "ParameterChanges", "LearningSummary", "Recommendations");
   }

   FileWrite(handle,
      rd.periodType,
      (string)rd.periodStart,
      (string)rd.periodEnd,
      (string)rd.totalTrades,
      (string)rd.wins,
      (string)rd.losses,
      DoubleToString(rd.winRate, 1),
      DoubleToString(rd.profitFactor, 2),
      DoubleToString(rd.expectancy, 2),
      DoubleToString(rd.avgRiskReward, 2),
      DoubleToString(rd.maxDrawdown, 1),
      DoubleToString(rd.netProfit, 2),
      DoubleToString(rd.totalProfit, 2),
      DoubleToString(rd.totalLoss, 2),
      rd.bestSymbol,
      rd.worstSymbol,
      (string)rd.parameterChanges,
      rd.learningSummary,
      rd.recommendations
   );

   FileClose(handle);
   return true;
}

#endif // AIEA_REPORT_GENERATOR_MQH
//+------------------------------------------------------------------+
