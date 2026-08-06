//+------------------------------------------------------------------+
//| Config.mqh — Configuration, Enums, and Parameter Definitions      |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_CONFIG_MQH
#define AIEA_CONFIG_MQH

//==================================================================
//  ENUMERATIONS
//==================================================================

enum ENUM_MARKET_REGIME
{
   REGIME_UNKNOWN   = 0,
   REGIME_TRENDING  = 1,
   REGIME_RANGING   = 2,
   REGIME_VOLATILE  = 3
};

enum ENUM_TRADE_OUTCOME
{
   OUTCOME_PENDING  = 0,
   OUTCOME_WIN      = 1,
   OUTCOME_LOSS     = 2,
   OUTCOME_BREAKEVEN= 3
};

enum ENUM_ENTRY_QUALITY
{
   ENTRY_UNKNOWN   = 0,
   ENTRY_OPTIMAL   = 1,
   ENTRY_AVERAGE   = 2,
   ENTRY_POOR      = 3
};

enum ENUM_EXIT_QUALITY
{
   EXIT_UNKNOWN    = 0,
   EXIT_OPTIMAL    = 1,
   EXIT_AVERAGE    = 2,
   EXIT_POOR       = 3
};

enum ENUM_SL_ASSESSMENT
{
   SL_UNKNOWN      = 0,
   SL_TOO_TIGHT    = 1,
   SL_APPROPRIATE  = 2,
   SL_TOO_WIDE     = 3
};

enum ENUM_TP_ASSESSMENT
{
   TP_UNKNOWN      = 0,
   TP_TOO_CLOSE    = 1,
   TP_APPROPRIATE  = 2,
   TP_TOO_FAR      = 3
};

enum ENUM_PROFILE_STATUS
{
   PROFILE_ACTIVE    = 0,
   PROFILE_PROMOTED  = 1,
   PROFILE_RETIRED   = 2,
   PROFILE_BACKUP    = 3
};

enum ENUM_APPROVAL_STATE
{
   APPROVAL_NONE     = 0,
   APPROVAL_PENDING  = 1,
   APPROVAL_APPROVED = 2,
   APPROVAL_REJECTED = 3
};

//==================================================================
//  PARAMETER SET — a complete strategy configuration profile
//==================================================================

struct ParameterSet
{
   int      id;
   string   name;
   int      rsiPeriod;
   int      maFastPeriod;
   int      maSlowPeriod;
   int      bbPeriod;
   double   bbDeviation;
   int      macdFast;
   int      macdSlow;
   int      macdSignal;
   int      stochK;
   int      stochD;
   int      stochSlow;
   double   atrMultiplier;
   int      atrPeriod;
   double   stopLossDistance;
   double   takeProfitDistance;
   double   trailingStop;
   double   breakEvenTrigger;
   double   positionSizePercent;
   int      tradingStartHour;
   int      tradingEndHour;
   bool     newsFilter;
   bool     volatilityFilter;
   double   maxSpreadPoints;
   double   minConfidence;
   double   maxDailyLossPercent;
   int      maxOpenPositions;
   double   maxDrawdownPercent;

   int      totalTrades;
   int      wins;
   int      losses;
   double   totalProfit;
   double   profitFactor;
   double   avgRiskReward;
   double   score;
   ENUM_PROFILE_STATUS status;
   datetime created;
   datetime lastUpdated;
};

