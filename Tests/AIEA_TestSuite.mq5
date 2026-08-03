//+------------------------------------------------------------------+
//| AIEA_TestSuite.mq5 — Unit Tests for AIEA Trader                   |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#property strict
#property description "Unit tests for AIEA Trader modules"
#property script_show_inputs

#include <Trade\Trade.mqh>
#include "AIEA\Config.mqh"
#include "AIEA\IndicatorEngine.mqh"
#include "AIEA\RiskManager.mqh"
#include "AIEA\TradingJournal.mqh"
#include "AIEA\LearningEngine.mqh"
#include "AIEA\PatternRecognition.mqh"
#include "AIEA\StrategyEvolution.mqh"
#include "AIEA\OptimizationEngine.mqh"
#include "AIEA\ReportGenerator.mqh"

//==================================================================
//  TEST FRAMEWORK
//==================================================================

int g_testsPassed = 0;
int g_testsFailed = 0;
int g_testsTotal  = 0;

void AssertTrue(bool condition, string testName)
{
   g_testsTotal++;
   if(condition)
   {
      g_testsPassed++;
      Print("[PASS] ", testName);
   }
   else
   {
      g_testsFailed++;
      Print("[FAIL] ", testName);
   }
}

void AssertEqual(double actual, double expected, string testName, double tolerance = 0.001)
{
   g_testsTotal++;
   if(MathAbs(actual - expected) < tolerance)
   {
      g_testsPassed++;
      Print("[PASS] ", testName);
   }
   else
   {
      g_testsFailed++;
      Print("[FAIL] ", testName, " (expected: ", DoubleToString(expected, 5),
            ", got: ", DoubleToString(actual, 5), ")");
   }
}

void AssertEqualInt(int actual, int expected, string testName)
{
   g_testsTotal++;
   if(actual == expected)
   {
      g_testsPassed++;
      Print("[PASS] ", testName);
   }
   else
   {
      g_testsFailed++;
      Print("[FAIL] ", testName, " (expected: ", expected, ", got: ", actual, ")");
   }
}

void PrintTestHeader(string section)
{
   Print("========================================");
   Print("  Testing: ", section);
   Print("========================================");
}

void PrintTestSummary()
{
   Print("========================================");
   Print("  TEST SUMMARY");
   Print("========================================");
   Print("  Total:   ", g_testsTotal);
   Print("  Passed:  ", g_testsPassed);
   Print("  Failed:  ", g_testsFailed);
   Print("  Rate:    ", DoubleToString((double)g_testsPassed / (double)(g_testsTotal > 0 ? g_testsTotal : 1) * 100.0, 1), "%");
   Print("========================================");
}

//==================================================================
//  TEST SUITES
//==================================================================

//--- Test Config module
void TestConfig()
{
   PrintTestHeader("Config Module");

   ParameterSet ps;
   CreateDefaultParameterSet(ps, 1);

   AssertEqualInt(ps.id, 1, "Default parameter set ID");
   AssertEqualInt(ps.rsiPeriod, 14, "Default RSI period");
   AssertEqualInt(ps.maFastPeriod, 20, "Default MA fast period");
   AssertEqualInt(ps.maSlowPeriod, 50, "Default MA slow period");
   AssertEqual(ps.bbDeviation, 2.0, "Default BB deviation");
   AssertEqual(ps.stopLossDistance, 1.5, "Default SL distance");
   AssertEqual(ps.takeProfitDistance, 3.0, "Default TP distance");
   AssertEqual(ps.minConfidence, 60.0, "Default min confidence");
   AssertEqual(ps.positionSizePercent, 1.0, "Default position size");
   AssertTrue(ps.status == PROFILE_ACTIVE, "Default profile status is ACTIVE");

   // Test clone
   ParameterSet clone;
   CloneParameterSet(ps, clone, 2, "Clone1");
   AssertEqualInt(clone.id, 2, "Cloned profile ID");
   AssertEqualInt(clone.rsiPeriod, 14, "Cloned RSI period matches source");
   AssertEqualInt(clone.totalTrades, 0, "Cloned profile has zero trades");
   AssertEqualInt(clone.wins, 0, "Cloned profile has zero wins");

   // Test journal entry init
   JournalEntry je;
   InitJournalEntry(je);
   AssertEqualInt(je.ticket, 0, "Init journal entry ticket");
   AssertTrue(je.outcome == OUTCOME_PENDING, "Init journal outcome is PENDING");

   // Test report data init
   ReportData rd;
   InitReportData(rd);
   AssertEqualInt(rd.totalTrades, 0, "Init report data total trades");
   AssertEqual(rd.winRate, 0.0, "Init report data win rate");
}

//--- Test RiskManager module
void TestRiskManager()
{
   PrintTestHeader("RiskManager Module");

   CRiskManager rm;
   rm.Init();

   AssertTrue(!rm.IsHalted(), "Risk manager not halted on init");
   AssertEqual(rm.GetDailyProfit(), 0.0, "Daily profit starts at zero");

   rm.RecordProfit(100.0);
   AssertEqual(rm.GetDailyProfit(), 100.0, "Daily profit after recording");

   rm.RecordProfit(-50.0);
   AssertEqual(rm.GetDailyProfit(), 50.0, "Daily profit after loss");

   rm.HaltTrading("Test halt");
   AssertTrue(rm.IsHalted(), "Risk manager halted after HaltTrading");
   AssertEqual(rm.GetHaltReason(), "Test halt", "Halt reason matches");

   rm.ResumeTrading();
   AssertTrue(!rm.IsHalted(), "Risk manager resumed");

   // Test lot size calculation
   double lotSize = rm.CalculateLotSize(1.0, 500.0, _Symbol, 0.001);
   AssertTrue(lotSize > 0.0, "Lot size is positive");

   // Test CanOpenPosition
   ParameterSet ps;
   CreateDefaultParameterSet(ps);
   bool canOpen = rm.CanOpenPosition(ps);
   AssertTrue(canOpen || rm.IsHalted(), "CanOpenPosition returns boolean without crash");
}

//--- Test TradingJournal module
void TestTradingJournal()
{
   PrintTestHeader("TradingJournal Module");

   CTradingJournal jnl;
   AssertTrue(jnl.Init("AIEA_Test"), "Journal initialization succeeds");

   // Write a test entry
   JournalEntry je;
   InitJournalEntry(je);
   je.ticket = 1001;
   je.symbol = "EURUSD";
   je.openTime = TimeCurrent();
   je.closeTime = TimeCurrent() + 3600;
   je.type = ORDER_TYPE_BUY;
   je.openPrice = 1.1000;
   je.closePrice = 1.1050;
   je.stopLoss = 1.0950;
   je.takeProfit = 1.1100;
   je.volume = 0.10;
   je.profit = 50.0;
   je.outcome = OUTCOME_WIN;
   je.confidence = 75.0;
   je.entryRationale = "Test buy signal";
   je.exitRationale = "Hit TP";
   je.profileId = 1;
   je.regime = REGIME_TRENDING;
   je.session = "London";
   je.lessonLearned = "Good trade";
   je.riskRewardRatio = 2.0;
   je.ruleCompliant = true;

   AssertTrue(jnl.WriteEntry(je), "Write journal entry succeeds");

   // Read entries
   JournalEntry entries[];
   int count = 0;
   AssertTrue(jnl.ReadAllEntries(entries, count), "Read all entries succeeds");
   AssertTrue(count >= 1, "At least one entry exists");

   if(count > 0)
   {
      AssertEqualInt(entries[0].ticket, 1001, "Read back correct ticket");
      AssertEqual(entries[0].profit, 50.0, "Read back correct profit");
   }

   // Test read by profile
   JournalEntry profileEntries[];
   int profileCount = 0;
   AssertTrue(jnl.ReadEntriesByProfile(1, profileEntries, profileCount),
              "Read entries by profile succeeds");
   AssertTrue(profileCount >= 1, "At least one entry for profile 1");

   // Cleanup test data
   jnl.ClearAll();
   AssertEqualInt(jnl.GetTotalEntries(), 0, "Journal cleared successfully");
}