void CreateDefaultParameterSet(ParameterSet &ps, int id = 1)
{
   ps.id                  = id;
   ps.name                = "Default";
   ps.rsiPeriod           = 14;
   ps.maFastPeriod        = 20;
   ps.maSlowPeriod        = 50;
   ps.bbPeriod            = 20;
   ps.bbDeviation         = 2.0;
   ps.macdFast            = 12;
   ps.macdSlow            = 26;
   ps.macdSignal          = 9;
   ps.stochK              = 14;
   ps.stochD              = 3;
   ps.stochSlow           = 3;
   ps.atrPeriod           = 14;
   ps.atrMultiplier       = 1.5;
   ps.stopLossDistance    = 1.5;
   ps.takeProfitDistance  = 3.0;
   ps.trailingStop        = 1.0;
   ps.breakEvenTrigger    = 0.5;
   ps.positionSizePercent = 1.0;
   ps.tradingStartHour    = 8;
   ps.tradingEndHour      = 20;
   ps.newsFilter          = true;
   ps.volatilityFilter    = true;
   ps.maxSpreadPoints     = 30.0;
   ps.minConfidence       = 45.0;
   ps.maxDailyLossPercent = 5.0;
   ps.maxOpenPositions    = 3;
   ps.maxDrawdownPercent  = 20.0;
   ps.totalTrades         = 0;
   ps.wins                = 0;
   ps.losses              = 0;
   ps.totalProfit         = 0.0;
   ps.profitFactor        = 0.0;
   ps.avgRiskReward       = 0.0;
   ps.score               = 50.0;
   ps.status              = PROFILE_ACTIVE;
   ps.created             = TimeCurrent();
   ps.lastUpdated         = TimeCurrent();
}

void CloneParameterSet(const ParameterSet &src, ParameterSet &dst, int newId, string newName)
{
   dst = src;
   dst.id          = newId;
   dst.name        = newName;
   dst.totalTrades = 0;
   dst.wins        = 0;
   dst.losses      = 0;
   dst.totalProfit = 0.0;
   dst.profitFactor = 0.0;
   dst.avgRiskReward = 0.0;
   dst.score       = 50.0;
   dst.status      = PROFILE_ACTIVE;
   dst.created     = TimeCurrent();
   dst.lastUpdated = TimeCurrent();
}

//==================================================================
//  TRADE JOURNAL ENTRY
//==================================================================

struct JournalEntry
{
   int          ticket;
   string       symbol;
   datetime     openTime;
   datetime     closeTime;
   int          type;
   double       openPrice;
   double       closePrice;
   double       stopLoss;
   double       takeProfit;
   double       volume;
   double       profit;
   double       mfe;
   double       mae;
   double       spreadAtEntry;
   double       slippage;
   double       confidence;
   string       entryRationale;
   string       exitRationale;
   ENUM_TRADE_OUTCOME  outcome;
   ENUM_ENTRY_QUALITY  entryQuality;
   ENUM_EXIT_QUALITY   exitQuality;
   ENUM_SL_ASSESSMENT  slAssessment;
   ENUM_TP_ASSESSMENT  tpAssessment;
   ENUM_MARKET_REGIME  regime;
   int          profileId;
   double       rsiAtEntry;
   double       maFastAtEntry;
   double       maSlowAtEntry;
   double       bbUpperAtEntry;
   double       bbLowerAtEntry;
   double       macdMainAtEntry;
   double       macdSignalAtEntry;
   double       stochMainAtEntry;
   double       atrAtEntry;
   double       volatilityPercent;
   int          weekday;
   int          hour;
   string       session;
   string       lessonLearned;
   double       riskRewardRatio;
   bool         ruleCompliant;
   double       performanceImpact;
};

void InitJournalEntry(JournalEntry &je)
{
   je.ticket           = 0;
   je.symbol          = "";
   je.openTime        = 0;
   je.closeTime       = 0;
   je.type            = -1;
   je.openPrice       = 0.0;
   je.closePrice      = 0.0;
   je.stopLoss        = 0.0;
   je.takeProfit      = 0.0;
   je.volume          = 0.0;
   je.profit          = 0.0;
   je.mfe             = 0.0;
   je.mae             = 0.0;
   je.spreadAtEntry   = 0.0;
   je.slippage        = 0.0;
   je.confidence      = 0.0;
   je.entryRationale  = "";
   je.exitRationale   = "";
   je.outcome         = OUTCOME_PENDING;
   je.entryQuality    = ENTRY_UNKNOWN;
   je.exitQuality     = EXIT_UNKNOWN;
   je.slAssessment    = SL_UNKNOWN;
   je.tpAssessment    = TP_UNKNOWN;
   je.regime          = REGIME_UNKNOWN;
   je.profileId       = 0;
   je.rsiAtEntry      = 0.0;
   je.maFastAtEntry   = 0.0;
   je.maSlowAtEntry   = 0.0;
   je.bbUpperAtEntry  = 0.0;
   je.bbLowerAtEntry  = 0.0;
   je.macdMainAtEntry = 0.0;
   je.macdSignalAtEntry = 0.0;
   je.stochMainAtEntry  = 0.0;
   je.atrAtEntry      = 0.0;
   je.volatilityPercent = 0.0;
   je.weekday         = 0;
   je.hour            = 0;
   je.session         = "";
   je.lessonLearned   = "";
   je.riskRewardRatio = 0.0;
   je.ruleCompliant   = true;
   je.performanceImpact = 0.0;
}