//--- Test LearningEngine module
void TestLearningEngine()
{
   PrintTestHeader("LearningEngine Module");

   CTradingJournal jnl;
   jnl.Init("AIEA_Test");
   jnl.ClearAll();

   CLearningEngine le;
   le.Init(jnl, 5);

   // Create a test trade entry
   JournalEntry je;
   InitJournalEntry(je);
   je.ticket = 2001;
   je.symbol = "EURUSD";
   je.openPrice = 1.1000;
   je.closePrice = 1.1050;
   je.stopLoss = 1.0950;
   je.takeProfit = 1.1100;
   je.profit = 50.0;
   je.mfe = 60.0;
   je.mae = 20.0;
   je.outcome = OUTCOME_WIN;
   je.regime = REGIME_TRENDING;
   je.riskRewardRatio = 2.0;
   je.session = "London";
   je.hour = 10;
   je.confidence = 75.0;
   je.spreadAtEntry = 5.0;
   je.volatilityPercent = 0.8;

   // Analyze the trade
   ParameterSet ps;
   CreateDefaultParameterSet(ps);
   le.AnalyzeTrade(je, ps);

   // Verify assessments
   AssertTrue(je.entryQuality == ENTRY_OPTIMAL || je.entryQuality == ENTRY_AVERAGE,
              "Entry quality assessed for winning trade");
   AssertTrue(je.exitQuality != EXIT_UNKNOWN, "Exit quality assessed");
   AssertTrue(je.slAssessment != SL_UNKNOWN, "SL assessment done");
   AssertTrue(je.tpAssessment != TP_UNKNOWN, "TP assessment done");
   AssertTrue(StringLen(je.lessonLearned) > 0, "Lesson learned generated");

   // Test performance impact
   double impact = je.performanceImpact;
   AssertTrue(impact > 0.0, "Performance impact positive for winning trade");

   // Test with a losing trade
   JournalEntry je2;
   InitJournalEntry(je2);
   je2.ticket = 2002;
   je2.openPrice = 1.1000;
   je2.closePrice = 1.0950;
   je2.stopLoss = 1.0950;
   je2.takeProfit = 1.1100;
   je2.profit = -50.0;
   je2.mfe = 5.0;
   je2.mae = 50.0;
   je2.outcome = OUTCOME_LOSS;
   je2.regime = REGIME_VOLATILE;
   je2.riskRewardRatio = 2.0;

   le.AnalyzeTrade(je2, ps);

   AssertTrue(je2.entryQuality == ENTRY_POOR || je2.entryQuality == ENTRY_AVERAGE,
              "Entry quality assessed for losing trade");
   AssertTrue(je2.performanceImpact < 0.0, "Performance impact negative for losing trade");

   // Write entries for aggregate stats
   jnl.WriteEntry(je);
   jnl.WriteEntry(je2);

   double winRate = le.GetWinRate(1);
   AssertEqual(winRate, 50.0, "Win rate with 1 win and 1 loss", 10.0);

   int tradeCount = le.GetTradeCount(1);
   AssertEqualInt(tradeCount, 2, "Trade count for profile 1");

   // Cleanup
   jnl.ClearAll();
}

//--- Test StrategyEvolution module
void TestStrategyEvolution()
{
   PrintTestHeader("StrategyEvolution Module");

   CTradingJournal jnl;
   jnl.Init("AIEA_Test");
   jnl.ClearAll();

   CLearningEngine le;
   le.Init(jnl, 5);

   CStrategyEvolution se;
   se.Init(le, jnl);

   AssertTrue(se.GetProfileCount() >= 1, "At least one profile exists");
   AssertTrue(se.GetActiveProfileId() >= 1, "Active profile ID is valid");

   // Get active profile
   ParameterSet ps;
   AssertTrue(se.GetProfileById(se.GetActiveProfileId(), ps),
              "Get active profile succeeds");

   // Create a new profile
   int newId = se.CreateProfile("TestProfile2", ps);
   AssertTrue(newId > 0, "New profile created");

   // Set active profile
   AssertTrue(se.SetActiveProfile(newId), "Set active profile succeeds");
   AssertEqualInt(se.GetActiveProfileId(), newId, "Active profile updated");

   // Revert to original
   se.RevertToProfile(1);
   AssertEqualInt(se.GetActiveProfileId(), 1, "Reverted to profile 1");

   // Get profile summary
   string summary = se.GetProfileSummary();
   AssertTrue(StringLen(summary) > 0, "Profile summary generated");

   // Save and load
   AssertTrue(se.SaveProfiles(), "Save profiles succeeds");
   AssertTrue(se.LoadProfiles(), "Load profiles succeeds");

   // Cleanup
   jnl.ClearAll();
}

//--- Test PatternRecognition module
void TestPatternRecognition()
{
   PrintTestHeader("PatternRecognition Module");

   CTradingJournal jnl;
   jnl.Init("AIEA_Test");
   jnl.ClearAll();

   // Add test trades
   for(int i = 0; i < 5; i++)
   {
      JournalEntry je;
      InitJournalEntry(je);
      je.ticket = 3000 + i;
      je.symbol = "EURUSD";
      je.session = "London";
      je.weekday = 1;
      je.regime = (i % 2 == 0) ? REGIME_TRENDING : REGIME_RANGING;
      je.profit = (i % 3 == 0) ? -25.0 : 50.0;
      je.outcome = (je.profit > 0) ? OUTCOME_WIN : OUTCOME_LOSS;
      je.rsiAtEntry = (i % 2 == 0) ? 25.0 : 75.0;
      je.maFastAtEntry = (i % 2 == 0) ? 1.1010 : 1.0990;
      je.maSlowAtEntry = 1.1000;
      je.macdMainAtEntry = (i % 2 == 0) ? 0.0005 : -0.0005;
      je.macdSignalAtEntry = 0.0;
      je.stochMainAtEntry = (i % 2 == 0) ? 15.0 : 85.0;

      jnl.WriteEntry(je);
   }

   CPatternRecognition pr;
   pr.Init(jnl);

   // Analyze by symbol
   PatternStat symPatterns[];
   int symCount = 0;
   AssertTrue(pr.AnalyzeBySymbol(symPatterns, symCount), "Analyze by symbol succeeds");
   AssertTrue(symCount > 0, "Symbol patterns found");

   // Analyze by session
   PatternStat sessPatterns[];
   int sessCount = 0;
   AssertTrue(pr.AnalyzeBySession(sessPatterns, sessCount), "Analyze by session succeeds");

   // Analyze by weekday
   PatternStat dayPatterns[];
   int dayCount = 0;
   AssertTrue(pr.AnalyzeByWeekday(dayPatterns, dayCount), "Analyze by weekday succeeds");

   // Analyze by regime
   PatternStat regPatterns[];
   int regCount = 0;
   AssertTrue(pr.AnalyzeByRegime(regPatterns, regCount), "Analyze by regime succeeds");

   // Analyze by indicator combo
   PatternStat comboPatterns[];
   int comboCount = 0;
   AssertTrue(pr.AnalyzeByIndicatorCombo(comboPatterns, comboCount), "Analyze by indicator combo succeeds");

   // Test convenience queries
   string bestSymbol = pr.GetBestSymbol();
   AssertTrue(StringLen(bestSymbol) > 0, "Best symbol returned");

   string bestSession = pr.GetBestSession();
   AssertTrue(StringLen(bestSession) > 0, "Best session returned");

   // Cleanup
   jnl.ClearAll();
}