//==================================================================
//  PATTERN STAT
//==================================================================

struct PatternStat
{
   string   category;
   string   condition;
   int      trades;
   int      wins;
   int      losses;
   double   totalProfit;
   double   winRate;
   double   avgProfit;
   double   score;
};

void InitPatternStat(PatternStat &ps)
{
   ps.category     = "";
   ps.condition    = "";
   ps.trades       = 0;
   ps.wins         = 0;
   ps.losses       = 0;
   ps.totalProfit  = 0.0;
   ps.winRate      = 0.0;
   ps.avgProfit    = 0.0;
   ps.score        = 50.0;
}

//==================================================================
//  PROPOSED CHANGE
//==================================================================

struct ProposedChange
{
   int          changeId;
   int          profileId;
   string       parameter;
   double       oldValue;
   double       newValue;
   string       rationale;
   double       expectedImprovement;
   int          evidenceTrades;
   ENUM_APPROVAL_STATE approval;
   datetime     proposed;
   datetime     reviewed;
   string       reviewerNote;
};

void InitProposedChange(ProposedChange &pc)
{
   pc.changeId          = 0;
   pc.profileId         = 0;
   pc.parameter         = "";
   pc.oldValue          = 0.0;
   pc.newValue          = 0.0;
   pc.rationale         = "";
   pc.expectedImprovement = 0.0;
   pc.evidenceTrades    = 0;
   pc.approval          = APPROVAL_NONE;
   pc.proposed          = TimeCurrent();
   pc.reviewed          = 0;
   pc.reviewerNote      = "";
}

//==================================================================
//  REPORT DATA
//==================================================================

struct ReportData
{
   datetime   periodStart;
   datetime   periodEnd;
   string     periodType;
   int        totalTrades;
   int        wins;
   int        losses;
   double     winRate;
   double     profitFactor;
   double     expectancy;
   double     avgRiskReward;
   double     maxDrawdown;
   double     totalProfit;
   double     totalLoss;
   double     netProfit;
   int        bestProfileId;
   int        worstProfileId;
   string     bestSymbol;
   string     worstSymbol;
   int        parameterChanges;
   string     learningSummary;
   string     recommendations;
};

void InitReportData(ReportData &rd)
{
   rd.periodStart    = 0;
   rd.periodEnd      = 0;
   rd.periodType     = "";
   rd.totalTrades   = 0;
   rd.wins          = 0;
   rd.losses        = 0;
   rd.winRate       = 0.0;
   rd.profitFactor  = 0.0;
   rd.expectancy    = 0.0;
   rd.avgRiskReward = 0.0;
   rd.maxDrawdown   = 0.0;
   rd.totalProfit   = 0.0;
   rd.totalLoss     = 0.0;
   rd.netProfit     = 0.0;
   rd.bestProfileId = 0;
   rd.worstProfileId = 0;
   rd.bestSymbol    = "";
   rd.worstSymbol   = "";
   rd.parameterChanges = 0;
   rd.learningSummary = "";
   rd.recommendations = "";
}

#endif // AIEA_CONFIG_MQH
//+------------------------------------------------------------------+