//--- Test OptimizationEngine module
void TestOptimizationEngine()
{
   PrintTestHeader("OptimizationEngine Module");

   CTradingJournal jnl;
   jnl.Init("AIEA_Test");
   jnl.ClearAll();

   CLearningEngine le;
   le.Init(jnl, 3);

   CPatternRecognition pr;
   pr.Init(jnl);

   CStrategyEvolution se;
   se.Init(le, jnl);

   COptimizationEngine oe;
   oe.Init(se, le, pr, jnl, 3);

   // Add enough trades for optimization
   for(int i = 0; i < 10; i++)
   {
      JournalEntry je;
      InitJournalEntry(je);
      je.ticket = 4000 + i;
      je.symbol = "EURUSD";
      je.profileId = se.GetActiveProfileId();
      je.openPrice = 1.1000;
      je.closePrice = (i % 4 == 0) ? 1.0950 : 1.1050;
      je.stopLoss = 1.0950;
      je.takeProfit = 1.1100;
      je.profit = (i % 4 == 0) ? -50.0 : 25.0;
      je.outcome = (je.profit > 0) ? OUTCOME_WIN : OUTCOME_LOSS;
      je.mfe = (je.profit > 0) ? 60.0 : 10.0;
      je.mae = (je.profit > 0) ? 15.0 : 50.0;
      je.spreadAtEntry = 10.0;
      je.slippage = 2.0;
      je.confidence = 65.0;
      je.riskRewardRatio = 2.0;
      je.volatilityPercent = 0.8;

      // Set assessments to trigger optimization
      if(i < 6)
      {
         je.slAssessment = SL_TOO_TIGHT;
         je.tpAssessment = TP_TOO_CLOSE;
      }
      else
      {
         je.slAssessment = SL_APPROPRIATE;
         je.tpAssessment = TP_APPROPRIATE;
      }

      ParameterSet testPs;
      CreateDefaultParameterSet(testPs);
      le.AnalyzeTrade(je, testPs); // Just for lesson generation
      jnl.WriteEntry(je);
   }

   // Run optimization
   int activeId = se.GetActiveProfileId();
   bool optResult = oe.RunOptimization(activeId);
   AssertTrue(optResult, "Optimization run completes");

   // Check for proposed changes
   ProposedChange pending[];
   int pendingCount = 0;
   oe.GetPendingChanges(pending, pendingCount);

   // There should be some proposed changes
   if(pendingCount > 0)
   {
      // Approve first change
      AssertTrue(oe.ApproveChange(pending[0].changeId), "Approve first change succeeds");

      // Reject if there's a second
      if(pendingCount > 1)
      {
         AssertTrue(oe.RejectChange(pending[1].changeId, "Test rejection"),
                      "Reject second change succeeds");
      }
   }

   // Test changes summary
   string summary = oe.GetChangesSummary();
   AssertTrue(StringLen(summary) > 0, "Changes summary generated");

   // Save and load changes
   AssertTrue(oe.SaveChanges(), "Save changes succeeds");
   AssertTrue(oe.LoadChanges(), "Load changes succeeds");

   // Cleanup
   jnl.ClearAll();
}

//--- Test ReportGenerator module
void TestReportGenerator()
{
   PrintTestHeader("ReportGenerator Module");

   CTradingJournal jnl;
   jnl.Init("AIEA_Test");
   jnl.ClearAll();

   CLearningEngine le;
   le.Init(jnl, 5);

   CPatternRecognition pr;
   pr.Init(jnl);

   CStrategyEvolution se;
   se.Init(le, jnl);

   COptimizationEngine oe;
   oe.Init(se, le, pr, jnl, 5);

   CReportGenerator rg;
   rg.Init(jnl, le, se, pr, oe);

   // Add some test trades
   for(int i = 0; i < 5; i++)
   {
      JournalEntry je;
      InitJournalEntry(je);
      je.ticket = 5000 + i;
      je.symbol = "EURUSD";
      je.closeTime = TimeCurrent() - i * 3600;
      je.openTime = je.closeTime - 3600;
      je.profit = (i % 3 == 0) ? -30.0 : 40.0;
      je.outcome = (je.profit > 0) ? OUTCOME_WIN : OUTCOME_LOSS;
      je.riskRewardRatio = 1.5;
      jnl.WriteEntry(je);
   }

   // Generate reports
   string dailyReport = rg.GetDailyReportString();
   AssertTrue(StringLen(dailyReport) > 0, "Daily report generated");

   string weeklyReport = rg.GetWeeklyReportString();
   AssertTrue(StringLen(weeklyReport) > 0, "Weekly report generated");

   string monthlyReport = rg.GetMonthlyReportString();
   AssertTrue(StringLen(monthlyReport) > 0, "Monthly report generated");

   // Check report contains expected fields
   AssertTrue(StringFind(dailyReport, "Win Rate") >= 0, "Daily report contains Win Rate");
   AssertTrue(StringFind(dailyReport, "Profit Factor") >= 0, "Daily report contains Profit Factor");
   AssertTrue(StringFind(dailyReport, "Expectancy") >= 0, "Daily report contains Expectancy");

   // Cleanup
   jnl.ClearAll();
}

//==================================================================
//  MAIN TEST RUNNER
//==================================================================

void OnStart()
{
   Print("========================================");
   Print("  AIEA Trader — Unit Test Suite");
   Print("========================================");

   TestConfig();
   TestRiskManager();
   TestTradingJournal();
   TestLearningEngine();
   TestStrategyEvolution();
   TestPatternRecognition();
   TestOptimizationEngine();
   TestReportGenerator();

   PrintTestSummary();
}

//+------------------------------------------------------------------+
